import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:http/http.dart' as http;
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/utils/app_logger.dart';

// ─── Simple HTTP cache with ETag/Last-Modified ────────────────────────────────
class _CacheEntry {
  final String body;
  final String? etag;
  final String? lastModified;
  final DateTime storedAt;
  _CacheEntry({
    required this.body,
    this.etag,
    this.lastModified,
    required this.storedAt,
  });
}

/// Fields we want back from Archive.org
const _fields =
    "runtime,avg_rating,num_reviews,title,description,identifier,creator,date,downloads,subject,item_size,language";

/// Build a full advancedsearch URL with a base collection, optional extra query,
/// sorting, and paging.
String _buildAdvancedSearchUrl({
  required String collection,
  String extraQuery = '',
  String sortBy = '',
  required int page,
  required int rows,
}) {
  final sort = sortBy.isNotEmpty ? '&sort[]=$sortBy+desc' : '';

  // q=collection:(librivoxaudio)+AND+(<extraQuery>)
  final qParts = <String>[
    'collection:($collection)',
  ];
  if (extraQuery.isNotEmpty) {
    // Encode the extra query component to be safe with spaces/ORs, then wrap.
    final enc = Uri.encodeComponent(extraQuery);
    qParts.add('($enc)');
  }
  final q = 'q=${qParts.join('+AND+')}';

  return 'https://archive.org/advancedsearch.php?$q&fl=$_fields$sort&output=json&page=$page&rows=$rows';
}


class ArchiveApi {
  // Reuse one client to keep TCP alive & reduce handshake cost.
  static final http.Client _client = http.Client();

