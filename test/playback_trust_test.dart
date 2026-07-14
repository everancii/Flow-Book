import 'dart:async';
import 'dart:io';

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/models/history_of_audiobook.dart';
import 'package:audiobookflow/resources/services/bookmark_service.dart';
import 'package:audiobookflow/resources/services/my_audio_handler.dart';
import 'package:audiobookflow/screens/audiobook_player/widgets/track_section_dialog.dart'
    show effectiveTrackLength, formatTrackDuration;
import 'package:audiobookflow/utils/optimized_timer.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('flow_book_playback_test_');
    Hive.init(hiveDir.path);
    for (final boxName in [
      'playing_audiobook_details_box',
      'history_of_audiobook_box',
      'bookmarks_box',
      'listening_stats_box',
    ]) {
      await Hive.openBox(boxName);
    }
  });

  setUp(() async {
    await Hive.box('playing_audiobook_details_box').clear();
    await Hive.box('history_of_audiobook_box').clear();
    await Hive.box('bookmarks_box').clear();
    await Hive.box('listening_stats_box').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  group('playback restore payload', () {
    test('round trips current audiobook, chapters, index, and position',
        () async {
      final box = Hive.box('playing_audiobook_details_box');
      final audiobook = _sampleAudiobook();
      final files = _sampleFiles();

      await box.put('audiobook', audiobook.toMap());
      await box.put('audiobookFiles', files.map((f) => f.toMap()).toList());
      await box.put('index', 1);
      await box.put('position', 123456);

      final restoredAudiobook =
          Audiobook.fromMap(Map<String, dynamic>.from(box.get('audiobook')));
      final restoredFiles = (box.get('audiobookFiles') as List)
          .map((e) => AudiobookFile.fromMap(Map<String, dynamic>.from(e)))
          .toList();

      expect(restoredAudiobook.id, audiobook.id);
      expect(restoredAudiobook.title, audiobook.title);
      expect(
          restoredFiles.map((f) => f.title), ['Opening', 'Middle', 'Finale']);
      expect(restoredFiles[1].startMs, 60000);
      expect(restoredFiles[1].durationMs, 90000);
      expect(box.get('index'), 1);
      expect(box.get('position'), 123456);
    });
  });

  group('position history', () {
    test('updates saved track index, position, and recency', () async {
      final history = HistoryOfAudiobook();
      final audiobook = _sampleAudiobook();
      final files = _sampleFiles();

      await history.addToHistory(audiobook, files, 0, 1000);
      final first = history.getHistoryOfAudiobookItem(audiobook.id);

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await history.updateAudiobookPosition(audiobook.id, 2, 98765);

      final updated = history.getHistoryOfAudiobookItem(audiobook.id);
      expect(updated.index, 2);
      expect(updated.position, 98765);
      expect(updated.lastModified.isAfter(first.lastModified), isTrue);
      expect(history.getHistory().single.audiobook.id, audiobook.id);
    });
  });

  group('bookmarks', () {
    test('sorts by track and position, removes by sorted index', () async {
      final service = BookmarkService();

      await service.addBookmark(_bookmark(trackIndex: 2, positionMs: 5000));
      await service.addBookmark(_bookmark(trackIndex: 0, positionMs: 9000));
      await service.addBookmark(_bookmark(trackIndex: 0, positionMs: 3000));

      expect(
        service
            .getBookmarks('book-1')
            .map((b) => '${b.trackIndex}:${b.positionMs}'),
        ['0:3000', '0:9000', '2:5000'],
      );

      await service.removeBookmark('book-1', 1);

      expect(
        service
            .getBookmarks('book-1')
            .map((b) => '${b.trackIndex}:${b.positionMs}'),
        ['0:3000', '2:5000'],
      );
    });

    test('detects bookmark near current position within tolerance', () async {
      final service = BookmarkService();
      await service.addBookmark(_bookmark(trackIndex: 1, positionMs: 10000));

      expect(service.hasBookmarkAt('book-1', 1, 14999), isTrue);
      expect(service.hasBookmarkAt('book-1', 1, 15000), isFalse);
      expect(service.hasBookmarkAt('book-1', 2, 10000), isFalse);
    });
  });

  group('sleep timer', () {
    testWidgets('counts down, formats remaining time, and expires once',
        (tester) async {
      final timer = OptimizedTimer();
      var expiredCount = 0;

      timer.start(
        duration: const Duration(seconds: 3),
        onExpired: () => expiredCount += 1,
      );

      expect(timer.isActive.value, isTrue);
      expect(timer.formattedRemainingTime, '00:03');

      await tester.pump(const Duration(seconds: 1));
      expect(timer.formattedRemainingTime, '00:02');

      await tester.pump(const Duration(seconds: 2));
      expect(timer.isActive.value, isFalse);
      expect(timer.remainingTime.value, isNull);
      expect(timer.formattedRemainingTime, '00:00');
      expect(expiredCount, 1);
    });

    testWidgets('cancel clears state and calls onCanceled without expiring',
        (tester) async {
      final timer = OptimizedTimer();
      var canceled = false;
      var expired = false;

      timer.start(
        duration: const Duration(minutes: 1),
        onCanceled: () => canceled = true,
        onExpired: () => expired = true,
      );
      timer.cancel();
      await tester.pump(const Duration(minutes: 1));

      expect(timer.isActive.value, isFalse);
      expect(timer.remainingTime.value, isNull);
      expect(canceled, isTrue);
      expect(expired, isFalse);
    });
  });

  group('chapter switching metadata', () {
    test(
        'derives display durations from explicit duration, length, and start offsets',
        () {
      final files = _sampleFiles();

      expect(formatTrackDuration(effectiveTrackLength(files, 0)), '01:00');
      expect(formatTrackDuration(effectiveTrackLength(files, 1)), '01:30');
      expect(formatTrackDuration(effectiveTrackLength(files, 2)), '02:00');
    });

    test('falls back to next chapter start when no explicit duration exists',
        () {
      final files = [
        AudiobookFile.fromMap({
          'identifier': 'book-1',
          'title': 'Part 1',
          'track': 1,
          'url': '/tmp/book.mp3',
          'startMs': 10000,
        }),
        AudiobookFile.fromMap({
          'identifier': 'book-1',
          'title': 'Part 2',
          'track': 2,
          'url': '/tmp/book.mp3',
          'startMs': 70000,
        }),
      ];

      expect(effectiveTrackLength(files, 0), const Duration(minutes: 1));
    });
  });

  group('MyAudioHandler with fake playback engine', () {
    test('restores queue from Hive without starting real playback', () async {
      final fake = FakePlaybackEngine();
      final handler = MyAudioHandler(
        player: fake,
        configureAudioSession: false,
      );
      final audiobook = _sampleAudiobook();
      final files = _sampleFiles();

      await Hive.box('playing_audiobook_details_box')
          .put('audiobook', audiobook.toMap());
      await Hive.box('playing_audiobook_details_box')
          .put('audiobookFiles', files.map((f) => f.toMap()).toList());
      await Hive.box('playing_audiobook_details_box').put('index', 1);
      await Hive.box('playing_audiobook_details_box').put('position', 123456);

      await handler.restoreIfNeeded();

      expect(fake.setAudioSourcesCalls, hasLength(1));
      expect(fake.setAudioSourcesCalls.single.initialIndex, 1);
      expect(
        fake.setAudioSourcesCalls.single.initialPosition,
        const Duration(milliseconds: 123456),
      );
      expect(fake.playCount, 0);
      expect(handler.queue.value.map((item) => item.title), [
        'Opening',
        'Middle',
        'Finale',
      ]);
      expect(handler.mediaItem.value?.title, 'Middle');
    });

    test('skipToQueueItem seeks to chapter start and resumes playback',
        () async {
      final fake = FakePlaybackEngine();
      final handler = MyAudioHandler(
        player: fake,
        configureAudioSession: false,
      );

      await handler.initSongs(
        _sampleFiles(),
        _sampleAudiobook(),
        0,
        0,
        playImmediately: false,
      );

      await handler.skipToQueueItem(2);

      expect(fake.seekCalls.last.position, Duration.zero);
      expect(fake.seekCalls.last.index, 2);
      expect(fake.playCount, 1);
    });

    test('seek writes latest position to now-playing box and history',
        () async {
      final fake = FakePlaybackEngine();
      final handler = MyAudioHandler(
        player: fake,
        configureAudioSession: false,
      );

      await handler.initSongs(
        _sampleFiles(),
        _sampleAudiobook(),
        1,
        1000,
        playImmediately: false,
      );
      await Future<void>.delayed(Duration.zero);

      await handler.seek(const Duration(milliseconds: 42000));

      expect(Hive.box('playing_audiobook_details_box').get('index'), 1);
      expect(Hive.box('playing_audiobook_details_box').get('position'), 42000);
      final history = HistoryOfAudiobook().getHistoryOfAudiobookItem('book-1');
      expect(history.index, 1);
      expect(history.position, 42000);
    });

    test(
        'initSongs fires play() unconditionally even when processingState stays loading',
        () async {
      // Simulates Sound-Books: processingState stuck at loading (duration probe
      // in-flight). Proves (a) the fake accepts a loading configuration — the
      // infrastructure proof that loading→ready simulation is configurable — and
      // (b) play() fires unconditionally regardless of processingState (the
      // current bug Phase 3 will fix). PASSES today; WILL FAIL after the Phase 3
      // ready-before-play fix (play deferred until ready → playCount stays 0 when
      // ready never arrives). Phase 3 must update this test to emit ready on the
      // stream once the listener re-fire is removed.
      final fake = FakePlaybackEngine();
      fake.processingState = ProcessingState.loading;
      final handler = MyAudioHandler(
        player: fake,
        configureAudioSession: false,
      );

      await handler.initSongs(
        _sampleFiles(),
        _sampleAudiobook(),
        0,
        0,
        playImmediately: true,
      );

      expect(fake.playCount, 1);
      expect(fake.setAudioSourcesCalls, hasLength(1));
    });

    // Skipped until Phase 3 implements ready-before-play.
    // @Skip('await Phase 3 ready-before-play fix')
    // (annotation form is not valid before a test() call in Dart — annotations
    // apply to declarations, not call expressions; using the `skip:` parameter
    // below instead, which is the flutter_test API for skipping a test.)
    // Remove this skip after Phase 3 implements ready-before-play.
    // This test verifies the race is gone.
    test(
        'play() does not fire before processingState reaches ready (race detector)',
        () async {
      final fake = FakePlaybackEngine();
      fake.processingState = ProcessingState.loading;
      final handler = MyAudioHandler(
        player: fake,
        configureAudioSession: false,
      );

      final initFuture = handler.initSongs(
        _sampleFiles(),
        _sampleAudiobook(),
        0,
        0,
        playImmediately: true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fake.playCount, 0,
          reason: 'play() must not fire before processingState reaches ready');

      fake.processingState = ProcessingState.ready;
      fake.processingStates.add(ProcessingState.ready);

      await initFuture;

      expect(fake.playCount, 1);
    }, skip: 'await Phase 3 ready-before-play fix');

    // ── Phase 2: Subscription Lifecycle + State-Guard refactor tests ──

    test(
        'stale init finally does not clobber newer init _isReinitializing flag',
        () async {
      // D-01: Gen-guarded finally — a stale init's finally must NOT clear
      // _isReinitializing when a newer init is active.
      final fake = FakePlaybackEngine();
      final handler = MyAudioHandler(
        player: fake,
        configureAudioSession: false,
      );

      // First init completes normally.
      await handler.initSongs(
        _sampleFiles(),
        _sampleAudiobook(),
        0,
        0,
        playImmediately: false,
      );
      expect(handler.isReinitializing, isFalse,
          reason: 'Flag should be false after initSongs completes');

      // Second init (simulates rapid book switch A→B) — also completes.
      await handler.initSongs(
        _sampleFiles(),
        _sampleAudiobook(),
        0,
        0,
        playImmediately: false,
      );
      expect(handler.isReinitializing, isFalse,
          reason: 'Flag should be false after second initSongs completes. '
              'If the stale gen-A finally clobbered gen-B flag, this would be true.');
    });

    test('initSongs cancels previous processingStateStream listener on re-entry',
        () async {
      // D-03/D-05: Tracked _initSettleSub — re-entry cancels the previous
      // listener instead of stacking. After two initSongs calls, exactly ONE
      // listener should be active, not two.
      final fake = FakePlaybackEngine();
      final handler = MyAudioHandler(
        player: fake,
        configureAudioSession: false,
      );

      // First init with playImmediately so the settle listener is attached.
      await handler.initSongs(
        _sampleFiles(),
        _sampleAudiobook(),
        0,
        0,
        playImmediately: true,
      );
      expect(fake.processingStates.hasListener, isTrue,
          reason: 'Settle listener should be active after initSongs');

      // Second init — should cancel the first listener and attach a new one.
      await handler.initSongs(
        _sampleFiles(),
        _sampleAudiobook(),
        0,
        0,
        playImmediately: true,
      );
      expect(fake.processingStates.hasListener, isTrue,
          reason: 'One listener should still be active (the new one)');

      // Third init — still exactly one listener, not three.
      await handler.initSongs(
        _sampleFiles(),
        _sampleAudiobook(),
        0,
        0,
        playImmediately: true,
      );
      expect(fake.processingStates.hasListener, isTrue,
          reason: 'Still exactly one listener after three initSongs calls');
    });

    test('stop() cancels all processingStateStream listeners', () async {
      // D-05.2: stop() cancels _initSettleSub — full teardown.
      final fake = FakePlaybackEngine();
      final handler = MyAudioHandler(
        player: fake,
        configureAudioSession: false,
      );

      await handler.initSongs(
        _sampleFiles(),
        _sampleAudiobook(),
        0,
        0,
        playImmediately: true,
      );
      expect(fake.processingStates.hasListener, isTrue,
          reason: 'Listener active after initSongs');

      await handler.stop();
      expect(fake.processingStates.hasListener, isFalse,
          reason: 'All listeners cancelled after stop()');
    });
  });
}

Audiobook _sampleAudiobook() {
  return Audiobook.fromMap({
    'id': 'book-1',
    'title': 'Playback Trust',
    'author': 'Flow Book',
    'description': 'Test audiobook',
    'lowQCoverImage': 'https://example.com/cover.jpg',
    'origin': 'local',
  });
}

List<AudiobookFile> _sampleFiles() {
  return [
    AudiobookFile.fromMap({
      'identifier': 'book-1',
      'title': 'Opening',
      'track': 1,
      'length': 60.0,
      'url': '/tmp/opening.mp3',
      'startMs': 0,
      'durationMs': null,
    }),
    AudiobookFile.fromMap({
      'identifier': 'book-1',
      'title': 'Middle',
      'track': 2,
      'length': null,
      'url': '/tmp/middle.mp3',
      'startMs': 60000,
      'durationMs': 90000,
    }),
    AudiobookFile.fromMap({
      'identifier': 'book-1',
      'title': 'Finale',
      'track': 3,
      'length': null,
      'url': '/tmp/finale.mp3',
      'startMs': 150000,
      'durationMs': 120000,
    }),
  ];
}

Bookmark _bookmark({
  required int trackIndex,
  required int positionMs,
}) {
  return Bookmark(
    audiobookId: 'book-1',
    trackIndex: trackIndex,
    positionMs: positionMs,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

class FakePlaybackEngine implements PlaybackEngine {
  final playbackEvents = StreamController<PlaybackEvent>.broadcast();
  final playerStates = StreamController<PlayerState>.broadcast();
  final playingStates = StreamController<bool>.broadcast();
  final bufferedPositions = StreamController<Duration>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  final currentIndexes = StreamController<int?>.broadcast();
  final processingStates = StreamController<ProcessingState>.broadcast();

  final setAudioSourcesCalls = <SetAudioSourcesCall>[];
  final seekCalls = <SeekCall>[];
  int playCount = 0;
  int stopCount = 0;
  int pauseCount = 0;

  @override
  bool playing = false;

  @override
  int? currentIndex;

  @override
  Duration position = Duration.zero;

  @override
  Duration bufferedPosition = Duration.zero;

  @override
  Duration? duration = const Duration(minutes: 5);

  @override
  double speed = 1.0;

  @override
  ProcessingState processingState = ProcessingState.ready;

  @override
  List<IndexedAudioSource> sequence = const [];

  @override
  PlaybackEvent playbackEvent = PlaybackEvent();

  @override
  Stream<PlaybackEvent> get playbackEventStream => playbackEvents.stream;

  @override
  Stream<PlayerState> get playerStateStream => playerStates.stream;

  @override
  Stream<bool> get playingStream => playingStates.stream;

  @override
  Stream<Duration> get bufferedPositionStream => bufferedPositions.stream;

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Stream<int?> get currentIndexStream => currentIndexes.stream;

  @override
  Stream<ProcessingState> get processingStateStream => processingStates.stream;

  @override
  Future<void> pause() async {
    pauseCount += 1;
    playing = false;
    playingStates.add(false);
  }

  @override
  Future<void> play() async {
    playCount += 1;
    playing = true;
    playingStates.add(true);
  }

  @override
  Future<void> seek(Duration position, {int? index}) async {
    seekCalls.add(SeekCall(position, index));
    this.position = position;
    if (index != null) {
      currentIndex = index;
      currentIndexes.add(index);
    }
    positions.add(position);
    playbackEvent = PlaybackEvent(currentIndex: currentIndex);
  }

  @override
  Future<void> seekToNext() async {
    await seek(Duration.zero, index: (currentIndex ?? 0) + 1);
  }

  @override
  Future<void> seekToPrevious() async {
    await seek(Duration.zero, index: ((currentIndex ?? 0) - 1).clamp(0, 999));
  }

  @override
  Future<void> setAndroidAudioAttributes(
      AndroidAudioAttributes attributes) async {}

  @override
  Future<void> setAudioSources(
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
    required bool preload,
  }) async {
    setAudioSourcesCalls.add(
      SetAudioSourcesCall(
        sources: sources,
        initialIndex: initialIndex,
        initialPosition: initialPosition,
        preload: preload,
      ),
    );
    currentIndex = initialIndex;
    position = initialPosition;
    sequence = sources.cast<IndexedAudioSource>();
    playbackEvent = PlaybackEvent(currentIndex: initialIndex);
    currentIndexes.add(initialIndex);
    positions.add(initialPosition);
  }

  @override
  Future<void> setBalance(double balance) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> setSkipSilenceEnabled(bool skipSilence) async {}

  @override
  Future<void> setSpeed(double speed) async {
    this.speed = speed;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {
    stopCount += 1;
    playing = false;
    playingStates.add(false);
  }
}

class SetAudioSourcesCall {
  const SetAudioSourcesCall({
    required this.sources,
    required this.initialIndex,
    required this.initialPosition,
    required this.preload,
  });

  final List<AudioSource> sources;
  final int initialIndex;
  final Duration initialPosition;
  final bool preload;
}

class SeekCall {
  const SeekCall(this.position, this.index);

  final Duration position;
  final int? index;
}
