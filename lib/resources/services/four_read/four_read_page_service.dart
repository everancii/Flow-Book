import 'dart:convert';
import 'dart:io';

import 'package:audiobookflow/resources/services/four_read/four_read_auth_service.dart';
import 'package:audiobookflow/utils/app_logger.dart';

class FourReadPageData {
  final String articleUrl;
  final String title;
  final String author;
  final String coverImage;
  final String playlistExpression;
  final String description;

  const FourReadPageData({
    required this.articleUrl,
    required this.title,
    required this.author,
    required this.coverImage,
    required this.playlistExpression,
    this.description = '',
  });
}

class FourReadTrack {
  final String title;
  final String url;
  final double? durationSeconds;

  const FourReadTrack({
    required this.title,
    required this.url,
    required this.durationSeconds,
  });
}

class FourReadPageService {
  static const _baseUrl = 'https://4read.org';

  /// Cache of article URL → description so the BLoC can read it without
  /// an extra HTTP request.
  static final Map<String, String> descriptionCache = {};

  /// Parses [url] tolerantly: bare `%` signs and raw non-ASCII characters
  /// (e.g. Cyrillic filenames) are encoded before retrying.
  static Uri _safeUri(String url) {
    // Fix bare % signs first (not followed by two hex digits).
    final fixedPercent = url.replaceAllMapped(
      RegExp(r'%(?![0-9A-Fa-f]{2})'),
      (_) => '%25',
    );
    // Uri.encodeFull encodes raw non-ASCII (Cyrillic etc.) while preserving
    // already-valid %XX sequences.  It does NOT re-encode '%' itself, so
    // the fixedPercent step above must run first.
    final encoded = Uri.encodeFull(fixedPercent);
    try {
      return Uri.parse(encoded);
    } catch (_) {
      return Uri.parse('https://4read.org/');
    }
  }

  /// Fetches [url] as a UTF-8 string, following redirects and tolerating
  /// Location headers with illegal percent-encoding (which [package:http]
  /// cannot handle because it calls Uri.parse on redirect URLs internally).
  static Future<String> safeHttpGetBody(
    String url,
    Map<String, String> headers,
  ) async {
    Uri uri = _safeUri(url);
    AppLogger.debug('[safeHttpGetBody] starting url=$url → uri=$uri');
    final client = HttpClient()..autoUncompress = true;
    try {
      for (var hop = 0; hop < 5; hop++) {
        AppLogger.debug('[safeHttpGetBody] hop=$hop uri=$uri');
        final req = await client.getUrl(uri);
        req.followRedirects =
            false; // handle redirects manually via _safeResolve
        headers.forEach((k, v) => req.headers.set(k, v));
        final resp = await req.close();
        AppLogger.debug(
            '[safeHttpGetBody] hop=$hop status=${resp.statusCode} isRedirect=${resp.isRedirect}');
        if (resp.isRedirect) {
          final loc = resp.headers.value('location') ?? '';
          AppLogger.debug('[safeHttpGetBody] redirect loc=$loc');
          await resp.drain<void>();
          uri = _safeResolve(uri, loc);
          AppLogger.debug('[safeHttpGetBody] resolved uri=$uri');
          continue;
        }
        final bytes = await resp.fold<List<int>>(
          [],
          (list, chunk) => list..addAll(chunk),
        );
        if (resp.statusCode != 200) {
          throw Exception('4Read fetch failed: ${resp.statusCode}');
        }
        return utf8.decode(bytes, allowMalformed: true);
      }
      throw Exception('Too many redirects for $url');
    } finally {
      client.close(force: false);
    }
  }

  /// Resolves [location] against [base], tolerating bad percent-encoding
  /// in the Location header.
  static Uri _safeResolve(Uri base, String location) {
    if (location.isEmpty) return base;
    // Use resolveUri(Uri) instead of resolve(String) to avoid Dart calling
    // Uri.parse internally on the raw Location header string.
    return base.resolveUri(_safeUri(location));
  }