  // Very small in-memory cache (URL -> response + validators).
  static final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};
  static const Duration _maxStale = Duration(minutes: 15); // tune as you like
  static const int _maxEntries = 100; // tiny LRU-ish trim

  // Centralized GET with conditional requests.
  static Future<String> _getJson(String url) async {
    final headers = <String, String>{};
    final cached = _cache[url];

    if (cached != null &&
        DateTime.now().difference(cached.storedAt) < _maxStale) {
      if (cached.etag != null) headers['If-None-Match'] = cached.etag!;
      if (cached.lastModified != null) {
        headers['If-Modified-Since'] = cached.lastModified!;
      }
    }

    final resp = await _client.get(Uri.parse(url), headers: headers);

    if (resp.statusCode == 304 && cached != null) {
      // Not modified — serve cached body
      return cached.body;
    }
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode} for $url');
    }

    final etag = resp.headers['etag'];
    final lastMod = resp.headers['last-modified'];

    // Store/refresh cache (simple trim to avoid unbounded growth)
    _cache[url] = _CacheEntry(
      body: resp.body,
      etag: etag,
      lastModified: lastMod,
      storedAt: DateTime.now(),
    );
    if (_cache.length > _maxEntries) {
      // Drop the stalest ~10% (super simple)
      final entries = _cache.entries.toList()
        ..sort((a, b) => a.value.storedAt.compareTo(b.value.storedAt));
      for (var i = 0; i < (_maxEntries / 10).ceil(); i++) {
        _cache.remove(entries[i].key);
      }
    }

    return resp.body;
  }

  // Optional: call this from app shutdown if you want.
  static void dispose() => _client.close();

  Future<Either<String, List<Audiobook>>> getLatestAudiobook(
    int page,
    int rows,
  ) async {
    final url = _buildAdvancedSearchUrl(
      collection: 'librivoxaudio',
      sortBy: 'addeddate',
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> getMostViewedWeeklyAudiobook(
    int page,
    int rows,
  ) async {
    final url = _buildAdvancedSearchUrl(
      collection: 'librivoxaudio',
      sortBy: 'week',
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> getMostDownloadedEverAudiobook(
    int page,
    int rows,
  ) async {
    final url = _buildAdvancedSearchUrl(
      collection: 'librivoxaudio',
      sortBy: 'downloads',
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> getAudiobooksByGenre(
    String genre,
    int page,
    int rows,
    String sortBy,
  ) async {
    final genreQuery = genre
        .split(RegExp(r'\s+OR\s+',
            caseSensitive: false)) // split by any 'OR' variant
        .map((s) => s.trim().toLowerCase())
        .join(' OR '); // join back with uppercase OR

    final url = _buildAdvancedSearchUrl(
      collection: 'librivoxaudio',
      extraQuery: 'subject:($genreQuery)',
      sortBy: sortBy,
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<AudiobookFile>>> getAudiobookFiles(
    String identifier,
  ) async {
    final safeIdentifier = identifier.trim();
    final url = Uri.https(
      'archive.org',
      '/metadata/$safeIdentifier/files',
      const {'output': 'json'},
    ).toString();
    try {
      final body = await _getJson(url);
      final resJson = json.decode(body);

      final List result = (resJson["result"] as List?) ??
          (resJson["files"] as List?) ??
          const [];
      String? highQCoverImage = result.firstWhere(
        (item) =>
            item is Map &&
            item["source"] == "original" &&
            item["format"] == "JPEG",
        orElse: () => null,
      )?["name"];

      final files = <AudiobookFile>[];
      for (final item in result) {
        if (item is Map &&
            item["source"] == "original" &&
            item["track"] != null) {
          item["identifier"] = identifier;
          item["highQCoverImage"] = highQCoverImage;
          files.add(AudiobookFile.fromJson(item));
        }
      }
      return Right(files);
    } catch (e) {
      return Left(e.toString());
    }
  }

  Future<Either<String, List<Audiobook>>> searchAudiobook(
    String searchQuery,
    int page,
    int rows,
  ) async {
    // Encode the free-form query to avoid breaking the `q` param.
    final encoded = Uri.encodeComponent(searchQuery);

    final q = '$encoded+AND+collection:(librivoxaudio)';

    final url =
        "https://archive.org/advancedsearch.php?q=$q&fl=$_fields&sort[]=downloads+desc&output=json&page=$page&rows=$rows";
    AppLogger.debug('Search URL: $url', 'ArchiveApi');
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> searchArchiveOrg(
    String searchQuery,
    int page,
    int rows,
  ) async {
    // Use text search and filter by title match in results
    final q = '$searchQuery+AND+(mediatype:audio)';

    final url =
        "https://archive.org/advancedsearch.php?q=$q&fl=$_fields&sort[]=downloads+desc&output=json&page=$page&rows=50";
    AppLogger.debug('Archive.org Search URL: $url', 'ArchiveApi');
    return _fetchAudiobooksWithOriginFiltered(url, 'archive', searchQuery);
  }

  Future<Either<String, List<Audiobook>>> _fetchAudiobooksWithOriginFiltered(
      String url, String origin, String searchQuery) async {
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final docs =
            (decoded['response']['docs'] as List).cast<Map<String, dynamic>>();

        final byId = <String, Map<String, dynamic>>{};
        for (final d in docs) {
          final id = (d['identifier'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          byId.putIfAbsent(id, () => d);
        }

        // Filter results where title contains the search query
        final queryLower = searchQuery.toLowerCase();
        final audiobooks = byId.values
            .where((book) => book["title"] != null)
            .where((book) {
              final title = book["title"].toString().toLowerCase();
              return title.contains(queryLower);
            })
            .map((book) => Audiobook.fromJson(book).copyWith(origin: origin))
            .toList();

        return Right(audiobooks);
      } else {
        throw Exception('Failed to load audiobooks');
      }
    } catch (e) {
      return Left(e.toString());
    }
  }

  Future<Either<String, List<Audiobook>>> _fetchAudiobooks(String url) async {
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final docs =
            (decoded['response']['docs'] as List).cast<Map<String, dynamic>>();

        // De-dupe raw docs by Archive.org identifier before building models
        final byId = <String, Map<String, dynamic>>{};
        for (final d in docs) {
          final id = (d['identifier'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          byId.putIfAbsent(id, () => d); // keep first
        }

        return Right(Audiobook.fromJsonArray(byId.values.toList()));
      } else {
        throw Exception('Failed to load audiobooks');
      }
    } catch (e) {
      return Left(e.toString());
    }
  }
}
