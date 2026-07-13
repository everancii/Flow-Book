import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/soundbooks/soundbooks_http.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:http/http.dart' as http;

class SoundBooksListService {
  static const _baseUrl = SoundBooksHttp.baseUrl;

  /// Latest books — the homepage lists newest books with pagination.
  /// `/page/2/`, `/page/3/`, etc.
  Future<List<Audiobook>> fetchLatestBooks({int page = 1}) async {
    final url = page <= 1 ? '$_baseUrl/' : '$_baseUrl/page/$page/';
    return _fetchList(url);
  }

  /// Popular books — the site's Top-100 page at
  /// `/top-100-audioknyg-nashogu-saitu.html`.
  Future<List<Audiobook>> fetchTopBooks() async {
    return _fetchList('$_baseUrl/top-100-audioknyg-nashogu-saitu.html');
  }

  /// Popular carousel books — extracted from the homepage `tile-item`
  /// carousel ("Популярні аудіокниги"). These have less metadata than
  /// `short-item` cards, so we return what the tile provides.
  Future<List<Audiobook>> fetchPopularCarousel() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/'),
        headers: SoundBooksHttp.headers,
      );
      if (SoundBooksHttp.isBlocked(response)) {
        throw const SoundBooksBlockedException();
      }
      if (response.statusCode != 200) {
        throw Exception('Failed to load: ${response.statusCode}');
      }
      return _parseTileItems(response.body);
    } on SoundBooksBlockedException catch (e) {
      throw Exception(e.toString());
    } catch (e) {
      throw Exception('Failed to load Sound-Books popular: $e');
    }
  }

  Future<List<Audiobook>> _fetchList(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: SoundBooksHttp.headers,
      );
      if (SoundBooksHttp.isBlocked(response)) {
        throw const SoundBooksBlockedException();
      }
      if (response.statusCode != 200) {
        throw Exception('Failed to load: ${response.statusCode}');
      }
      return _parseBooks(response.body);
    } on SoundBooksBlockedException catch (e) {
      throw Exception(e.toString());
    } catch (e) {
      throw Exception('Failed to load Sound-Books list: $e');
    }
  }

  /// Parses `short-item` cards (used by homepage latest, top-100, search).
  List<Audiobook> _parseBooks(String html) {
    final cards = html.split(RegExp(r'<div[^>]*class="short-item"[^>]*>'));
    if (cards.length <= 1) return [];

    final results = <Audiobook>[];

    for (final rawCard in cards.skip(1)) {
      final card = rawCard;

      var imagePath = _match(card,
          RegExp(r'<img[^>]*data-src="([^"]+)"', dotAll: true));
      if (imagePath.isEmpty) {
        imagePath = _match(card,
            RegExp(r'<img[^>]*src="([^"]+)"', dotAll: true));
      }

      final href = _match(card, RegExp(
          r'<a[^>]*class="short-title"[^>]*href="([^"]+)"',
          dotAll: true));
      final titleAndAuthor = _cleanText(_match(card,
          RegExp(r'<a[^>]*class="short-title"[^>]*>(.*?)</a>', dotAll: true)));

      String title = titleAndAuthor;
      String author = 'Unknown';
      final sepIdx = titleAndAuthor.lastIndexOf(' - ');
      if (sepIdx > 0) {
        title = titleAndAuthor.substring(0, sepIdx).trim();
        author = titleAndAuthor.substring(sepIdx + 3).trim();
      }

      final description = _cleanText(_match(card,
          RegExp(r'<div[^>]*class="short-text"[^>]*>(.*?)</div>', dotAll: true)));

      final durationMatch =
          RegExp(r'Триває:\s*([\d:]+)', caseSensitive: false)
              .firstMatch(card);
      final duration = durationMatch?.group(1) ?? '';

      final viewsMatch = RegExp(
              r'class="fal fa-eye"></span>([\d\s]+)</div>',
              caseSensitive: false)
          .firstMatch(card);
      final viewsText =
          viewsMatch?.group(1)?.replaceAll(RegExp(r'\s'), '') ?? '';
      final views = int.tryParse(viewsText) ?? 0;

      final categories = <String>[];
      for (final m in RegExp(
              r'<a[^>]*href="https://sound-books\.net/[a-z0-9-]+/"[^>]*>(.*?)</a>',
              dotAll: true)
          .allMatches(card)) {
        final cat = _cleanText(m.group(1)!);
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

  /// Parses `tile-item` carousel cards from the homepage popular section.
  /// These only provide title, cover, and URL (no author/description).
  List<Audiobook> _parseTileItems(String html) {
    final popIdx = html.indexOf('Популярні аудіокниги');
    if (popIdx < 0) return [];

    final sectIdx = html.indexOf('class="sect"', popIdx);
    final section = sectIdx > 0
        ? html.substring(popIdx, sectIdx)
        : html.substring(popIdx, popIdx + 20000);

    final cards = section.split(RegExp(r'<div[^>]*class="tile-item"[^>]*>'));
    if (cards.length <= 1) return [];

    final results = <Audiobook>[];

    for (final rawCard in cards.skip(1)) {
      final card = rawCard;

      final href = _match(card, RegExp(
          r'<a[^>]*class="tile-img[^"]*"[^>]*href="([^"]+)"',
          dotAll: true));
      final title = _cleanText(_match(card,
          RegExp(r'<div[^>]*class="tile-title"[^>]*>(.*?)</div>', dotAll: true)));

      var imagePath = _match(card,
          RegExp(r'<img[^>]*data-src="([^"]+)"', dotAll: true));
      if (imagePath.isEmpty) {
        imagePath = _match(card,
            RegExp(r'<img[^>]*src="([^"]+)"', dotAll: true));
      }

      if (href.isEmpty || title.isEmpty) continue;

      final fullCover = imagePath.startsWith('http')
          ? imagePath
          : '$_baseUrl$imagePath';

      results.add(Audiobook.fromMap({
        'id': href,
        'title': title,
        'author': 'Unknown',
        'description': '',
        'lowQCoverImage': fullCover,
        'totalTime': '',
        'downloads': 0,
        'rating': null,
        'reviews': 0,
        'subject': [],
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
