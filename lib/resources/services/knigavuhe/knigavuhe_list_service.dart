import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:http/http.dart' as http;

class KnigavuheListService {
  static const _baseUrl = 'https://knigavuhe.org';
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Referer': _baseUrl,
  };

  Future<List<Audiobook>> fetchNewBooks() => _fetchList('$_baseUrl/new/');
  Future<List<Audiobook>> fetchPopularBooks({String period = 'alltime'}) =>
      _fetchList('$_baseUrl/popular/?w=$period');
  Future<List<Audiobook>> fetchRatingBooks({String period = 'alltime'}) =>
      _fetchList('$_baseUrl/rating/?w=$period');

  Future<List<Audiobook>> _fetchList(String url) async {
    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to load: ${response.statusCode}');
      }
      return _parseBooks(response.body);
    } catch (e) {
      throw Exception('Failed to load knigavuhe list: $e');
    }
  }

  List<Audiobook> _parseBooks(String html) {
    final cards = html.split(RegExp(r'<div[^>]*class="bookkitem"[^>]*>'));
    if (cards.length <= 1) return [];

    final results = <Audiobook>[];

    for (final rawCard in cards.skip(1)) {
      final href = _match(
          rawCard,
          RegExp(r'<a[^>]*href="([^"]+)"[^>]*>',
              dotAll: true, caseSensitive: false));
      final title = _cleanText(
          _match(rawCard, RegExp(r'<a[^>]*class="bookkitem_name"[^>]*>(.*?)</a>', dotAll: true)));
      final author = _cleanText(
          _match(rawCard, RegExp(r'<span[^>]*class="bookkitem_author"[^>]*>.*?<a[^>]*>(.*?)</a>', dotAll: true)));
      final imagePath = _match(
          rawCard, RegExp(r'<img[^>]*class="bookkitem_cover_img"[^>]*src="([^"]+)"', dotAll: true));
      final description = _cleanText(
          _match(rawCard, RegExp(r'<div[^>]*class="bookkitem_about"[^>]*>(.*?)</div>', dotAll: true)));

      if (href.isEmpty || title.isEmpty) continue;

      results.add(Audiobook.fromMap({
        'id': href.startsWith('http') ? href : '$_baseUrl$href',
        'title': title,
        'author': author.isNotEmpty ? author : 'Unknown',
        'description': description,
        'lowQCoverImage':
            imagePath.startsWith('http') ? imagePath : '$_baseUrl$imagePath',
        'totalTime': '',
        'downloads': 0,
        'rating': null,
        'reviews': 0,
        'subject': [],
        'size': 0,
        'language': 'ru',
        'origin': AppConstants.knigavuheDirName,
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
