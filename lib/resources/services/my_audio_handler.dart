// lib/resources/services/my_audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/models/history_of_audiobook.dart';
import 'package:audiobookflow/resources/services/soundbooks/soundbooks_detail_service.dart';
import 'package:audiobookflow/resources/services/youtube/youtube_audio_service.dart';
import 'package:audiobookflow/resources/services/local/cover_image_service.dart';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:audiobookflow/utils/optimized_timer.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Turn a local path or remote URL into a proper Uri for MediaItem.artUri.
Uri? _artUriFrom(String? s) {
  if (s == null || s.isEmpty) return null;
  final local = asLocalPath(s);
  return local != null ? Uri.file(local) : Uri.parse(s);
}

/// Sanitizes a playback URL for the audio player.
///
/// Percent-encodes raw non-ASCII bytes and spaces (healing old persisted
/// state) and returns the safe URL string. Already-ASCII URLs pass through
/// unchanged. Local file paths (starting with `/`) are returned as-is
/// without encoding — the caller distinguishes them via the leading `/`.
String sanitizePlayerUrl(String rawUrl) {
  final needsEncoding =
      rawUrl.codeUnits.any((u) => u > 0x7F || u == 0x20);
  return needsEncoding ? encodeTrackUrl(rawUrl) : rawUrl;
}

abstract class PlaybackEngine {
  int? get currentIndex;
  Duration get position;
  Duration get bufferedPosition;
  Duration? get duration;
  double get speed;
  bool get playing;
  ProcessingState get processingState;
  List<IndexedAudioSource> get sequence;
  PlaybackEvent get playbackEvent;

  Stream<PlaybackEvent> get playbackEventStream;
  Stream<PlayerState> get playerStateStream;
  Stream<bool> get playingStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<Duration> get positionStream;
  Stream<int?> get currentIndexStream;
  Stream<ProcessingState> get processingStateStream;

  Future<void> setAndroidAudioAttributes(AndroidAudioAttributes attributes);
  Future<void> stop();
  Future<void> setAudioSources(
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
    required bool preload,
  });
  Future<void> seek(Duration position, {int? index});
  Future<void> play();
  Future<void> pause();
  Future<void> seekToNext();
  Future<void> seekToPrevious();
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);
  Future<void> setSkipSilenceEnabled(bool skipSilence);
  Future<void> setBalance(double balance);
  Future<void> setPitch(double pitch);
}

class JustAudioPlaybackEngine implements PlaybackEngine {
  JustAudioPlaybackEngine(this._player);

  final AudioPlayer _player;

  @override
  int? get currentIndex => _player.currentIndex;

  @override
  Duration get position => _player.position;

  @override
  Duration get bufferedPosition => _player.bufferedPosition;

  @override
  Duration? get duration => _player.duration;

  @override
  double get speed => _player.speed;

  @override
  bool get playing => _player.playing;

  @override
  ProcessingState get processingState => _player.processingState;

  @override
  List<IndexedAudioSource> get sequence => _player.sequence;

  @override
  PlaybackEvent get playbackEvent => _player.playbackEvent;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _player.playbackEventStream;

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  @override
  Future<void> setAndroidAudioAttributes(AndroidAudioAttributes attributes) {
    return _player.setAndroidAudioAttributes(attributes);
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> setAudioSources(
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
    required bool preload,
  }) {
    return _player.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      preload: preload,
    );
  }

  @override
  Future<void> seek(Duration position, {int? index}) {
    return _player.seek(position, index: index);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seekToNext() => _player.seekToNext();

  @override
  Future<void> seekToPrevious() => _player.seekToPrevious();

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSkipSilenceEnabled(bool skipSilence) {
    return _player.setSkipSilenceEnabled(skipSilence);
  }

  @override
  Future<void> setBalance(double balance) => _player.setBalance(balance);

  @override
  Future<void> setPitch(double pitch) => _player.setPitch(pitch);
}

