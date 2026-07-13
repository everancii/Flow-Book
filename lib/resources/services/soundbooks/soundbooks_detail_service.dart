import 'dart:convert';

import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/services/soundbooks/soundbooks_http.dart';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;

const int _hex0 = 48; // '0'
const int _hex9 = 57; // '9'
const int _hexA = 65; // 'A'
const int _hexF = 70; // 'F'
const int _hexa = 97; // 'a'
const int _hexf = 102; // 'f'

bool _isHexDigit(int c) =>
    (c >= _hex0 && c <= _hex9) ||
    (c >= _hexA && c <= _hexF) ||
    (c >= _hexa && c <= _hexf);

const Set<int> _pathSafe = {
  0x2D, // -
  0x2E, // .
  0x5F, // _
  0x7E, // ~
  0x2F, // /
  0x3A, // :
  0x40, // @
  0x21, // !
  0x24, // $
  0x26, // &
  0x27, // '
  0x28, // (
  0x29, // )
  0x2A, // *
  0x2B, // +
  0x2C, // ,
  0x3B, // ;
  0x3D, // =
};

const String _hexAlphabet = '0123456789ABCDEF';

/// Percent-encodes [raw] into an RFC 3986-compliant URI string.
///
/// Walks the UTF-8 byte stream of [raw] and:
///   * preserves already-valid `%XX` hex sequences (no double encoding),
///   * preserves unreserved chars (`A-Za-z0-9`) and the path-safe set above,
///   * encodes space as `%20`,
///   * encodes every other byte as uppercase `%XX`.
///
/// A `%` that is not followed by two hex digits is encoded as `%25`.
String encodeTrackUrl(String raw) {
  final bytes = utf8.encode(raw);
  final out = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b == 0x25 /* % */ &&
        i + 2 < bytes.length &&
        _isHexDigit(bytes[i + 1]) &&
        _isHexDigit(bytes[i + 2])) {
      // Preserve existing %XX sequence (uppercase the hex digits for
      // canonical form).
      out.writeCharCode(0x25);
      out.writeCharCode(bytes[i + 1]);
      out.writeCharCode(bytes[i + 2]);
      i += 3;
      continue;
    }
    if (b == 0x20 /* space */) {
      out.write('%20');
      i += 1;
      continue;
    }
    if (_pathSafe.contains(b) ||
        (b >= 0x41 && b <= 0x5A) /* A-Z */ ||
        (b >= 0x61 && b <= 0x7A) /* a-z */ ||
        (b >= 0x30 && b <= 0x39) /* 0-9 */) {
      out.writeCharCode(b);
      i += 1;
      continue;
    }
    out.writeCharCode(0x25);
    out.writeCharCode(_hexAlphabet.codeUnitAt((b >> 4) & 0x0F));
    out.writeCharCode(_hexAlphabet.codeUnitAt(b & 0x0F));
    i += 1;
  }
  return out.toString();
}

class SoundBooksDetailResult {
  final List<AudiobookFile> files;
  final String? description;

  SoundBooksDetailResult({required this.files, this.description});
}

