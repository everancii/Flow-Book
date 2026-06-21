// ignore_for_file: experimental_member_use
import 'dart:async';

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:audiobookflow/resources/services/youtube/stream_client.dart';
import 'package:audiobookflow/utils/app_logger.dart';

/*
 * This code is based on the implementation from:
 * https://github.com/jhelumcorp/gyawun/blob/main/lib/services/yt_audio_stream.dart
 * 
 * Original implementation by jhelumcorp
 * Modified and adapted for use in this project
 */

class YouTubeAudioSource extends StreamAudioSource {
  final String videoId;
  final String quality; // 'high' or 'low'
  static final YoutubeExplode _sharedYtExplode = YoutubeExplode();
  final AudioStreamClient _streamClient;

  YouTubeAudioSource({
    required this.videoId,
    required this.quality,
    super.tag,
  })  : _streamClient = AudioStreamClient();

  Future<File?> _getLocalFile() async {
    try {
      final tag = this.tag as MediaItem?;
      if (tag == null) return null;

      final audiobookId = tag.extras?['audiobook_id'] as String?;
      final fileTitle = tag.title;
      if (audiobookId == null) return null;

      Directory? extDir;
      try {
        if (Platform.isAndroid) {
          extDir = await getExternalStorageDirectory();
        }
      } catch (_) {}
      final appDocDir = extDir ?? await getApplicationDocumentsDirectory();
      
      // Matches DownloadManager's path logic
      final safeId = audiobookId.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.]'), '_');
      final localFile = File('${appDocDir.path}/downloads/$safeId/$fileTitle.mp3');
      
      if (await localFile.exists()) {
        return localFile;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final localFile = await _getLocalFile();
    if (localFile != null) {
      final size = await localFile.length();
      final s = start ?? 0;
      final e = end ?? size;
      
      return StreamAudioResponse(
        sourceLength: size,
        contentLength: e - s,
        offset: s,
        stream: localFile.openRead(s, e),
        contentType: 'audio/mpeg',
      );
    }

    // Resolve actual video ID from URL if needed
    String resolvedVideoId = videoId;
    if (videoId.contains('youtube.com') || videoId.contains('youtu.be')) {
      final parsed = VideoId.parseVideoId(videoId);
      if (parsed != null) {
        resolvedVideoId = parsed;
      } else {
        // Extract from URL manually
        final uri = Uri.tryParse(videoId);
        resolvedVideoId = uri?.queryParameters['v'] ?? videoId;
      }
    }

    // Try manifest fetch with timeout and fallback clients
    StreamManifest? manifest;
    final clients = [
      (YoutubeApiClient.androidMusic, true),
      (YoutubeApiClient.android, true),
      (YoutubeApiClient.androidVr, true),
      (YoutubeApiClient.ios, true),
    ];

    for (final (client, requireWatch) in clients) {
      try {
        manifest = await _sharedYtExplode.videos.streams.getManifest(
          resolvedVideoId,
          requireWatchPage: requireWatch,
          ytClients: [client],
        ).timeout(const Duration(seconds: 30));
        AppLogger.debug('YouTubeAudioSource: got manifest with client $client');
        break;
      } catch (e) {
        AppLogger.debug('YouTubeAudioSource: client $client failed: $e');
        continue;
      }
    }

    if (manifest == null) {
      throw Exception('Failed to get YouTube stream manifest after trying all clients');
    }

    final supportedStreams = manifest.audioOnly.sortByBitrate();
    if (supportedStreams.isEmpty) {
      throw Exception('No audio streams available for this video');
    }

    final audioStream = quality == 'high'
        ? supportedStreams.lastOrNull
        : supportedStreams.firstOrNull;

    if (audioStream == null) {
      throw Exception('No audio stream available for this video.');
    }

    // Coerce to non-null ints that respect total size
    int s = start ?? 0;
    int e;
    if (audioStream.isThrottled) {
      // cap chunk size to keep the player happy on throttled streams
      const cap = 10 * 1024 * 1024; // ~10 MB
      e = end ?? (s + cap);
    } else {
      e = end ?? audioStream.size.totalBytes;
    }
    if (e > audioStream.size.totalBytes) e = audioStream.size.totalBytes;

    // Use AudioStreamClient for better headers and retry logic
    final rawStream = _streamClient.getAudioStream(
      audioStream,
      start: s,
      end: e,
      isThrottledOrVeryLarge: audioStream.isThrottled,
    );
    final stream = _limitBytes(rawStream, e - s);

    return StreamAudioResponse(
      sourceLength: audioStream.size.totalBytes,
      contentLength: e - s,
      offset: s,
      stream: stream,
      contentType: audioStream.codec.mimeType,
    );
  }

  /// Caps [source] to emit at most [limit] bytes total.
  Stream<List<int>> _limitBytes(Stream<List<int>> source, int limit) async* {
    var remaining = limit;
    await for (final chunk in source) {
      if (remaining <= 0) break;
      if (chunk.length <= remaining) {
        yield chunk;
        remaining -= chunk.length;
      } else {
        yield chunk.sublist(0, remaining);
        break;
      }
    }
  }
}
