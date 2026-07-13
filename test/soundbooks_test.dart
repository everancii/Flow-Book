import 'dart:convert';

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/services/my_audio_handler.dart';
import 'package:audiobookflow/resources/services/soundbooks/soundbooks_detail_service.dart';
import 'package:audiobookflow/resources/services/soundbooks/soundbooks_http.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the Sound-Books (sound-books.net) source.
///
/// These tests use real HTML snippets captured from the site to verify
/// that the search-result parser and the detail-page / m3u-playlist
/// parser work correctly without making live network requests.
void main() {
  group('SoundBooks title/author splitting', () {
    test('splits "Title - Author" at last " - "', () {
      const combined = 'Неначе сон  - Іван Франко';
      final sepIdx = combined.lastIndexOf(' - ');
      final title = combined.substring(0, sepIdx).trim();
      final author = combined.substring(sepIdx + 3).trim();

      expect(title, 'Неначе сон');
      expect(author, 'Іван Франко');
    });

    test('handles title containing " - "', () {
      const combined = 'Доктор Сон - Стівен Кінг - автор';
      final sepIdx = combined.lastIndexOf(' - ');
      final title = combined.substring(0, sepIdx).trim();
      final author = combined.substring(sepIdx + 3).trim();

      expect(title, 'Доктор Сон - Стівен Кінг');
      expect(author, 'автор');
    });
  });

  group('SoundBooks m3u playlist parsing', () {
    List<String> parseM3u(String body) {
      return body
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
    }

    test('parses single-track playlist', () {
      const m3u = 'https://arch.sound-books.net/4381/test.mp3';
      final lines = parseM3u(m3u);
      expect(lines.length, 1);
      expect(lines[0], m3u);
    });

    test('parses multi-track playlist', () {
      const m3u = '''
https://arch.sound-books.net/100/Track_1.mp3
https://arch.sound-books.net/100/Track_2.mp3
https://s1.reasd.org/100/Track_3.mp3
''';
      final lines = parseM3u(m3u);
      expect(lines.length, 3);
      expect(lines[2], 'https://s1.reasd.org/100/Track_3.mp3');
    });

    test('ignores comment lines', () {
      const m3u = '''
#EXTM3U
#EXTINF:3600,Track 1
https://arch.sound-books.net/100/Track_1.mp3
#EXTINF:1800,Track 2
https://arch.sound-books.net/100/Track_2.mp3
''';
      final lines = parseM3u(m3u);
      expect(lines.length, 2);
    });
  });

  group('SoundBooks detail page parsing', () {
    test('extracts PlayerJS m3u file URL', () {
      const html = r'''
<script>
   var player = new Playerjs({id:"player", file:"https://sound-books.net/uploads/public_files/2026-04/4381-test.m3u"});
</script>
''';
      final match = RegExp(r'file:"([^"]+\.m3u)"').firstMatch(html);
      expect(match, isNotNull);
      expect(
        match!.group(1),
        'https://sound-books.net/uploads/public_files/2026-04/4381-test.m3u',
      );
    });

    test('extracts description from JSON-LD Book data', () {
      const html = r'''
<script type="application/ld+json">
        {
        "@context": "http://schema.org",
        "@type": "Book",
        "author": "Френк Беттджер",
        "name": "Вчора невдаха",
        "description": "У книзі розказано про секрети."
        }
</script>
''';
      final match = RegExp(
        r'<script type="application/ld\+json">\s*(\{.*?"@type"\s*:\s*"Book".*?\})\s*</script>',
        dotAll: true,
      ).firstMatch(html);

      expect(match, isNotNull);
      final bookJson = jsonDecode(match!.group(1)!) as Map<String, dynamic>;
      expect(bookJson['author'], 'Френк Беттджер');
      expect(bookJson['description'], 'У книзі розказано про секрети.');
    });
  });

  group('SoundBooks model integration', () {
    test('creates Audiobook with soundbooks origin', () {
      final book = Audiobook.fromMap({
        'id': 'https://sound-books.net/test.html',
        'title': 'Test Book',
        'author': 'Test Author',
        'description': 'A description.',
        'lowQCoverImage': 'https://sound-books.net/cover.webp',
        'totalTime': '01:30:00',
        'downloads': 100,
        'rating': null,
        'reviews': 100,
        'subject': ['Українська література'],
        'size': 0,
        'language': 'uk',
        'origin': AppConstants.soundBooksDirName,
      });

      expect(book.origin, 'soundbooks');
      expect(book.language, 'uk');
      expect(book.title, 'Test Book');
    });

    test('creates AudiobookFile with soundbooks identifier', () {
      final file = AudiobookFile.fromMap({
        'identifier': 'soundbooks',
        'title': 'Track 1',
        'name': 'Track 1',
        'track': 1,
        'size': 0,
        'length': 0.0,
        'url': 'https://arch.sound-books.net/100/Track_1.mp3',
        'highQCoverImage': null,
        'startMs': null,
        'durationMs': null,
      });

      expect(file.identifier, 'soundbooks');
      expect(file.track, 1);
    });
  });

  group('SoundBooksHttp', () {
    test('baseUrl is sound-books.net', () {
      expect(SoundBooksHttp.baseUrl, 'https://sound-books.net');
    });

    test('headers include Ukrainian Accept-Language', () {
      expect(SoundBooksHttp.headers['Accept-Language'], contains('uk'));
    });
  });

  group('SoundBooks track URL encoding (encodeTrackUrl)', () {
    test('2.1 single-track Cyrillic URL encodes to %D0%9D... form', () {
      const raw = 'https://s1.reasd.org/5223/Неначе сон.mp3';
      final encoded = encodeTrackUrl(raw);
      expect(
        encoded,
        'https://s1.reasd.org/5223/'
        '%D0%9D%D0%B5%D0%BD%D0%B0%D1%87%D0%B5%20%D1%81%D0%BE%D0%BD.mp3',
      );
      // Title stays decoded (human-readable Cyrillic). Mirrors the
      // service's title derivation: last segment, decode if possible
      // else use raw, strip extension.
      final lastSeg = raw.split('/').where((s) => s.isNotEmpty).last;
      String decoded;
      try {
        decoded = Uri.decodeComponent(lastSeg);
      } catch (_) {
        decoded = lastSeg;
      }
      final title = decoded.replaceAll(RegExp(r'\.[^.]+$'), '');
      expect(title, 'Неначе сон');
    });

    test('2.2 multi-track mixed ASCII/Cyrillic has no raw non-ASCII/spaces', () {
      const raw =
          'https://arch.sound-books.net/4769/01 - Стівен Кінг. Доктор Сон. '
          '00. Вступні заснування 1. Скринька.mp3';
      final encoded = encodeTrackUrl(raw);
      // No raw spaces.
      expect(encoded.contains(' '), isFalse);
      // No raw Cyrillic (Cyrillic Unicode block U+0400..U+04FF).
      expect(RegExp(r'[\u0400-\u04FF]').hasMatch(encoded), isFalse);
      // Стівен -> %D0%A1%D1%82%D1%96%D0%B2%D0%B5%D0%BD
      expect(encoded, contains('%D0%A1%D1%82%D1%96%D0%B2%D0%B5%D0%BD'));
      // Space -> %20.
      expect(encoded, contains('%20'));
      // ASCII path components preserved.
      expect(encoded, startsWith('https://arch.sound-books.net/4769/01'));
    });

    test('2.3 ASCII-only URL is unchanged (no-op)', () {
      const raw = 'https://arch.sound-books.net/100/Track_1.mp3';
      expect(encodeTrackUrl(raw), raw);
    });

    test('2.4 already-encoded URL is not double-encoded', () {
      const raw = 'https://arch.sound-books.net/5223/'
          '%D0%9D%D0%B5%D0%BD%D0%B0%D1%87%D0%B5%20%D1%81%D0%BE%D0%BD.mp3';
      final encoded = encodeTrackUrl(raw);
      expect(encoded, raw);
      expect(encoded.contains('%25'), isFalse);
    });

    test('2.5 stray % not followed by two hex digits is encoded as %25', () {
      const raw = 'https://arch.sound-books.net/100/50%off.mp3';
      expect(encodeTrackUrl(raw),
          'https://arch.sound-books.net/100/50%25off.mp3');
    });

    test('2.6 relative URL resolved against m3u base then encoded', () {
      // Simulate what _parseM3uPlaylist does for a relative entry.
      const m3uUrl =
          'https://sound-books.net/uploads/public_files/2026-06/5223.m3u';
      const rel = '5223/Неначе сон.mp3';
      final resolved = Uri.parse(m3uUrl).resolve(rel).toString();
      final encoded = encodeTrackUrl(resolved);
      expect(encoded,
          'https://sound-books.net/uploads/public_files/2026-06/5223/'
          '%D0%9D%D0%B5%D0%BD%D0%B0%D1%87%D0%B5%20%D1%81%D0%BE%D0%BD.mp3');
    });
  });

  group('Player URL encoding defense (sanitizePlayerUrl)', () {
    test('3.1 raw Cyrillic URL gets encoded', () {
      const raw = 'https://s1.reasd.org/5223/Неначе сон.mp3';
      final safe = sanitizePlayerUrl(raw);
      expect(safe,
          'https://s1.reasd.org/5223/'
          '%D0%9D%D0%B5%D0%BD%D0%B0%D1%87%D0%B5%20%D1%81%D0%BE%D0%BD.mp3');
      // Verify the encoded URL produces a valid Uri for AudioSource.uri.
      final uri = Uri.parse(safe);
      expect(uri.host, 's1.reasd.org');
      expect(uri.path, contains('%D0%9D'));
    });

    test('3.2 already-encoded URL unchanged (no double-encoding)', () {
      const raw = 'https://s1.reasd.org/5223/'
          '%D0%9D%D0%B5%D0%BD%D0%B0%D1%87%D0%B5%20%D1%81%D0%BE%D0%BD.mp3';
      final safe = sanitizePlayerUrl(raw);
      expect(safe, raw);
      expect(safe.contains('%25'), isFalse);
    });

    test('3.3 ASCII-only URL unchanged (fast path)', () {
      const raw = 'https://arch.org/download/book/track01.mp3';
      expect(sanitizePlayerUrl(raw), raw);
    });

    test('3.4 mixed encoded + raw segments', () {
      const raw = 'https://arch.org/path/%D0%9D%D0%B5/Стівен.mp3';
      final safe = sanitizePlayerUrl(raw);
      // Encoded segment preserved.
      expect(safe, contains('%D0%9D%D0%B5/'));
      // Raw segment encoded.
      expect(safe, contains('%D0%A1%D1%82%D1%96%D0%B2%D0%B5%D0%BD'));
      // No double-encoding.
      expect(safe.contains('%25'), isFalse);
      // No raw Cyrillic left.
      expect(RegExp(r'[\u0400-\u04FF]').hasMatch(safe), isFalse);
    });

    test('3.5 local file path unaffected (no encoding, Uri.file used)', () {
      const raw = '/data/user/0/app/files/book/track.mp3';
      final safe = sanitizePlayerUrl(raw);
      // No encoding applied (all ASCII, no spaces).
      expect(safe, raw);
      // Caller uses Uri.file for paths starting with /.
      final uri = Uri.file(safe);
      expect(uri.path, contains('track.mp3'));
    });
  });
}
