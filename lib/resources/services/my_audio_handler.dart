// lib/resources/services/my_audio_handler.dart
import 'dart:async';
import 'dart:io';

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/models/history_of_audiobook.dart';
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

class MyAudioHandler extends BaseAudioHandler {
  // Audio effects (Android-only)
  final AndroidEqualizer? _equalizer =
      Platform.isAndroid ? AndroidEqualizer() : null;
  final AndroidLoudnessEnhancer? _loudnessEnhancer =
      Platform.isAndroid ? AndroidLoudnessEnhancer() : null;

  late final AudioPlayer _player;

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

  MyAudioHandler() {
    final effects = [
      if (_equalizer != null) _equalizer,
      if (_loudnessEnhancer != null) _loudnessEnhancer,
    ];
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: effects,
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

  // Subscriptions to keep PlaybackState in sync
  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<bool>? _playingSub;

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
    _coverSub?.cancel();

    _eventSub = _player.playbackEventStream.listen(_broadcastState);
    _playerStateSub = _player.playerStateStream.listen((_) {
      _broadcastState(_player.playbackEvent);
    });
    _playingSub = _player.playingStream.listen((_) {
      _broadcastState(_player.playbackEvent);
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
          duration: Duration(milliseconds: song.durationMs ?? (song.length != null ? (song.length! * 1000).toInt() : 0)),
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
          final uri = song.url!.startsWith('/')
              ? Uri.file(song.url!)
              : Uri.parse(song.url!);

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

      await _player.setAudioSources(
        _audioSources!,
        initialIndex: sources.isEmpty ? 0 : safeIndex,
        initialPosition: currentIsYT
            ? Duration.zero
            : Duration(milliseconds: positionInMilliseconds),
        preload: playImmediately,
      );

      if (myGen != _initGen) return;

      if (currentIsYT && positionInMilliseconds > 0) {
        if (playImmediately) {
          await _waitForProcessingReady(timeout: const Duration(seconds: 5));
        }
        await _player.seek(Duration(milliseconds: positionInMilliseconds),
            index: safeIndex);
      } else {
        await _player.seek(Duration(milliseconds: positionInMilliseconds),
            index: safeIndex);
      }

      if (playImmediately) {
        AppLogger.debug('initSongs: calling _player.play(), state=${_player.processingState}');
        _player.play();
        
        // Listen for processing state changes to re-trigger play if we enter buffering
        DateTime? bufferingStarted;
        final sub = _player.processingStateStream.listen((state) {
          AppLogger.debug('initSongs: processingState=$state');
          
          if (state == ProcessingState.ready) {
            AppLogger.debug('initSongs: player ready, ensuring play');
            bufferingStarted = null;
            _player.play();
          } else if (state == ProcessingState.buffering) {
            // Track when buffering started
            bufferingStarted ??= DateTime.now();
          } else if (state == ProcessingState.idle && _player.playing) {
            // If player goes idle while supposed to be playing, try to recover
            AppLogger.debug('initSongs: player went idle, attempting recovery');
            Future.delayed(const Duration(milliseconds: 500), () {
              if (_player.processingState == ProcessingState.idle) {
                _player.play();
              }
            });
          }
          
          // If stuck in buffering for more than 30 seconds, log and try to recover
          if (state == ProcessingState.buffering && bufferingStarted != null) {
            final stuckDuration = DateTime.now().difference(bufferingStarted!);
            if (stuckDuration > const Duration(seconds: 30)) {
              AppLogger.error('initSongs: stuck in buffering for ${stuckDuration.inSeconds}s, attempting skip');
              bufferingStarted = null;
              // Try to skip to next track
              Future.delayed(const Duration(milliseconds: 100), () {
                try {
                  _player.seekToNext();
                  _player.play();
                } catch (_) {}
              });
            }
          }
        });
        
        // Timeout to cancel the listener
        Future.delayed(const Duration(seconds: 60), () => sub.cancel());
      }

      _player.processingStateStream.listen((state) {
        AppLogger.debug('initSongs: player processingState=$state');
      });

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
      _isReinitializing = false;
    }
  }

  bool _isIndexYouTube(int index) {
    final children = _audioSources;
    if (children == null || index < 0 || index >= children.length) return false;
    return children[index] is YouTubeAudioSource;
  }

  Future<void> _waitForProcessingReady(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_player.processingState == ProcessingState.ready) return;
      await Future.delayed(const Duration(milliseconds: 50));
    }
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
      statsBox.put('totalSessions', (statsBox.get('totalSessions', defaultValue: 0) as int) + 1);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      statsBox.put('lastDate', today);
      final streak = (statsBox.get('streak', defaultValue: <String>[]) as List).cast<String>();
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
        final currentSequence = _player.sequence ?? [];

        if (index != null && index < currentSequence.length) {
          final tag = currentSequence[index].tag;
          final item = tag as MediaItem?;
          final metaDuration = item?.duration ??
              Duration(
                  milliseconds: item?.extras?['durationMs'] as int? ?? 0);

          // Use player's actual duration as primary, fallback to metadata
          final trackDuration = _player.duration != null &&
                  _player.duration! > Duration.zero
              ? _player.duration!
              : (metaDuration > Duration.zero
                  ? metaDuration
                  : Duration.zero);

          return PositionData(position, bufferedPosition, trackDuration);
        }

        return PositionData(position, bufferedPosition, Duration.zero);
      },
    );
  }

  Future<void> _restoreQueueFromBoxIfEmpty({bool playImmediately = false}) async {
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

      await initSongs(files, audiobook, index, position, playImmediately: playImmediately);
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
  AppLogger.debug('MyAudioHandler: play() called, processingState=${_player.processingState}, playing=${_player.playing}');
  await _restoreQueueFromBoxIfEmpty(); // only at cold start

  await _player.play();

  _broadcastState(_player.playbackEvent);
}
  @override
  Future<void> pause() async {
    await _player.pause();
    final id = _activeAudiobookId;
    final idx = _player.currentIndex;
    if (_canPersistProgress && !_isReinitializing && id != null && idx != null) {
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