  Future<FourReadPageData> fetchPageData(String articleUrl) async {
    final authService = FourReadAuthService();
    final authHeaders = await authService.getAuthHeaders();
    
    final html = await FourReadPageService.safeHttpGetBody(
      articleUrl,
      authHeaders,
    );
    final description = _extractDescription(html);
    descriptionCache[articleUrl] = description;
    return FourReadPageData(
      articleUrl: articleUrl,
      title: _extractTitle(html),
      author: _extractAuthor(html),
      coverImage: _extractCoverImage(html),
      playlistExpression: _extractPlaylistExpression(html),
      description: description,
    );
  }

  List<FourReadTrack> parsePlaylist(String playlistText) {
    final trimmed = playlistText.trimLeft();
    if (trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(playlistText);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map(
                (item) => FourReadTrack(
                  title: _cleanText(item['title']?.toString() ?? ''),
                  url: item['file']?.toString() ?? '',
                  durationSeconds:
                      double.tryParse(item['duration']?.toString() ?? ''),
                ),
              )
              .where((track) => track.url.isNotEmpty)
              .toList();
        }
      } catch (_) {
        // Fall back to M3U parsing below.
      }
    }

    final normalized = playlistText.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final tracks = <FourReadTrack>[];

    String? pendingTitle;
    double? pendingDuration;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        final details = line.substring('#EXTINF:'.length);
        final commaIndex = details.indexOf(',');
        final durationPart =
            commaIndex == -1 ? details : details.substring(0, commaIndex);
        final titlePart =
            commaIndex == -1 ? '' : details.substring(commaIndex + 1).trim();
        pendingDuration = double.tryParse(durationPart.trim());
        pendingTitle = titlePart;
        continue;
      }

      if (line.startsWith('#')) {
        continue;
      }

      final url = line.startsWith('http')
          ? _safeUri(line).toString()
          : Uri.parse(_baseUrl).resolveUri(_safeUri(line)).toString();
      tracks.add(
        FourReadTrack(
          title: pendingTitle?.trim().isNotEmpty == true
              ? pendingTitle!.trim()
              : _titleFromUrl(url, tracks.length + 1),
          url: url,
          durationSeconds: pendingDuration,
        ),
      );
      pendingTitle = null;
      pendingDuration = null;
    }

    return tracks;
  }

  String resolvePlaylistExpression(
    String expression, {
    required Map<String, dynamic> vars,
  }) {
    var resolved = expression;
    for (var i = 1; i <= 5; i++) {
      final key = 'v$i';
      final value = vars[key];
      if (value == null) continue;
      resolved = resolved.replaceAll('{$key}', value.toString());
    }

    resolved = resolved.replaceAll(
      RegExp(r'\{v[1-5]\}', caseSensitive: false),
      '',
    );

    if (resolved.startsWith('http')) {
      return _safeUri(resolved).toString();
    }

    final cleaned = resolved.trim();
    if (cleaned.isEmpty) {
      return Uri.parse(_baseUrl).resolve('/').toString();
    }

    final fileName = _safeUri(cleaned).pathSegments.isNotEmpty
        ? _safeUri(cleaned).pathSegments.last
        : cleaned;

    if (fileName.toLowerCase().endsWith('.m3u')) {
      final path = cleaned.startsWith('m3u/')
          ? '/$cleaned'
          : cleaned.startsWith('/m3u/')
              ? cleaned
              : '/m3u/$fileName';
      return Uri.parse(_baseUrl).resolveUri(_safeUri(path)).toString();
    }

    return Uri.parse(_baseUrl).resolveUri(_safeUri(cleaned)).toString();
  }

  String _extractTitle(String html) {
    final metaTitle = _match(
      html,
      RegExp(r'<meta property="og:title" content="([^"]+)"'),
    );
    if (metaTitle.isNotEmpty) {
      return _cleanText(metaTitle);
    }

    final spanTitle = _match(
      html,
      RegExp(r'<span itemprop="name">([^<]+)</span>'),
    );
    return _cleanText(spanTitle);
  }

  String _extractAuthor(String html) {
    final author = _match(
      html,
      RegExp(r'<p itemprop="author"[^>]*>\s*<a[^>]*>(.*?)</a>', dotAll: true),
    );
    return _cleanText(author.isNotEmpty ? author : 'Unknown');
  }

  String _extractDescription(String html) {
    // The description div uses two different inner layouts:
    //   Layout A: <div style="text-align:justify;">text<br>text</div>
    //   Layout B: <div itemprop="description"><p>...</p><p>...</p></div>
    //
    // The outer div usually contains nested divs so we must NOT rely on
    // `</div>` as the outer boundary — instead scan 6 KB from the opening tag.

    final openMatch = RegExp(
      r'<div[^>]+(?:itemprop="description"|class="pmovie__text[^"]*")[^>]*>',
    ).firstMatch(html);

    if (openMatch != null) {
      final start = openMatch.end;
      final chunk = html.substring(start, (start + 6000).clamp(0, html.length));

      // Stop before noise sections
      final stopMatch = RegExp(
        r'Теги#|Ютуб канал|YouTube канал|Подякувати диктор|Підтримати диктор|<div[^>]+class="(?:pmovie__subtitle|pmovie__player|comments)',
      ).firstMatch(chunk);
      final body =
          stopMatch != null ? chunk.substring(0, stopMatch.start) : chunk;

      // Layout A: text inside <div style="text-align:justify;"> with <br> breaks
      final justifyMatch = RegExp(
        r'<div[^>]+style="text-align:justify[^"]*"[^>]*>(.*?)</div>',
        dotAll: true,
      ).firstMatch(body);
      if (justifyMatch != null) {
        final text = justifyMatch
            .group(1)!
            .replaceAll(RegExp(r'<br\s*/?>'), '\n')
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .trim();
        final cleaned = _cleanText(text);
        if (cleaned.isNotEmpty) return cleaned;
      }

      // Layout B: text inside <p> tags
      final paragraphs = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true)
          .allMatches(body)
          .map((m) {
            final raw = m.group(1) ?? '';
            return _cleanText(raw.replaceAll(RegExp(r'<[^>]+>'), ' ').trim());
          })
          .where((p) =>
              p.isNotEmpty &&
              !p.startsWith('Теги#') &&
              !p.contains('Ютуб канал') &&
              !p.contains('Підтримати') &&
              !p.contains('Подякувати'))
          .join('\n\n');
      if (paragraphs.isNotEmpty) return paragraphs;
    }

    // Fallback: og:description meta tag
    final og = _match(
      html,
      RegExp(r'<meta property="og:description" content="([^"]+)"'),
    );
    if (og.isNotEmpty) return _cleanText(og);

    // Fallback: meta name description
    final meta = _match(
      html,
      RegExp(r'<meta name="description" content="([^"]+)"'),
    );
    if (meta.isNotEmpty) return _cleanText(meta);

    return '';
  }

  String _extractCoverImage(String html) {
    final image = _match(
      html,
      RegExp(r'<meta property="og:image" content="([^"]+)"'),
    );
    return image.isNotEmpty ? image : '';
  }

  String _extractPlaylistExpression(String html) {
    final match = _match(
      html,
      RegExp(
        r'new Playerjs\(\{id:"playerjs1",file:"([^"]+)"\}\);',
        dotAll: true,
      ),
    );
    return _cleanText(match);
  }

  String _titleFromUrl(String url, int trackIndex) {
    final uri = Uri.tryParse(url);
    final segment =
        uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '';
    if (segment.isNotEmpty) {
      try {
        return Uri.decodeComponent(segment);
      } catch (_) {
        return segment; // malformed percent-encoding — use raw segment
      }
    }
    return 'Chapter $trackIndex';
  }

  String _match(String input, RegExp exp) {
    final match = exp.firstMatch(input);
    return match?.group(1)?.trim() ?? '';
  }

  String _cleanText(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}
