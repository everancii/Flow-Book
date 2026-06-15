import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_auth_service.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_guard.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:http/http.dart' as http;

class FourReadSearchService {
  static const _baseUrl = 'https://4read.org';
  final FourReadAuthService _authService = FourReadAuthService();

  Future<List<Audiobook>> search(
    String query, {
    int page = 1,
    int pageSize = 15,
  }) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final url =
          '$_baseUrl/?do=search&mode=advanced&subaction=search&story=$encoded&search_start=$page';
      
      // Use authenticated headers if logged in
      final headers = await _authService.getAuthHeaders();
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('4Read search failed with ${response.statusCode}');
      }

      return _parseSearchResults(response.body, limit: pageSize);
    } catch (e) {
      throw Exception('4Read search failed: $e');
    }
  }

  List<Audiobook> _parseSearchResults(
    String html, {
    required int limit,
  }) {
    final cards = html
        .split('<div class="poster has-overlay grid-item d-flex fd-column">');
    if (cards.length <= 1) return [];

    final results = <Audiobook>[];
    for (final rawCard in cards.skip(1)) {
      if (results.length >= limit) break;
      final card = rawCard;
      final href = _match(
        card,
        RegExp(r'<a href="([^"]+)" class="poster__link">', dotAll: true),
      );
      final title = _cleanText(
        _match(
          card,
          RegExp(r'poster__title[^>]*>(.*?)</div>', dotAll: true),
        ),
      );
      final author = _cleanText(
        _match(
          card,
          RegExp(r'poster__subtitle ws-nowrap">\s*(.*?)\s*</div>',
              dotAll: true),
        ),
      );
      final imagePath = _match(
        card,
        RegExp(r'<img src="([^"]+)"', dotAll: true),
      );
      final duration = _match(
        card,
        RegExp(r'data-time="([^"]+)"'),
      );
      final ratingText = _match(
        card,
        RegExp(r'poster__ratings">Рейтинг<br>\s*([0-9.]+)', dotAll: true),
      );
      final votesText = _match(
        card,
        RegExp(r'data-vote-num-id="\d+">(\d+)<', dotAll: true),
      );

      if (href.isEmpty || title.isEmpty) continue;

      final rawBook = Audiobook.fromMap({
        'id': href.startsWith('http') ? href : '$_baseUrl$href',
        'title': title,
        'author': author.isNotEmpty ? author : 'Unknown',
        'description': '',
        'lowQCoverImage':
            imagePath.startsWith('http') ? imagePath : '$_baseUrl$imagePath',
        'totalTime': duration,
        'downloads': int.tryParse(votesText) ?? 0,
        'rating': double.tryParse(ratingText),
        'reviews': int.tryParse(votesText) ?? 0,
        'subject': [],
        'size': 0,
        'language': 'uk',
        'origin': AppConstants.fourReadDirName,
      });
      final guarded = FourReadOpenGuard.validateAndNormalizeAudiobook(
        rawBook,
        stage: 'search_parse',
      );
      if (!guarded.isValid) {
        AppLogger.warning(
          'Skipping invalid 4Read search card with id=${rawBook.id}: ${guarded.failure?.code}',
          'FourReadSearch',
        );
        continue;
      }
      results.add(guarded.audiobook!);
    }

    return results;
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
