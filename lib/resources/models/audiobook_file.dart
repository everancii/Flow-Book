import 'dart:convert';
import 'dart:io';

import 'package:audiobookflow/utils/app_logger.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_storage.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_page_service.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_auth_service.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const String _base = "https://archive.org/download";

class AudiobookFile {
  final String? identifier;
  final String? title;
  final String? name;
  final String? url;
  final double? length; // seconds
  final int? track;
  final int? size;
  final String? highQCoverImage;

  final int? startMs; // chapter start (ms from file start)
  final int? durationMs; // chapter duration (ms); null => to EOF

  AudiobookFile.fromJson(Map json)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url = "$_base/${json['identifier']}/${json['name']}",
        highQCoverImage =
            "$_base/${json['identifier']}/${json["highQCoverImage"]}",
        startMs = null,
        durationMs = null;

  AudiobookFile.fromYoutubeJson(Map json)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url = json["url"]?.toString(),
        highQCoverImage = json["highQCoverImage"]?.toString(),
        startMs = null,
        durationMs = null;

  AudiobookFile.fromLocalJson(Map json, String location)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url = "$location/${json["url"]!}",
        highQCoverImage = "$location/cover.jpg",
        startMs = null,
        durationMs = null;

  AudiobookFile copyWithLength(double length) => AudiobookFile.fromMap({
        'identifier': identifier,
        'title': title,
        'name': name,
        'track': track,
        'size': size,
        'length': length,
        'url': url,
        'highQCoverImage': highQCoverImage,
        'startMs': startMs,
        'durationMs': durationMs,
      });

  static AudiobookFile chapterSlice({
    required String identifier,
    required String url,
    required String parentTitle,
    required int track,
    required String chapterTitle,
    required int startMs,
    int? durationMs,
    String? highQCoverImage,
  }) {
    return AudiobookFile.fromMap({
      "identifier": identifier,
      "title": chapterTitle.isNotEmpty
          ? chapterTitle
          : "$parentTitle — Chapter $track",
      "name": parentTitle,
      "track": track,
      "size": 0,
      "length": null, // player derives effective length via ClippingAudioSource
      "url": url,
      "highQCoverImage": highQCoverImage,
      "startMs": startMs,
      "durationMs": durationMs,
    });
  }

  static int _parseTrack(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;

    try {
      final trackStr = value.toString();
      return int.parse(trackStr.split("/")[0]);
    } catch (e) {
      AppLogger.debug('Error parsing track value: $value, error: $e');
      return 0;
    }
  }

  static int? _parseIntSafely(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;

    try {
      return int.parse(value.toString());
    } catch (e) {
      AppLogger.debug('Error parsing int value: $value, error: $e');
      return null;
    }
  }

  static double? _parseDoubleSafely(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();

    try {
      return double.parse(value.toString());
    } catch (e) {
      AppLogger.debug('Error parsing double value: $value, error: $e');
      return null;
    }
  }

  static List<AudiobookFile> fromJsonArray(List jsonFiles) {
    List<AudiobookFile> audiobookFiles = <AudiobookFile>[];
    for (var i = 0; i < jsonFiles.length; i++) {
      try {
        var jsonFile = jsonFiles[i];
        audiobookFiles.add(AudiobookFile.fromJson(jsonFile));
      } catch (e) {
        AppLogger.debug('Error parsing file at index $i: $e');
        AppLogger.debug('Data: ${jsonFiles[i]}');
      }
    }
    return audiobookFiles;
  }

  static List<AudiobookFile> fromLocalJsonArray(
      List jsonFiles, String location) {
    List<AudiobookFile> audiobookFiles = <AudiobookFile>[];
    for (var i = 0; i < jsonFiles.length; i++) {
      audiobookFiles.add(AudiobookFile.fromLocalJson(jsonFiles[i], location));
    }
    return audiobookFiles;
  }

  static List<AudiobookFile> fromYoutubeJsonArray(List jsonFiles) {
    List<AudiobookFile> audiobookFiles = <AudiobookFile>[];
    for (var i = 0; i < jsonFiles.length; i++) {
      audiobookFiles.add(AudiobookFile.fromYoutubeJson(jsonFiles[i]));
    }
    return audiobookFiles;
  }