class MyAudioHandler extends BaseAudioHandler {
  // Audio effects (Android-only)
  final AndroidEqualizer? _equalizer =
      Platform.isAndroid ? AndroidEqualizer() : null;
  final AndroidLoudnessEnhancer? _loudnessEnhancer =
      Platform.isAndroid ? AndroidLoudnessEnhancer() : null;

  late final PlaybackEngine _player;
  final bool _configureAudioSession;

  // Global sleep timer
  final OptimizedTimer sleepTimer = OptimizedTimer();

  List<AudioSource>? _audioSources;
  List<AudioSource>? get audioSources => _audioSources;

  Box<dynamic> playingAudiobookDetailsBox =
      Hive.box('playing_audiobook_details_box');

  final HistoryOfAudiobook historyOfAudiobook = HistoryOfAudiobook();
  Timer? _positionUpdateTimer;

  bool _sessionConfigured = false;
  bool _isReinitializing = false;
  int _initGen = 0;

  /// True while [initSongs] is replacing the queue. Callers (e.g.
  /// [MiniAudioPlayer]) SHOULD skip restore-from-Hive reinit while this
  /// is true to avoid racing with an explicit initSongs.
  bool get isReinitializing => _isReinitializing;

  MyAudioHandler({
    PlaybackEngine? player,
    bool configureAudioSession = true,
  }) : _configureAudioSession = configureAudioSession {
    final effects = [
      if (_equalizer != null) _equalizer,
      if (_loudnessEnhancer != null) _loudnessEnhancer,
    ];
    _player = player ??
        JustAudioPlaybackEngine(
          AudioPlayer(
            audioPipeline: AudioPipeline(
              androidAudioEffects: effects,
            ),
          ),
        );
  }

  StreamSubscription<String>? _coverSub;

  // Write barrier + context about the current audiobook
  bool _canPersistProgress = false;
  String? _activeAudiobookId;

  // Debounce MRU/position writes so UIs don’t “flap”
  DateTime _lastPersistAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _persistInterval = Duration(seconds: 12);
  static const _readyTimeout = Duration(seconds: 10);

  // Subscriptions to keep PlaybackState in sync
  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _bufferedSub;

  // Global YouTube buffering indicator
  final ValueNotifier<bool> isBufferingYouTube = ValueNotifier(false);

  /// Buffered-ahead fraction (0.0–1.0) of the current track while it loads,
  /// computed from `bufferedPosition / duration`. Lets the UI show a real
  /// percentage instead of a bare spinner while buffering. `0.0` when not
  /// buffering or when the duration is unknown.
  final ValueNotifier<double> bufferingProgress = ValueNotifier(0.0);

  Future<void> _persistInstant() async {
    if (!_canPersistProgress || _isReinitializing) return;
    final id = _activeAudiobookId;
    final idx = _player.currentIndex;
    if (id == null || idx == null) return;
    final liveMs = _player.position.inMilliseconds;
    historyOfAudiobook.updateAudiobookPosition(id, idx, liveMs);
    playingAudiobookDetailsBox.put('index', idx);
    playingAudiobookDetailsBox.put('position', liveMs);
    _lastPersistAt = DateTime.now();
  }

  /// Rebuild the queue from Hive on cold start *without* starting playback.
  Future<void> restoreIfNeeded() async {
    await _restoreQueueFromBoxIfEmpty(); // already silent (no play)
    // Make sure the UI gets an immediate state + current media item
    _broadcastState(_player.playbackEvent);
  }

  int? get currentIndex => _player.currentIndex;

  Future<void> _ensureAudioSession() async {
    if (_sessionConfigured) return;

    if (!_configureAudioSession) {
      _sessionConfigured = true;
      _bindStatePipelines();
      return;
    }

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    if (Platform.isAndroid) {
      await _player.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
      );
    }

    // Pause if headphones unplugged
    session.becomingNoisyEventStream.listen((_) {
      if (_player.playing) _player.pause();
    });

