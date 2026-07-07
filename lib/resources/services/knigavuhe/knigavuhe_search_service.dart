import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/knigavuhe/knigavuhe_http.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:http/http.dart' as http;

class KnigavuheSearchService {
  static const _baseUrl = KnigavuheHttp.baseUrl;

  Future<List<Audiobook>> search(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final url = '$_baseUrl/search/?q=$encoded&page=$page';
      final response = await http.get(
        Uri.parse(url),
        headers: KnigavuheHttp.headers,
      );

      if (KnigavuheHttp.isBlocked(response)) {
        throw const KnigavuheBlockedException();
      }

      if (response.statusCode != 200) {
        throw Exception('Knigavuhe search failed with ${response.statusCode}');
      }

      return _parseSearchResults(response.body, limit: pageSize);
    } on KnigavuheBlockedException catch (e) {
      throw Exception(e.toString());
    } catch (e) {
      throw Exception('Knigavuhe search failed: $e');
    }
  }

  List<Audiobook> _parseSearchResults(
    String html, {
    required int limit,
  }) {
    // Split by book item cards - knigavuhe uses class="bookkitem"
    final cards = html.split(RegExp(r'<div[^>]*class="bookkitem"[^>]*>'));
    if (cards.length <= 1) return [];

    final results = <Audiobook>[];
    for (final rawCard in cards.skip(1)) {
      if (results.length >= limit) break;
      final card = rawCard;

      // Extract fields using actual knigavuhe class names
      final href = _match(
          card,
          RegExp(r'<a[^>]*href="([^"]+)"[^>]*>',
              dotAll: true, caseSensitive: false));
      final title = _cleanText(_match(
          card,
          RegExp(r'<a[^>]*class="bookkitem_name"[^>]*>(.*?)</a>',
              dotAll: true)));
      final author = _cleanText(_match(
          card,
          RegExp(
              r'<span[^>]*class="bookkitem_author"[^>]*>.*?<a[^>]*>(.*?)</a>',
              dotAll: true)));
      final imagePath = _match(
          card,
          RegExp(r'<img[^>]*class="bookkitem_cover_img"[^>]*src="([^"]+)"',
              dotAll: true));

      // Duration format: "X часов Y минут" or "X час Y минут"
      final durationMatch = RegExp(r'(\d+)\s+(?:часов?|час)\s+(\d+)\s+минут',
              caseSensitive: false)
          .firstMatch(card);
      final duration = durationMatch != null
          ? '${durationMatch.group(1)} часов ${durationMatch.group(2)} минут'
          : '';

      // Downloads number - look for numbers in bookkitem_meta_label -not_last
      final downloadsMatch = RegExp(
              r'class="bookkitem_meta_label -not_last">([\d\s]+)</span>',
              caseSensitive: false)
          .firstMatch(card);
      final downloadsText = downloadsMatch?.group(1)?.replaceAll(' ', '') ?? '';

      // Description - class is bookkitem_about
      final descriptionMatch = RegExp(
              r'<div[^>]*class="bookkitem_about"[^>]*>(.*?)</div>',
              dotAll: true)
          .firstMatch(card);
      final description = descriptionMatch != null
          ? _cleanText(descriptionMatch.group(1)!)
          : '';

      if (href.isEmpty || title.isEmpty) continue;

      // Extract narrators - look for 'Читает' or 'Читают' and extract links after it
      final narratorMatch = RegExp(r'Чита(?:ет|ют).*?>(.*?)</a>',
              dotAll: true, caseSensitive: false)
          .firstMatch(card);
      final narrators =
          narratorMatch != null ? _cleanText(narratorMatch.group(1)!) : '';

      String finalDescription = description;
      if (narrators.isNotEmpty) {
        finalDescription = description.isNotEmpty
            ? '$description\n\nNarrated by: $narrators'
            : 'Narrated by: $narrators';
      }

      final rawBook = Audiobook.fromMap({
        'id': href.startsWith('http') ? href : '$_baseUrl$href',
        'title': title,
        'author': author.isNotEmpty ? author : 'Unknown',
        'description': finalDescription,
        'lowQCoverImage':
            imagePath.startsWith('http') ? imagePath : '$_baseUrl$imagePath',
        'totalTime': duration, // Keep as string format "X часов Y минут"
        'downloads': int.tryParse(downloadsText) ?? 0,
        'rating': null, // knigavuhe doesn't show rating in search results
        'reviews': int.tryParse(downloadsText) ?? 0,
        'subject': [],
        'size': 0,
        'language': 'ru',
        'origin': AppConstants.knigavuheDirName,
      });

      results.add(rawBook);
    }

    return results;
  }

  String _match(String input, RegExp exp) {
    final match = exp.firstMatch(input);
    return match?.group(1)?.trim() ?? '';
  }

  String _cleanText(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>', dotAll: true), '') // Remove HTML tags
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+', dotAll: true), ' ') // Normalize whitespace
        .trim();
  }
}