class SoundBooksDetailService {
  Future<Either<String, SoundBooksDetailResult>> getAudiobookFiles(
      String bookUrl) async {
    try {
      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse(bookUrl),
          headers: SoundBooksHttp.headers,
        );

        if (SoundBooksHttp.isBlocked(response)) {
          return const Left(SoundBooksBlockedException.message);
        }

        if (response.statusCode != 200) {
          return Left(
              'Failed to load Sound-Books page: ${response.statusCode}');
        }

        final html = utf8.decode(response.bodyBytes);

        // 1) Extract the PlayerJS playlist URL: file:"https://...m3u"
        final fileMatch = RegExp(r'file:"([^"]+\.m3u)"').firstMatch(html);
        if (fileMatch == null) {
          return Left(
            'Could not find audio playlist. This book may not be available '
            'for streaming.',
          );
        }
        final m3uUrl = fileMatch.group(1)!;

        // 2) Extract description from JSON-LD Book structured data
        String? description;
        final jsonLdMatch = RegExp(
          r'<script type="application/ld\+json">\s*(\{.*?"@type"\s*:\s*"Book".*?\})\s*</script>',
          dotAll: true,
        ).firstMatch(html);
        if (jsonLdMatch != null) {
          try {
            final bookJson =
                jsonDecode(jsonLdMatch.group(1)!) as Map<String, dynamic>;
            description = bookJson['description'] as String?;
          } catch (e) {
            AppLogger.debug('SoundBooks: failed to parse JSON-LD: $e');
          }
        }
        // Fallback: meta description
        if (description == null || description.isEmpty) {
          final metaMatch = RegExp(
            r'<meta name="description" content="([^"]*)"',
          ).firstMatch(html);
          if (metaMatch != null) {
            description = metaMatch.group(1);
          }
        }

        // 3) Fetch the .m3u playlist — it is a plain-text file with one
        //    direct MP3 URL per line (no #EXTM3U header on this site).
        //    The server sends Content-Type: audio/mpegurl with NO charset,
        //    so response.body would default to Latin-1 and corrupt UTF-8
        //    Cyrillic filenames. Decode bodyBytes as UTF-8 explicitly.
        final m3uResponse = await client.get(
          Uri.parse(m3uUrl),
          headers: SoundBooksHttp.headers,
        );
        if (m3uResponse.statusCode != 200) {
          return Left(
              'Failed to load playlist: ${m3uResponse.statusCode}');
        }

        final m3uBody = utf8.decode(m3uResponse.bodyBytes);
        final files = _parseM3uPlaylist(m3uBody, m3uUrl);

        if (files.isEmpty) {
          return Left('No audio tracks found');
        }

        return Right(SoundBooksDetailResult(
          files: files,
          description: description,
        ));
      } finally {
        client.close();
      }
    } catch (e) {
      return Left('Failed to load Sound-Books audiobook: $e');
    }
  }

  /// Parses a plain-text .m3u playlist into [AudiobookFile]s.
  ///
  /// sound-books.net m3u files contain one direct MP3 URL per line (no
  /// #EXTM3U / #EXTINF headers). Each track's title is derived from the
  /// filename in the URL.
  List<AudiobookFile> _parseM3uPlaylist(String body, String m3uUrl) {
    final lines = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();

    // Resolve relative URLs against the m3u URL's base.
    final m3uBase = Uri.parse(m3uUrl);

    final files = <AudiobookFile>[];
    for (var i = 0; i < lines.length; i++) {
      final rawUrl = lines[i];
      if (rawUrl.isEmpty) continue;

      // Resolve relative URLs and percent-encode non-ASCII / spaces per
      // RFC 3986. sound-books.net playlists contain raw Cyrillic
      // filenames that must be encoded before the player can fetch them.
      String url;
      try {
        final uri = Uri.parse(rawUrl);
        if (uri.isAbsolute) {
          // Absolute URL — encode directly.
          url = encodeTrackUrl(rawUrl);
        } else {
          // Relative URL — resolve against m3u base, then encode the
          // resulting absolute URL.
          url = encodeTrackUrl(m3uBase.resolve(rawUrl).toString());
        }
      } catch (_) {
        url = encodeTrackUrl(rawUrl);
      }

      // Derive a human-readable title from the URL filename.
      String title;
      try {
        final lastSegment =
            rawUrl.split('/').where((s) => s.isNotEmpty).last;
        // Try to decode percent-encoding; if the URL is raw (no %),
        // Uri.decodeComponent may throw on non-ASCII — fall back to the
        // raw segment which is already human-readable.
        String decoded;
        try {
          decoded = Uri.decodeComponent(lastSegment);
        } catch (_) {
          decoded = lastSegment;
        }
        // Strip extension.
        title = decoded.replaceAll(RegExp(r'\.[^.]+$'), '');
      } catch (_) {
        title = 'Track ${i + 1}';
      }

      files.add(AudiobookFile.fromMap({
        'identifier': 'soundbooks',
        'title': title,
        'name': title,
        'track': i + 1,
        'size': 0,
        'length': 0, // duration unknown until probed by the player
        'url': url,
        'highQCoverImage': null,
        'startMs': null,
        'durationMs': null,
      }));
    }
    return files;
  }
}
