import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/soundbooks/soundbooks_http.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:http/http.dart' as http;

class SoundBooksSearchService {
  static const _baseUrl = SoundBooksHttp.baseUrl;

  /// DataLife Engine search returns 10 results per page via POST.
  Future<List<Audiobook>> search(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/index.php?do=search&subaction=search'),
        headers: {
          ...SoundBooksHttp.headers,
          'Content-Type':
              'application/x-www-form-urlencoded',
        },
        body: {
          'do': 'search',
          'subaction': 'search',
          'story': query,
          'search_start': page.toString(),
        },
      );

      if (SoundBooksHttp.isBlocked(response)) {
        throw const SoundBooksBlockedException();
      }

      if (response.statusCode != 200) {
        throw Exception(
            'Sound-Books search failed with ${response.statusCode}');
      }

      return _parseSearchResults(response.body, limit: pageSize);
    } on SoundBooksBlockedException catch (e) {
      throw Exception(e.toString());
    } catch (e) {
      throw Exception('Sound-Books search failed: $e');
    }
  }

  List<Audiobook> _parseSearchResults(
    String html, {
    required int limit,
  }) {
    // DLE book cards use class="short-item"
    final cards = html.split(RegExp(r'<div[^>]*class="short-item"[^>]*>'));
    if (cards.length <= 1) return [];

    final results = <Audiobook>[];
    for (final rawCard in cards.skip(1)) {
      if (results.length >= limit) break;
      final card = rawCard;

      // The cover image uses lazy-loading: data-src (not src)
      var imagePath = _match(card,
          RegExp(r'<img[^>]*data-src="([^"]+)"', dotAll: true));
      // Fallback to src if data-src is absent
      if (imagePath.isEmpty) {
        imagePath = _match(card,
            RegExp(r'<img[^>]*src="([^"]+)"', dotAll: true));
      }

      // Title link also contains the book URL — text is "Title - Author"
      final href = _match(card,
          RegExp(r'<a[^>]*class="short-title"[^>]*href="([^"]+)"', dotAll: true));
      final titleAndAuthor = _cleanText(_match(card,
          RegExp(r'<a[^>]*class="short-title"[^>]*>(.*?)</a>', dotAll: true)));

      // Split "Title - Author" — author is after the last " - "
      String title = titleAndAuthor;
      String author = 'Unknown';
      final sepIdx = titleAndAuthor.lastIndexOf(' - ');
      if (sepIdx > 0) {
        title = titleAndAuthor.substring(0, sepIdx).trim();
        author = titleAndAuthor.substring(sepIdx + 3).trim();
      }

      // Description from short-text div
      final description = _cleanText(_match(card,
          RegExp(r'<div[^>]*class="short-text"[^>]*>(.*?)</div>', dotAll: true)));

      // Duration: "Триває: HH:MM:SS"
      final durationMatch =
          RegExp(r'Триває:\s*([\d:]+)', caseSensitive: false)
              .firstMatch(card);
      final duration = durationMatch?.group(1) ?? '';

      // Views count (eye icon) — used as a popularity proxy
      final viewsMatch = RegExp(
              r'class="fal fa-eye"></span>([\d\s]+)</div>',
              caseSensitive: false)
          .firstMatch(card);
      final viewsText =
          viewsMatch?.group(1)?.replaceAll(RegExp(r'\s'), '') ?? '';
      final views = int.tryParse(viewsText) ?? 0;

      // Categories from folder links
      final categories = <String>[];
      for (final m in RegExp(
              r'<a[^>]*href="https://sound-books\.net/[a-z0-9-]+/"[^>]*>(.*?)</a>',
              dotAll: true)
          .allMatches(card)) {
        final cat = _cleanText(m.group(1)!);
        // Strip "Аудіокниги " prefix from category labels
        final cleanCat = cat.replaceAll(RegExp(r'^Аудіокниги\s*'), '');
        if (cleanCat.isNotEmpty) categories.add(cleanCat);
      }

      if (href.isEmpty || title.isEmpty) continue;

      final fullCover = imagePath.startsWith('http')
          ? imagePath
          : '$_baseUrl$imagePath';

      results.add(Audiobook.fromMap({
        'id': href,
        'title': title,
        'author': author.isNotEmpty ? author : 'Unknown',
        'description': description,
        'lowQCoverImage': fullCover,
        'totalTime': duration,
        'downloads': views,
        'rating': null,
        'reviews': views,
        'subject': categories,
        'size': 0,
        'language': 'uk',
        'origin': AppConstants.soundBooksDirName,
      }));
    }

    return results;
  }

  String _match(String input, RegExp exp) {
    final match = exp.firstMatch(input);
    return match?.group(1)?.trim() ?? '';
  }

  String _cleanText(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>', dotAll: true), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+', dotAll: true), ' ')
        .trim();
  }
}
