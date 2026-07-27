import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Searches YouTube for audiobooks using [youtube_explode_dart] — no API key required.
///
/// Runs parallel searches (videos + playlists) and merges results so that:
/// - Single-file audiobooks (e.g. a 7-hour Carrie video) are found via video search.
/// - Multi-chapter series (e.g. "Воно # 01…67") appear as one playlist card.
class YoutubeSearchService {
  final YoutubeExplode _yt = YoutubeExplode();

  Future<List<Audiobook>> search(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      // Default search term — used for all queries.
      const term = 'audiobook';

      AppLogger.debug('YouTube Search: query="$query"');

      // Parallel: search for videos + playlists.
      final futures = <Future<List<SearchResult>>>[];
      final q = '$query $term';
      AppLogger.debug('YouTube Search: performing search for q="$q"');
      futures.add(_yt.search
          .searchContent(q)
          .then((l) => l.toList())
          .catchError((_) => <SearchResult>[]));
      futures.add(_yt.search
          .searchContent(q, filter: TypeFilters.playlist)
          .then((l) => l.toList())
          .catchError((_) => <SearchResult>[]));

      final allResults = await Future.wait(futures);
      final combined = <SearchResult>[];

      // Interleave results from different terms to ensure variety in top results
      int maxLen = 0;
      for (var list in allResults) {
        if (list.length > maxLen) maxLen = list.length;
      }

      for (int i = 0; i < maxLen; i++) {
        for (var list in allResults) {
          if (i < list.length) {
            combined.add(list[i]);
          }
        }
      }

      // Deduplicate results by ID
      final seenIds = <String>{};
      final uniqueResults = combined.where((res) {
        String id;
        if (res is SearchVideo) {
          id = res.id.value;
        } else if (res is SearchPlaylist) {
          id = res.id.value;
        } else if (res is SearchChannel) {
          id = res.id.value;
        } else {
          return false; // Skip unknown types
        }

        if (seenIds.contains(id)) return false;
        seenIds.add(id);
        return true;
      }).toList();

      final skip = (page - 1) * pageSize;
      final pageItems = uniqueResults.skip(skip).take(pageSize).toList();

      return pageItems
          .map((result) {
            if (result is SearchPlaylist) {
              final thumb = result.thumbnails.isNotEmpty
                  ? result.thumbnails.first.url.toString()
                  : '';
              return Audiobook.fromMap({
                'id': result.id.value,
                'title': result.title,
                'author': '',
                'description': '',
                'lowQCoverImage': thumb,
                'totalTime': null,
                'downloads': result.videoCount,
                'rating': null,
                'reviews': 0,
                'subject': [],
                'size': 0,
                'language': '',
                'origin': AppConstants.youtubeDirName,
                'date': null,
              });
            } else if (result is SearchVideo) {
              final thumb = result.thumbnails.isNotEmpty
                  ? result.thumbnails.first.url.toString()
                  : '';
              return Audiobook.fromMap({
                'id': result.id.value,
                'title': result.title,
                'author': result.author,
                'description': result.description,
                'lowQCoverImage': thumb,
                'totalTime': result.duration,
                'downloads': result.viewCount,
                'rating': null,
                'reviews': 0,
                'subject': [],
                'size': 0,
                'language': '',
                'origin': AppConstants.youtubeDirName,
                'date': null,
              });
            }
            return null;
          })
          .whereType<Audiobook>()
          .toList();
    } catch (e) {
      throw Exception('YouTube search failed: $e');
    }
  }

  void dispose() => _yt.close();
}
