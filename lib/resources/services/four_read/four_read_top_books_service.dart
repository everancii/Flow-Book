import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_guard.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FourReadTopBooksService {
  static const _baseUrl = 'https://4read.org';
  static const _topUrl = '$_baseUrl/top-100.html';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Referer': _baseUrl,
  };

  Future<List<Audiobook>> fetchTopBooks() async {
    try {
      final response = await http.get(Uri.parse(_topUrl), headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('4Read Top 100 fetch failed: ${response.statusCode}');
      }
      return _parseTopBooks(response.body);
    } catch (e) {
      throw Exception('4Read Top 100 fetch failed: $e');
    }
  }

  @visibleForTesting
  List<Audiobook> parseTopBooksFromHtml(String html) => _parseTopBooks(html);

  List<Audiobook> _parseTopBooks(String html) {
    // Cards are delimited by the linek card class used on the top-100 page.
    final cards =
        html.split('<div class="linek d-flex ai-center has-overlay card">');
    if (cards.length <= 1) return [];

    final results = <Audiobook>[];
    int rank = 1;

    for (final rawCard in cards.skip(1)) {
      final href = _match(rawCard, RegExp(r'<a href="([^"]+)"'));
      final combined = _cleanText(
        _match(rawCard, RegExp(r'linek__title[^>]*>(.*?)</div>', dotAll: true)),
      );
      final imagePath = _match(
        rawCard,
        RegExp(r'<img[^>]+src="([^"]+)"'),
      );

      if (href.isEmpty || combined.isEmpty) {
        rank++;
        continue;
      }

      final (title, author) = splitTitleAuthor(combined);
      final coverUrl =
          imagePath.startsWith('http') ? imagePath : '$_baseUrl$imagePath';
      final articleUrl = href.startsWith('http') ? href : '$_baseUrl$href';

      final rawBook = Audiobook.fromMap({
        'id': articleUrl,
        'title': title,
        'author': author.isNotEmpty ? author : 'Unknown',
        'description': '',
        'lowQCoverImage': coverUrl,
        'totalTime': '',
        'downloads': rank, // reuse downloads field as positional rank
        'rating': 0.0,
        'reviews': 0,
        'subject': [],
        'size': 0,
        'language': 'uk',
        'origin': AppConstants.fourReadDirName,
      });

      final guarded = FourReadOpenGuard.validateAndNormalizeAudiobook(
        rawBook,
        stage: 'top_books_parse',
      );
      if (!guarded.isValid) {
        AppLogger.warning(
          'Skipping invalid top-books card rank=$rank id=${rawBook.id}: ${guarded.failure?.code}',
          'FourReadTopBooks',
        );
        rank++;
        continue;
      }

      results.add(guarded.audiobook!);
      rank++;
    }

    return results;
  }

  /// Splits `"Title - Author"` on the **last** occurrence of ` - `.
  /// Returns `(title, author)`. If no separator is found, author is empty.
  static (String, String) splitTitleAuthor(String combined) {
    final idx = combined.lastIndexOf(' - ');
    if (idx == -1) return (combined, '');
    return (
      combined.substring(0, idx).trim(),
      combined.substring(idx + 3).trim()
    );
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