  static Future<Either<String, List<AudiobookFile>>> fromDownloadedFiles(
      String audiobookId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/downloads/$audiobookId');
      if (!await downloadDir.exists()) {
        return const Right([]);
      }
      List<FileSystemEntity> files = downloadDir
          .listSync()
          .where((file) => file.path.endsWith('.mp3'))
          .toList();
      files.sort(
        (a, b) => a.statSync().changed.compareTo(b.statSync().changed),
      );

      AppLogger.debug(
          'Now the files are going to be parsed from the downloaded files');

      List<AudiobookFile> audiobookFiles = <AudiobookFile>[];

      for (var i = 0; i < files.length; i++) {
        try {
          final metadata =
              await MetadataRetriever.fromFile(File(files[i].path));
          final duration = metadata.trackDuration?.toDouble() ?? 0.0;

          audiobookFiles.add(AudiobookFile.fromMap({
            "identifier": audiobookId,
            "title": files[i].path.split('/').last.split('.').first,
            "name": files[i].path.split('/').last,
            "track": i + 1,
            "size": files[i].statSync().size,
            "length": duration / 1000, // Convert milliseconds to seconds
            "url": files[i].path,
            "highQCoverImage":
                'https://archive.org/services/get-item-image.php?identifier=$audiobookId',
          }));
        } catch (e) {
          AppLogger.debug('Error getting metadata for ${files[i].path}: $e');
          audiobookFiles.add(AudiobookFile.fromMap({
            "identifier": audiobookId,
            "title": files[i].path.split('/').last.split('.').first,
            "name": files[i].path.split('/').last,
            "track": i + 1,
            "size": files[i].statSync().size,
            "length": 0.0,
            "url": files[i].path,
            "highQCoverImage":
                'https://archive.org/services/get-item-image.php?identifier=$audiobookId',
          }));
        }
      }

      return Right(audiobookFiles);
    } catch (e) {
      AppLogger.debug('Unexpected error: $e');
      return Left('Unexpected error: $e');
    }
  }

  static Future<Either<String, List<AudiobookFile>>> fromLocalFiles(
      String audiobookId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/local/$audiobookId');

      final stringContent =
          await File('${downloadDir.path}/files.txt').readAsString();
      final jsonContent = jsonDecode(stringContent);
      if (jsonContent is List) {
        AppLogger.debug('JSON list length: ${jsonContent.length}');
        if (jsonContent.isNotEmpty) {
          AppLogger.debug('First item sample fields:');
          final item = jsonContent[0];
          if (item is Map) {
            item.forEach((key, value) {
              AppLogger.debug('  $key: $value (${value.runtimeType})');
            });
          }
        }
      }

      final List<AudiobookFile> audiobookFiles =
          AudiobookFile.fromLocalJsonArray(jsonContent, downloadDir.path);
      return Right(audiobookFiles);
    } catch (e) {
      AppLogger.debug('Unexpected error: $e');
      return Left('Unexpected error: $e');
    }
  }

  /// Builds a single [AudiobookFile] from a live YouTube video ID.
  /// Used when showing details for a search result (no saved files.txt).
  /// Loads chapters for a YouTube search result.
  ///
  /// [id] may be a video ID (11 chars) or a playlist ID (e.g. `PL…`).
  /// When it is a playlist ID all videos in the playlist (up to 100) are
  /// returned as ordered chapters.  Falls back to single-video behaviour on
  /// any error.
  static Future<Either<String, List<AudiobookFile>>> fromYoutubeVideoId(
      String id) async {
    final yt = YoutubeExplode();
    try {
      // YouTube video IDs are exactly 11 characters.  Anything longer is
      // treated as a playlist ID so all chapters are loaded automatically.
      if (id.length != 11) {
        return await _fromYoutubePlaylistId(yt, id);
      }
      final video = await yt.videos.get(id);
      final file = AudiobookFile.fromMap({
        'identifier': id,
        'title': video.title,
        'name': '${video.id.value}.mp3',
        'track': 1,
        'size': 0,
        'length': video.duration?.inSeconds.toDouble() ?? 0.0,
        'url': video.url,
        'highQCoverImage': video.thumbnails.highResUrl,
      });
      return Right([file]);
    } catch (e) {
      AppLogger.debug('fromYoutubeVideoId error: $e');

      // If YouTube rate-limits watch-page metadata, keep the flow usable by
      // returning a minimal playable track built from the video ID.
      if (id.length == 11 && _isYoutubeRateLimitError(e)) {
        final fallback = _buildRateLimitedVideoFallback(id);
        AppLogger.debug(
            'fromYoutubeVideoId: using rate-limit fallback for $id');
        return Right([fallback]);
      }

      return Left('Failed to load YouTube video: $e');
    } finally {
      yt.close();
    }
  }

  static bool _isYoutubeRateLimitError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('requestlimitexceededexception') ||
        text.contains('rate limiting') ||
        text.contains('too many requests') ||
        text.contains('status code 429');
  }

  static AudiobookFile _buildRateLimitedVideoFallback(String id) {
    return AudiobookFile.fromMap({
      'identifier': id,
      'title': 'YouTube video',
      'name': '$id.mp3',
      'track': 1,
      'size': 0,
      'length': 0.0,
      'url': 'https://www.youtube.com/watch?v=$id',
      'highQCoverImage': 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
    });
  }

  /// Fetches all videos in a YouTube playlist (capped at 100) and returns
  /// them as ordered [AudiobookFile] chapters.  Falls back to [Left] on error.
  static Future<Either<String, List<AudiobookFile>>> _fromYoutubePlaylistId(
      YoutubeExplode yt, String playlistId) async {
    try {
      AppLogger.debug('_fromYoutubePlaylistId: fetching playlist $playlistId');

      // Fetch playlist metadata
      String playlistTitle = '';
      String playlistAuthor = '';
      try {
        final playlist = await yt.playlists.get(playlistId).timeout(
              const Duration(seconds: 15),
            );
        playlistTitle = playlist.title;
        playlistAuthor = playlist.author;
        AppLogger.debug(
            '_fromYoutubePlaylistId: playlist title="$playlistTitle", author="$playlistAuthor"');
      } catch (e) {
        AppLogger.debug(
            '_fromYoutubePlaylistId: failed to get playlist metadata: $e');
      }

      // Fetch playlist videos via HTTP API (yt.playlists.getVideos is broken in this fork)
      final videos = await fetchPlaylistVideosViaHttp(playlistId);

      if (videos.isEmpty) {
        return Left('Playlist is empty or could not be loaded');
      }

      final files = videos.asMap().entries.map((entry) {
        final index = entry.key;
        final video = entry.value;
        return AudiobookFile.fromMap({
          'identifier': playlistId,
          'title': video['title'] ?? 'Video ${index + 1}',
          'name': '${video['id']}.mp3',
          'track': index + 1,
          'size': 0,
          'length': 0.0,
          'url': 'https://www.youtube.com/watch?v=${video['id']}',
          'highQCoverImage': video['thumbnail'] ??
              'https://i.ytimg.com/vi/${video['id']}/hqdefault.jpg',
        });
      }).toList();

      AppLogger.debug(
          '_fromYoutubePlaylistId: loaded ${files.length} chapters from playlist');
      return Right(files);
    } catch (e) {
      AppLogger.debug('_fromYoutubePlaylistId error: $e');
      return Left('Failed to load YouTube playlist: $e');
    }
  }

  /// Fetches playlist video IDs via YouTube's internal API.
  ///
  /// [onProgress] is invoked as pages are fetched with the 1-based page number
  /// being loaded and the total number of videos collected so far, so callers
  /// can report "Loading videos (page N) • M loaded" to the user.
  static Future<List<Map<String, String>>> fetchPlaylistVideosViaHttp(
      String playlistId,
      {void Function(int page, int loaded)? onProgress}) async {
    final videos = <Map<String, String>>[];

    try {
      // Use YouTube's InnerTube API to get playlist content
      // ANDROID_VR is more resilient and still returns the old Renderer structure
      final apiUrl = Uri.parse(
          'https://www.youtube.com/youtubei/v1/browse?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8');
      final apiResponse = await http
          .post(
            apiUrl,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 10; Quest 2) AppleWebKit/537.36 (KHTML, like Gecko) OculusBrowser/15.0.0.0.22 SamsungBrowser/4.0 Chrome/89.0.4389.90 Mobile Safari/537.36',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'ANDROID_VR',
                  'clientVersion': '1.50.41',
                  'hl': 'en',
                  'gl': 'US',
                },
              },
              'browseId': 'VL$playlistId',
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (apiResponse.statusCode != 200) {
        AppLogger.debug(
            'fetchPlaylistVideosViaHttp: API request failed with status ${apiResponse.statusCode}');
        return videos;
      }

      final apiData = jsonDecode(apiResponse.body);

      // Navigate the response structure to find videos
      // Supports both twoColumn and singleColumn (VR) structures
      var contents = apiData['contents']?['twoColumnBrowseResultsRenderer']
                  ?['tabs']?[0]?['tabRenderer']?['content']
              ?['sectionListRenderer']?['contents']?[0]?['itemSectionRenderer']
          ?['contents']?[0]?['playlistVideoListRenderer']?['contents'];

      // Alternative path for ANDROID_VR/mobile clients
      contents ??= apiData['contents']?['singleColumnBrowseResultsRenderer']
              ?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']
          ?['contents']?[0]?['playlistVideoListRenderer']?['contents'];

      // Yet another alternative path seen in some ANDROID_VR responses
      contents ??= apiData['contents']?['singleColumnBrowseResultsRenderer']
                  ?['tabs']?[0]?['tabRenderer']?['content']
              ?['sectionListRenderer']?['contents']?[0]?['itemSectionRenderer']
          ?['contents']?[0]?['playlistVideoListRenderer']?['contents'];

      if (contents == null || contents is! List) {
        AppLogger.debug(
            'fetchPlaylistVideosViaHttp: no playlist contents found');
        return videos;
      }

      String? continuationToken;

      for (final item in contents) {
        if (item.containsKey('playlistVideoRenderer')) {
          final renderer = item['playlistVideoRenderer'];
          final videoId = renderer['videoId'] as String?;
          final titleRuns = renderer['title']?['runs'] as List?;
          final title = titleRuns?.isNotEmpty == true
              ? titleRuns![0]['text'] as String?
              : null;

          if (videoId != null && title != null) {
            videos.add({
              'id': videoId,
              'title': title,
              'thumbnail': 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
            });
          }
        } else if (item.containsKey('continuationItemRenderer')) {
          continuationToken = item['continuationItemRenderer']
                  ?['continuationEndpoint']?['continuationCommand']?['token']
              as String?;
        }
      }

      AppLogger.debug(
          'fetchPlaylistVideosViaHttp: found ${videos.length} videos from API');

      // Report the initial page (page 1) result.
      onProgress?.call(1, videos.length);

      // Fetch additional pages via continuation tokens
      int maxPages = 10;
      int page = 0;
      while (
          continuationToken != null && page < maxPages && videos.length < 100) {
        // Report "loading page N" (continuation pages are page 2, 3, …).
        onProgress?.call(page + 2, videos.length);
        try {
          final contResponse = await http
              .post(
                apiUrl,
                headers: {
                  'Content-Type': 'application/json',
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 10; Quest 2) AppleWebKit/537.36 (KHTML, like Gecko) OculusBrowser/15.0.0.0.22 SamsungBrowser/4.0 Chrome/89.0.4389.90 Mobile Safari/537.36',
                },
                body: jsonEncode({
                  'context': {
                    'client': {
                      'clientName': 'ANDROID_VR',
                      'clientVersion': '1.50.41',
                      'hl': 'en',
                      'gl': 'US',
                    },
                  },
                  'continuation': continuationToken,
                }),
              )
              .timeout(const Duration(seconds: 15));

          if (contResponse.statusCode == 200) {
            final contData = jsonDecode(contResponse.body);
            final continuationItems = contData['onResponseReceivedActions']?[0]
                ?['appendContinuationItemsAction']?['continuationItems'];

            if (continuationItems == null || continuationItems is! List) {
              break;
            }

            continuationToken = null; // Reset for next iteration

            for (final item in continuationItems) {
              if (item.containsKey('playlistVideoRenderer')) {
                final renderer = item['playlistVideoRenderer'];
                final videoId = renderer['videoId'] as String?;
                final titleRuns = renderer['title']?['runs'] as List?;
                final title = titleRuns?.isNotEmpty == true
                    ? titleRuns![0]['text'] as String?
                    : null;

                if (videoId != null && title != null) {
                  videos.add({
                    'id': videoId,
                    'title': title,
                    'thumbnail':
                        'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                  });
                }
              } else if (item.containsKey('continuationItemRenderer')) {
                continuationToken = item['continuationItemRenderer']
                        ?['continuationEndpoint']?['continuationCommand']
                    ?['token'] as String?;
              }
            }
          } else {
            break;
          }
        } catch (e) {
          AppLogger.debug('fetchPlaylistVideosViaHttp: continuation error: $e');
          break;
        }
        page++;
      }
    } catch (e) {
      AppLogger.debug('fetchPlaylistVideosViaHttp: error: $e');
    }

    return videos;
  }

  static Future<Either<String, List<AudiobookFile>>> fromYoutubeFiles(
      String audiobookId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/youtube/$audiobookId');

      final stringContent =
          await File('${downloadDir.path}/files.txt').readAsString();
      final jsonContent = jsonDecode(stringContent);
      if (jsonContent is List) {
        AppLogger.debug('JSON list length: ${jsonContent.length}');
        if (jsonContent.isNotEmpty) {
          AppLogger.debug('First item sample fields:');
          final item = jsonContent[0];
          if (item is Map) {
            item.forEach((key, value) {
              AppLogger.debug('  $key: $value (${value.runtimeType})');
            });
          }
        }
      }

      final List<AudiobookFile> audiobookFiles =
          AudiobookFile.fromYoutubeJsonArray(jsonContent);
      return Right(audiobookFiles);
    } catch (e) {
      AppLogger.debug('Unexpected error: $e');
      return Left('Unexpected error: $e');
    }
  }

  static Future<Either<String, List<AudiobookFile>>> fromFourReadFiles(
      String audiobookId) async {
    try {
      final downloadDir = await fourReadAudiobookDirectory(audiobookId);
      final stringContent =
          await File('${downloadDir.path}/files.txt').readAsString();
      final jsonContent = jsonDecode(stringContent);
      if (jsonContent is List) {
        AppLogger.debug('JSON list length: ${jsonContent.length}');
      }

      final List<AudiobookFile> audiobookFiles = <AudiobookFile>[];
      if (jsonContent is List) {
        for (var i = 0; i < jsonContent.length; i++) {
          try {
            final item = Map<String, dynamic>.from(jsonContent[i] as Map);
            audiobookFiles.add(AudiobookFile.fromMap(item));
          } catch (e) {
            AppLogger.debug('Error parsing 4Read file at index $i: $e');
            AppLogger.debug('Data: ${jsonContent[i]}');
          }
        }
      }

      return Right(audiobookFiles);
    } catch (e) {
      AppLogger.debug('Unexpected error: $e');
      return Left('Unexpected error: $e');
    }
  }

  static Future<Either<String, List<AudiobookFile>>> fromFourReadPageUrl(
    String articleUrl,
  ) async {
    try {
      AppLogger.debug('[4read] fromFourReadPageUrl: articleUrl=$articleUrl');
      final pageService = FourReadPageService();
      AppLogger.debug('[4read] step1: fetchPageData');
      final pageData = await pageService.fetchPageData(articleUrl);
      AppLogger.debug('[4read] step2: fetchFourReadVars');
      final vars = await _fetchFourReadVars(articleUrl);
      AppLogger.debug('[4read] step3: resolvePlaylistExpression');
      final playlistUrl = pageService.resolvePlaylistExpression(
        pageData.playlistExpression,
        vars: vars,
      );
      AppLogger.debug('[4read] playlistUrl=$playlistUrl');
      final fallbackPlaylistUrl = _deriveFourReadPlaylistUrl(articleUrl);
      AppLogger.debug('[4read] fallbackPlaylistUrl=$fallbackPlaylistUrl');
      String playlistText;
      try {
        playlistText = await _fetchFourReadPlaylist(playlistUrl);
      } catch (_) {
        if (playlistUrl == fallbackPlaylistUrl) {
          rethrow;
        }
        playlistText = await _fetchFourReadPlaylist(fallbackPlaylistUrl);
      }
      AppLogger.debug('[4read] step5: parsePlaylist');
      final tracks = pageService.parsePlaylist(playlistText);

      if (tracks.isEmpty) {
        return Left('No playable tracks were found in the 4Read playlist.');
      }

      final files = <AudiobookFile>[];
      for (var index = 0; index < tracks.length; index++) {
        final track = tracks[index];
        files.add(
          AudiobookFile.fromMap({
            'identifier': articleUrl,
            'title': track.title.isNotEmpty
                ? track.title
                : '${pageData.title} Chapter ${index + 1}',
            'name': _fileNameFromUrl(track.url, index + 1),
            'track': index + 1,
            'size': 0,
            'length': track.durationSeconds ?? 0.0,
            'url': track.url,
            'highQCoverImage': pageData.coverImage,
          }),
        );
      }

      return Right(files);
    } catch (e, st) {
      AppLogger.debug('fromFourReadPageUrl error: $e\n$st');
      return Left('Failed to load 4Read audiobook: $e');
    }
  }

  static String _deriveFourReadPlaylistUrl(String articleUrl) {
    final uri = Uri.tryParse(articleUrl);
    final slug = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : articleUrl;
    final playlistName = slug.endsWith('.html')
        ? '${slug.substring(0, slug.length - 5)}.m3u'
        : '$slug.m3u';
    return 'https://4read.org/m3u/$playlistName';
  }

  static Future<Map<String, dynamic>> _fetchFourReadVars(
    String articleUrl,
  ) async {
    final authService = FourReadAuthService();
    final authHeaders = await authService.getAuthHeaders();
    final html = await FourReadPageService.safeHttpGetBody(
      articleUrl,
      authHeaders,
    );
    final vars = <String, dynamic>{};
    final match = RegExp(
      r'window\.([A-Za-z][A-Za-z0-9_]*)\s*=\s*"([^"]+)"',
      dotAll: true,
    ).allMatches(html);
    for (final m in match) {
      vars[m.group(1)!] = m.group(2)!;
    }
    return vars;
  }

  static Future<String> _fetchFourReadPlaylist(String playlistUrl) async {
    final authService = FourReadAuthService();
    final authHeaders = await authService.getAuthHeaders();
    authHeaders['Accept'] = '*/*';
    return FourReadPageService.safeHttpGetBody(
      playlistUrl,
      authHeaders,
    );
  }

  static String _fileNameFromUrl(String url, int index) {
    final uri = _safeUri(url);
    final segment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (segment.isEmpty) {
      return 'chapter_$index.mp3';
    }

    final decoded = (() {
      try {
        return Uri.decodeComponent(segment);
      } catch (_) {
        return segment; // malformed percent-encoding — use raw segment
      }
    })();
    final clean = decoded.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
    if (clean.toLowerCase().endsWith('.mp3')) {
      return clean;
    }
    return '$clean.mp3';
  }

  /// Parses [url] tolerantly:
  /// 1. Fixes bare `%` signs not followed by two hex digits → `%25`.
  /// 2. Encodes raw non-ASCII characters (e.g. Cyrillic) via Uri.encodeFull.
  ///    Uri.encodeFull preserves already-valid %XX sequences.
  static Uri _safeUri(String url) {
    final fixedPercent = url.replaceAllMapped(
      RegExp(r'%(?![0-9A-Fa-f]{2})'),
      (_) => '%25',
    );
    final encoded = Uri.encodeFull(fixedPercent);
    try {
      return Uri.parse(encoded);
    } catch (_) {
      return Uri.parse('https://4read.org/');
    }
  }

  AudiobookFile.fromMap(Map<dynamic, dynamic> map)
      : identifier = map["identifier"],
        title = map["title"],
        name = map["name"],
        track = _parseTrack(map["track"]),
        size = _parseIntSafely(map["size"]),
        length = _parseDoubleSafely(map["length"]),
        url = map["url"],
        highQCoverImage = map["highQCoverImage"],
        startMs = _parseIntSafely(map["startMs"]),
        durationMs = _parseIntSafely(map["durationMs"]) {
    if (title != null && length != null && length! > 0) {
      AppLogger.debug(
          'AudiobookFile: title="$title", lengthSeconds=${length!.toStringAsFixed(0)}');
    }
  }

  Map<dynamic, dynamic> toMap() {
    return {
      "identifier": identifier,
      "title": title,
      "name": name,
      "track": track,
      "size": size,
      "length": length,
      "url": url,
      "highQCoverImage": highQCoverImage,
      "startMs": startMs,
      "durationMs": durationMs,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      "identifier": identifier,
      "title": title,
      "name": name,
      "track": track,
      "size": size,
      "length": length,
      "url": url,
      "highQCoverImage": highQCoverImage,
      "startMs": startMs,
      "durationMs": durationMs,
    };
  }
}