    _sessionConfigured = true;

    // Keep notification/media session state in lock-step with the real player
    _bindStatePipelines();
  }

  void _bindStatePipelines() {
    _eventSub?.cancel();
    _playerStateSub?.cancel();
    _playingSub?.cancel();
    _bufferedSub?.cancel();
    _coverSub?.cancel();

    _eventSub = _player.playbackEventStream.listen(_broadcastState);
    _playerStateSub = _player.playerStateStream.listen((_) {
      _broadcastState(_player.playbackEvent);
    });
    _playingSub = _player.playingStream.listen((_) {
      _broadcastState(_player.playbackEvent);
    });
    // Keep bufferingProgress ticking smoothly while the track pre-loads,
    // so play buttons can render a live % instead of a bare spinner.
    _bufferedSub = _player.bufferedPositionStream.listen((buffered) {
      if (!isBufferingYouTube.value) return;
      final duration = _player.duration;
      if (duration != null && duration.inMilliseconds > 0) {
        final frac = buffered.inMilliseconds / duration.inMilliseconds;
        final clamped = frac.clamp(0.0, 1.0);
        if ((bufferingProgress.value - clamped).abs() >= 0.005) {
          bufferingProgress.value = clamped;
        }
      }
    });

    // swap art immediately if the active audiobook’s cover mapping changes
    _coverSub = coverArtBus.stream.listen((key) {
      if (key.isEmpty) return;
      if (_activeAudiobookId == null) return;
      if (key == _activeAudiobookId) {
        _refreshActiveCoverArt();
      }
    });
  }

  Future<Uri?> _resolveActiveArtUri() async {
    final id = _activeAudiobookId;
    if (id == null) return null;

    // Prefer mapped cover (custom)
    final mapped = await getMappedCoverImage(id);
    final byMap = _artUriFrom(mapped);
    if (byMap != null) return byMap;

    // Fallback: whatever is in the "now playing" audiobook (Hive)
    try {
      final map = Map<String, dynamic>.from(
        playingAudiobookDetailsBox.get('audiobook') ?? {},
      );
      final v = map['lowQCoverImage'] as String?;
      final byBox = _artUriFrom(v);
      if (byBox != null) return byBox;
    } catch (_) {}

    // Last resort: keep existing item art
    return mediaItem.value?.artUri;
  }

  Future<void> _refreshActiveCoverArt() async {
    final id = _activeAudiobookId;
    if (id == null) return;
    if (_audioSources == null || queue.value.isEmpty) return;

    final newUri = await _resolveActiveArtUri();
    if (newUri == null) return;

    final old = queue.value;
    final rebuilt = <MediaItem>[];
    for (final item in old) {
      rebuilt.add(MediaItem(
        id: item.id,
        album: item.album,
        title: item.title,
        artist: item.artist,
        artUri: newUri,
        extras: item.extras,
        duration: item.duration,
        genre: item.genre,
        playable: item.playable,
        displayTitle: item.displayTitle,
        displaySubtitle: item.displaySubtitle,
        displayDescription: item.displayDescription,
        rating: item.rating,
      ));
    }

    addQueueItems([]);
    queue.add(rebuilt);

    final idx = _player.currentIndex ?? 0;
    if (idx >= 0 && idx < rebuilt.length) {
      mediaItem.add(rebuilt[idx]);
    }
  }

  Future<void> initSongs(
    List<AudiobookFile> files,
    Audiobook audiobook,
    int initialIndex,
    int positionInMilliseconds, {
    bool playImmediately = true,
  }) async {
    _isReinitializing = true;
    final myGen = ++_initGen;

    try {
      await _ensureAudioSession();

      // Disable persistence until the new queue is fully settled
      _canPersistProgress = false;
      _activeAudiobookId = audiobook.id;

      // Keep the "now playing" box in sync up front
      await playingAudiobookDetailsBox.put('audiobook', audiobook.toMap());
      await playingAudiobookDetailsBox.put(
        'audiobookFiles',
        files.map((f) => f.toMap()).toList(),
      );
      await playingAudiobookDetailsBox.put('index', initialIndex);
      await playingAudiobookDetailsBox.put('position', positionInMilliseconds);

      await _player.stop();

      queue.add([]);
      mediaItem.add(null);

      _positionUpdateTimer?.cancel();

      playbackState.add(
        playbackState.value.copyWith(
          controls: const [],
          systemActions: const {},
          processingState: AudioProcessingState.idle,
          playing: false,
          bufferedPosition: Duration.zero,
          speed: 1.0,
          queueIndex: null,
        ),
      );

      // Build MediaItems & Sources for ALL files
      final mediaItems = <MediaItem>[];
      final sources = <AudioSource>[];

      for (var idx = 0; idx < files.length; idx++) {
        final song = files[idx];
        final isYouTube = song.url?.contains('youtube.com') == true ||
            song.url?.contains('youtu.be') == true;

        String? artStr = audiobook.origin == "download"
            ? audiobook.lowQCoverImage
            : (song.highQCoverImage ?? audiobook.lowQCoverImage);
        final art = _artUriFrom(artStr);

        final item = MediaItem(
          id: song.track.toString(),
          album: audiobook.title,
          title: song.title ?? '',
          artist: audiobook.author ?? 'Unknown',
          artUri: art,
          duration: Duration(
              milliseconds: song.durationMs ??
                  (song.length != null ? (song.length! * 1000).toInt() : 0)),
          extras: {
            'url': song.url,
            'audiobook_id': audiobook.id,
            'is_youtube': isYouTube,
            'startMs': song.startMs,
            'durationMs': song.durationMs,
          },
        );
        mediaItems.add(item);

        if (isYouTube && song.url != null) {
          final videoId = VideoId.parseVideoId(song.url!) ?? song.url!;
          sources.add(
              YouTubeAudioSource(videoId: videoId, tag: item, quality: 'high'));
        } else if (song.url != null) {
          // Defense-in-depth: heal any raw non-ASCII / spaces in the URL
          // before handing it to the player. Sources should already
          // encode, but persisted state (Hive) from before the encoding
          // fix and edge-case paths can still carry raw Cyrillic.
          final safeUrl = sanitizePlayerUrl(song.url!);
          final uri = safeUrl.startsWith('/')
              ? Uri.file(safeUrl)
              : Uri.parse(safeUrl);

          if ((song.startMs ?? 0) > 0 || (song.durationMs ?? 0) > 0) {
            final start = Duration(milliseconds: song.startMs ?? 0);
            final end = (song.durationMs != null)
                ? start + Duration(milliseconds: song.durationMs!)
                : null;
            sources.add(
              ClippingAudioSource(
                start: start,
                end: end,
                child: AudioSource.uri(uri, tag: item),
              ),
            );
          } else {
            sources.add(AudioSource.uri(uri, tag: item));
          }
        }
      }

      if (myGen != _initGen) return;

      final safeIndex =
          sources.isEmpty ? 0 : initialIndex.clamp(0, sources.length - 1);

      addQueueItems(mediaItems);
      if (mediaItems.isNotEmpty) {
        mediaItem.add(mediaItems[safeIndex]);
      }

      _audioSources = sources;

      final currentIsYT = _isIndexYouTube(safeIndex);

      // wrap setAudioSources in try/catch that logs then rethrows
      // so the caller (audiobook_details) catches and shows a SnackBar.
      try {
        await _player.setAudioSources(
          _audioSources!,
          initialIndex: sources.isEmpty ? 0 : safeIndex,
          initialPosition: currentIsYT
              ? Duration.zero
              : Duration(milliseconds: positionInMilliseconds),
          preload: playImmediately,
        );
      } catch (e) {
        AppLogger.debug('initSongs: setAudioSources failed: $e');
        rethrow;
      }

      if (myGen != _initGen) return;

      await _player.seek(Duration(milliseconds: positionInMilliseconds),
          index: safeIndex);

      if (playImmediately) {
        // D-01: Await ProcessingState.ready before play(). BehaviorSubject
        // replays the last value, so already-ready sources (LibriVox, YouTube,
        // knigavuhe, 4read) complete synchronously — zero added latency.
        // Sound-Books (loading during duration probe) waits until ready or 10s.
        try {
          await _player.processingStateStream
              .firstWhere((s) => s == ProcessingState.ready)
              .timeout(_readyTimeout);
        } on TimeoutException {
          AppLogger.error(
              'initSongs: timed out waiting for ProcessingState.ready after ${_readyTimeout.inSeconds}s');
          rethrow;
        }

        // D-02: Stale init — a newer initSongs may have started during the await.
        if (myGen != _initGen) return;

        _player.play();
      }

      await _waitForStartToSettle(
        safeIndex,
        positionInMilliseconds,
        isYouTube: currentIsYT,
        timeout: const Duration(seconds: 3),
      );

      if (myGen != _initGen) return;

      _listenForCurrentSongIndexChanges();

      historyOfAudiobook.addToHistory(
        audiobook,
        files,
        safeIndex,
        positionInMilliseconds,
      );

      _startPositionUpdateTimer(audiobook.id);

      _canPersistProgress = true;
      _lastPersistAt = DateTime.now().subtract(_persistInterval);

      _broadcastState(_player.playbackEvent);
    } finally {
      // Only the active gen clears the flag — a stale init (superseded
      // by a newer ++_initGen) must not clobber the newer init's flag.
      if (myGen == _initGen) {
        _isReinitializing = false;
      }
    }
  }

  bool _isIndexYouTube(int index) {
    final children = _audioSources;
    if (children == null || index < 0 || index >= children.length) return false;
    return children[index] is YouTubeAudioSource;
  }

  Future<void> _waitForStartToSettle(
    int index,
    int positionMs, {
    required bool isYouTube,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final posEpsMs = isYouTube ? 2500 : 1200;

    while (DateTime.now().isBefore(deadline)) {
      final idxOk = _player.currentIndex == index;
      final posOk =
          (_player.position.inMilliseconds - positionMs).abs() <= posEpsMs;

      if (idxOk && posOk) return;
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    queue.add(queue.value..addAll(mediaItems));
  }

  void _listenForCurrentSongIndexChanges() {
    _player.currentIndexStream.listen((index) {
      if (_isReinitializing) return;
      if (index == null) return;

      final playList = queue.value;
      if (index >= playList.length) return;

      final item = playList[index];
      mediaItem.add(item);
      playingAudiobookDetailsBox.put('index', index);

      if (!_canPersistProgress) return;

      final audiobookId = item.extras?['audiobook_id'] as String?;
      if (audiobookId == null || audiobookId != _activeAudiobookId) return;
      if (!_player.playing) return;

      _persistNow(audiobookId, index);
    });
  }

  void _persistNow(String audiobookId, int index) {
    final now = DateTime.now();
    if (now.difference(_lastPersistAt) < _persistInterval) return;

    final liveMs = _player.position.inMilliseconds;
    if (liveMs >= 0) {
      historyOfAudiobook.updateAudiobookPosition(audiobookId, index, liveMs);
      playingAudiobookDetailsBox.put('position', liveMs);
      _lastPersistAt = now;
      AppLogger.debug('Position updated: $liveMs ms');
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processing = _player.processingState;
    final audioProcessing = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[processing]!;

    // Update YouTube buffering state (only when NOT playing yet)
    final currentIndex = _player.currentIndex;
    final isYT = currentIndex != null && _isIndexYouTube(currentIndex);
    final needsBuffering = (processing == ProcessingState.buffering ||
            processing == ProcessingState.loading) &&
        !playing;
    isBufferingYouTube.value = isYT && needsBuffering;

    // Update buffering progress so play buttons can show a real %.
    // While actively buffering/loading, report bufferedPosition/duration.
    if (needsBuffering) {
      final duration = _player.duration;
      final buffered = _player.bufferedPosition;
      if (duration != null && duration.inMilliseconds > 0) {
        final frac = buffered.inMilliseconds / duration.inMilliseconds;
        bufferingProgress.value = frac.clamp(0.0, 1.0);
      } else {
        bufferingProgress.value = 0.0;
      }
    } else {
      bufferingProgress.value = 0.0;
    }

    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      MediaControl.skipToNext,
    ];

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setSpeed,
        },
        processingState: audioProcessing,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }

  void _startPositionUpdateTimer(String audiobookId) {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isReinitializing || !_canPersistProgress) return;
      if (audiobookId != _activeAudiobookId) return;
      if (!_player.playing) return;

      final currentIndex = _player.currentIndex;
      if (currentIndex != null) {
        _persistNow(audiobookId, currentIndex);
        // Record 10 seconds of listening for stats
        _recordListeningSession();
      }
    });
  }

  void _recordListeningSession() {
    try {
      final statsBox = Hive.box('listening_stats_box');
      final current = statsBox.get('totalSeconds', defaultValue: 0) as int;
      statsBox.put('totalSeconds', current + 10);
      statsBox.put('totalSessions',
          (statsBox.get('totalSessions', defaultValue: 0) as int) + 1);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      statsBox.put('lastDate', today);
      final streak = (statsBox.get('streak', defaultValue: <String>[]) as List)
          .cast<String>();
      if (!streak.contains(today)) {
        streak.add(today);
        if (streak.length > 365) streak.removeAt(0);
        statsBox.put('streak', streak);
      }
    } catch (_) {}
  }

  Stream<PositionData> getPositionStream() {
    return Rx.combineLatest3<Duration, Duration, int?, PositionData>(
      _player.positionStream,
      _player.bufferedPositionStream,
      _player.currentIndexStream,
      (position, bufferedPosition, index) {
        final currentSequence = _player.sequence;

        if (index != null && index < currentSequence.length) {
          final tag = currentSequence[index].tag;
          final item = tag as MediaItem?;
          final metaDuration = item?.duration ??
              Duration(milliseconds: item?.extras?['durationMs'] as int? ?? 0);

          // Use player's actual duration as primary, fallback to metadata
          final trackDuration = _player.duration != null &&
                  _player.duration! > Duration.zero
              ? _player.duration!
              : (metaDuration > Duration.zero ? metaDuration : Duration.zero);

          return PositionData(position, bufferedPosition, trackDuration);
        }

        return PositionData(position, bufferedPosition, Duration.zero);
      },
    );
  }

  Future<void> _restoreQueueFromBoxIfEmpty(
      {bool playImmediately = false}) async {
    if (_isReinitializing) return;
    if ((_audioSources?.isNotEmpty ?? false)) return;

    try {
      final box = playingAudiobookDetailsBox;
      final storedAudiobookMap = box.get('audiobook');
      final storedFiles = box.get('audiobookFiles');
      if (storedAudiobookMap == null || storedFiles == null) return;

      final audiobook =
          Audiobook.fromMap(Map<String, dynamic>.from(storedAudiobookMap));
      final files = (storedFiles as List)
          .map(
              (e) => AudiobookFile.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      final index = (box.get('index') as int?) ?? 0;
      final position = (box.get('position') as int?) ?? 0;

      await initSongs(files, audiobook, index, position,
          playImmediately: playImmediately);
    } catch (_) {}
  }

  String? getCurrentAudiobookId() {
    final extras = mediaItem.value?.extras;
    return extras == null ? null : (extras['audiobook_id'] as String?);
  }

  List<AudioSource> getAudioSourcesFromPlaylist() {
    return _audioSources ?? const [];
  }

  @override
  Future<void> play() async {
    AppLogger.debug(
        'MyAudioHandler: play() called, processingState=${_player.processingState}, playing=${_player.playing}');
    await _restoreQueueFromBoxIfEmpty(); // only at cold start

    await _player.play();

    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    final id = _activeAudiobookId;
    final idx = _player.currentIndex;
    if (_canPersistProgress &&
        !_isReinitializing &&
        id != null &&
        idx != null) {
      _persistNow(id, idx);
    }
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> stop() async {
    _positionUpdateTimer?.cancel();
    await _player.stop();
    _coverSub?.cancel();
    _broadcastState(_player.playbackEvent);
    await _persistInstant();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcastState(_player.playbackEvent);
    await _persistInstant();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
    await _persistInstant();
    await play();
  }

  @override
  Future<void> skipToNext() async {
    await _player.seekToNext();
    _broadcastState(_player.playbackEvent);
    await _persistInstant();
  }

  @override
  Future<void> skipToPrevious() async {
    await _player.seekToPrevious();
    _broadcastState(_player.playbackEvent);
    await _persistInstant();
  }

  static const _ffAmount = Duration(seconds: 15);
  static const _rwAmount = Duration(seconds: 10);

  @override
  Future<void> fastForward() async {
    final newPos = _player.position + _ffAmount;
    await _player.seek(newPos);
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> rewind() async {
    final newPos = _player.position - _rwAmount;
    await _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _broadcastState(_player.playbackEvent);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  Future<void> setSkipSilence(bool skipSilence) async {
    await _player.setSkipSilenceEnabled(skipSilence);
  }

  Future<void> setEqualizerBand(int bandIndex, double gain) async {
    try {
      if (_equalizer == null) return;
      final clampedGain = gain.clamp(-15.0, 15.0);
      final parameters = await _equalizer.parameters;
      final bands = parameters.bands;
      if (bandIndex >= 0 && bandIndex < bands.length) {
        await bands[bandIndex].setGain(clampedGain);
      }
    } catch (e) {
      AppLogger.error('Error setting equalizer band: $e');
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    try {
      if (!Platform.isAndroid) return;
      await _equalizer!.setEnabled(enabled);
    } catch (e) {
      AppLogger.error('Error setting equalizer enabled: $e');
    }
  }

  Future<void> setBalance(double balance) async {
    try {
      await _player.setBalance(balance);
    } catch (e) {
      AppLogger.error('Error setting balance: $e');
    }
  }

  Future<void> setPitch(double pitch) async {
    try {
      await _player.setPitch(pitch);
    } catch (e) {
      AppLogger.error('Error setting pitch: $e');
    }
  }

  Future<void> setLoudnessEnhancer(double targetGain) async {
    try {
      if (!Platform.isAndroid) return;
      if (_loudnessEnhancer == null) return;
      await _loudnessEnhancer.setTargetGain(targetGain.clamp(0.0, 1000.0));
    } catch (e) {
      AppLogger.error('Error setting loudness enhancer: $e');
    }
  }

  Future<AndroidEqualizerParameters?> getEqualizerParameters() async {
    try {
      if (!Platform.isAndroid) return null;
      return await _equalizer!.parameters;
    } catch (e) {
      AppLogger.error('Error getting equalizer parameters: $e');
      return null;
    }
  }

  Duration get position => _player.position;

  void playPrevious() {
    final length = _audioSources?.length ?? 0;
    if (_player.currentIndex != null && _player.currentIndex! > 0) {
      _player.seekToPrevious();
    } else if (length > 0) {
      _player.seek(Duration.zero, index: 0);
    }
  }

  void playNext() {
    final length = _audioSources?.length ?? 0;
    if (_player.currentIndex != null &&
        length > 0 &&
        _player.currentIndex! < length - 1) {
      _player.seekToNext();
    }
  }
}

class PositionData {
  const PositionData(this.position, this.bufferedPosition, this.duration);
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
}
