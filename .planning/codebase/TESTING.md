# Testing Patterns

**Analysis Date:** 2026-07-13

## Test Framework

**Runner:**
- `flutter_test` (SDK-bundled) — no separate test runner package
- Config: `pubspec.yaml` dev_dependencies → `flutter_test: sdk: flutter` (`pubspec.yaml:76-77`)
- No `jest.config.*` / `vitest.config.*` equivalent — Flutter auto-discovers `test/**/*_test.dart`
- Linting in tests: inherits `analysis_options.yaml` `flutter_lints` set; `scratch/**` excluded

**Assertion Library:**
- `flutter_test` built-in `expect(actual, matcher)` + `matcher` package (`equals`, `isTrue`, `isFalse`, `isA<T>()`, `findsOneWidget`, `findsNWidgets`, `isNot`, `contains`, `startsWith`, `hasLength`)
- No `shouldly` / custom assertions

**Run Commands:**
```bash
flutter test                      # Run all tests
flutter test test/widget_test.dart        # Run single file
flutter test --plain-name "splits"        # Run by test name substring
flutter test --coverage                   # Generate coverage (lcov)
flutter analyze test/                     # Static analysis on tests
```

**Current state (as of analysis date):** `flutter test` → **44 pass / 4 fail** out of 48 tests. Failures listed in "Test Coverage Gaps" below.

## Test File Organization

**Location:**
- Flat `test/` directory — all 9 test files at root level, no subdirectories
- Not co-located with source (Flutter convention: tests mirror `lib/` paths under `test/`, but this project keeps them flat)
- Plan file references suggest future grouping by feature, but not yet adopted

**Naming:**
- `<feature>_test.dart` — `widget_test.dart`, `playback_trust_test.dart`, `soundbooks_test.dart`, `four_read_open_guard_test.dart`, `four_read_top_books_test.dart`, `audiobook_details_four_read_test.dart`, `resume_listening_service_test.dart`, `settings_update_button_test.dart`, `source_error_mapper_test.dart`

**Structure:**
```
test/
├── widget_test.dart                         # App shell smoke test
├── playback_trust_test.dart                 # Audio handler + Hive + sleep timer
├── soundbooks_test.dart                     # HTML/m3u parsers + URL encoding
├── four_read_open_guard_test.dart           # URL validation/normalization
├── four_read_top_books_test.dart            # HTML parser + title/author split
├── audiobook_details_four_read_test.dart    # BLoC error-state emission
├── resume_listening_service_test.dart       # Resume state from Hive (BROKEN)
├── settings_update_button_test.dart         # Widget test with DI overrides
└── source_error_mapper_test.dart            # Error mapping (BROKEN)
```

## Test Structure

**Suite Organization:**
```dart
void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('flow_book_playback_test_');
    Hive.init(hiveDir.path);
    for (final boxName in ['playing_audiobook_details_box', 'history_of_audiobook_box', 'bookmarks_box', 'listening_stats_box']) {
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
    test('round trips current audiobook, chapters, index, and position', () async { ... });
  });

  group('position history', () { ... });
  group('bookmarks', () { ... });
  group('sleep timer', () { ... });
  group('chapter switching metadata', () { ... });
  group('MyAudioHandler with fake playback engine', () { ... });
}
```
(`test/playback_trust_test.dart:17-46`)

**Patterns:**
- **Setup:** `setUpAll` for expensive one-time Hive init; `setUp` for per-test box clearing. Use `setUp` (not `setUpAll`) when each test needs a fresh Hive dir — see `test/widget_test.dart:18-37` and `test/settings_update_button_test.dart:15-21`.
- **Teardown:** `tearDownAll` (or `tearDown`) closes Hive and deletes the temp dir: `await Hive.close(); await hiveDir.delete(recursive: true);`
- **Assertion:** `expect(actual, matcher)` — straight from `flutter_test`. Group related assertions in one `test()` block.
- **Grouping:** `group('FeatureName', () { ... })` — one group per class or behavioral area. Subgroups allowed.

## Hive Test Setup (Required Pattern)

Every test that touches Hive MUST initialize it in a temp directory — Hive is a singleton and cannot use `Hive.initFlutter` in unit tests.

**Full box list to open (mirror `lib/main.dart:75-89`):**
```dart
const allBoxes = [
  'favourite_audiobooks_box',
  'download_status_box',
  'playing_audiobook_details_box',
  'theme_mode_box',
  'history_of_audiobook_box',
  'recommened_audiobooks_box',
  'dual_mode_box',
  'language_prefs_box',
  'bookmarks_box',
  'listening_stats_box',
  'four_read_auth',
  'settings',
];
```

**Minimal variant (only boxes the test touches):**
```dart
setUpAll(() async {
  hiveDir = await Directory.systemTemp.createTemp('flow_book_resume_test_');
  Hive.init(hiveDir.path);
  for (final boxName in ['playing_audiobook_details_box', 'history_of_audiobook_box']) {
    await Hive.openBox(boxName);
  }
});
```
(`test/resume_listening_service_test.dart:13-22`)

**Temp dir prefix:** `flow_book_<feature>_test_` — keeps temp dirs identifiable in `$TMPDIR`.

## Mocking

**Framework:** none. No `mockito`, no `mocktail`, no `build_runner`-generated mocks. Project uses **hand-rolled fakes**.

**Patterns:**

*Fake implementing interface:*
```dart
class FakePlaybackEngine implements PlaybackEngine {
  final playbackEvents = StreamController<PlaybackEvent>.broadcast();
  final playerStates = StreamController<PlayerState>.broadcast();
  // ... one StreamController per stream getter ...

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
  // ... all getters as plain mutable fields ...

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
    if (index != null) { currentIndex = index; currentIndexes.add(index); }
    positions.add(position);
  }

  // ... all abstract methods implemented as call-recording stubs ...
}

class SetAudioSourcesCall {
  const SetAudioSourcesCall({required this.sources, required this.initialIndex, required this.initialPosition, required this.preload});
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
```
(`test/playback_trust_test.dart:350-520`)

*Inject fake via constructor:*
```dart
final fake = FakePlaybackEngine();
final handler = MyAudioHandler(player: fake, configureAudioSession: false);
await handler.restoreIfNeeded();
expect(fake.setAudioSourcesCalls, hasLength(1));
expect(fake.setAudioSourcesCalls.single.initialIndex, 1);
expect(fake.playCount, 0); // restore must NOT auto-play
```
(`test/playback_trust_test.dart:211-242`)

*Function-injection fake (no class needed):*
```dart
await tester.pumpWidget(
  ChangeNotifierProvider(
    create: (_) => ThemeNotifier(),
    child: MaterialApp(
      home: Settings(
        loadAppVersion: () async => '1.1.17',
        fetchLatestVersion: () async {
          checks += 1;
          return Right(LatestVersionFetchModel(latestVersion: '1.1.17'));
        },
      ),
    ),
  ),
);
```
(`test/settings_update_button_test.dart:34-49`)

**What to Mock:**
- External audio playback engine (`PlaybackEngine`) — fake records calls and emits controlled stream events
- Network-dependent version check (`LatestVersionFetcher`, `AppVersionLoader` typedefs) — pass closures returning canned `Right(...)` / `Left(...)`
- HTTP responses — instead of mocking `http.Client`, tests use captured HTML snippets as inline strings and call parser methods directly (`test/soundbooks_test.dart:81-115`)

**What NOT to Mock:**
- Hive boxes — use real Hive in a temp directory. Tests verify actual serialization round-trips (`test/playback_trust_test.dart:47-73`).
- Model `fromMap` / `toMap` — call real methods, assert field equality
- BLoC `stream` — subscribe to real `bloc.stream.listen(emittedStates.add)` and assert emitted sequence (`test/audiobook_details_four_read_test.dart:23-49`)
- `AudioHandlerProvider` / `ThemeNotifier` / `WeSlideController` etc. in widget tests — wrap in real `MultiProvider` (`test/widget_test.dart:47-58`)

## Fixtures and Factories

**Test Data:**
- Private top-level functions at bottom of test file returning model instances built via `Audiobook.fromMap({...})`:
```dart
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
    AudiobookFile.fromMap({'identifier': 'book-1', 'title': 'Opening', 'track': 1, 'length': 60.0, 'url': '/tmp/opening.mp3', 'startMs': 0, 'durationMs': null}),
    AudiobookFile.fromMap({'identifier': 'book-1', 'title': 'Middle',  'track': 2, 'length': null, 'url': '/tmp/middle.mp3',  'startMs': 60000, 'durationMs': 90000}),
    AudiobookFile.fromMap({'identifier': 'book-1', 'title': 'Finale',  'track': 3, 'length': null, 'url': '/tmp/finale.mp3',  'startMs': 150000, 'durationMs': 120000}),
  ];
}

Bookmark _bookmark({required int trackIndex, required int positionMs}) {
  return Bookmark(audiobookId: 'book-1', trackIndex: trackIndex, positionMs: positionMs, createdAt: DateTime.utc(2026, 1, 1));
}
```
(`test/playback_trust_test.dart:295-348`)

**Inline HTML snippets** for parser tests:
```dart
const html = r'''
<script>
   var player = new Playerjs({id:"player", file:"https://sound-books.net/uploads/public_files/2026-04/4381-test.m3u"});
</script>
''';
final match = RegExp(r'file:"([^"]+\.m3u)"').firstMatch(html);
expect(match, isNotNull);
expect(match!.group(1), 'https://sound-books.net/uploads/public_files/2026-04/4381-test.m3u');
```
(`test/soundbooks_test.dart:80-92`)

**Location:**
- Fixtures live in the test file itself — no shared `test/fixtures/` or `test/helpers/` directory
- No factory libraries (`test/factories/audiobook_factory.dart`) — simple `_sample*()` functions suffice

## Coverage

**Requirements:** None enforced. No `--coverage` flag in default workflow, no `lcov.info` checked in, no coverage gate in CI.

**View Coverage:**
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

**Coverage gaps visible from `flutter test` output (as of 2026-07-13):**
- `lib/resources/services/` — only `soundbooks_*` and `four_read_open_guard` have direct tests. `knigavuhe_*`, `youtube_*`, `local/*`, `download/download_manager.dart`, `bookmark_service.dart` (covered indirectly via `playback_trust_test.dart`), `listening_stats.dart`, `equalizer_service.dart`, `character_service.dart`, `update_data_backup_service.dart` — no direct tests
- `lib/resources/archive_api.dart` (2022 lines, the largest file in the project) — zero direct tests
- `lib/resources/models/audiobook.dart`, `audiobook_file.dart` — covered indirectly via Hive round-trip tests, no isolated model tests
- `lib/screens/` — only `audiobook_details/bloc/audiobook_details_bloc.dart` (one error path) and `setting/settings.dart` (one update-check test) have direct tests. Other 14 screens untested.
- `lib/widgets/` — only the app shell smoke test exercises `ScaffoldWithNavBar`; `mini_audio_player`, `audiobook_item`, `flow_loading_indicator`, etc. untested

## Test Types

**Unit Tests:**
- Pure functions: `FourReadTopBooksService.splitTitleAuthor`, `parseTopBooksFromHtml`, `FourReadOpenGuard.validateArticleUrl`, `encodeTrackUrl`, `sanitizePlayerUrl`, regex extraction from HTML strings
- Model round-trips: `Audiobook.fromMap(audiobook.toMap())` equality, `AudiobookFile.fromMap(...)`
- Service logic with fake engine: `MyAudioHandler.restoreIfNeeded`, `skipToQueueItem`, `seek` (via `FakePlaybackEngine`)

**Integration Tests:**
- Hive + service: `ResumeListeningService.getResumeState` reads from real Hive box pre-populated by the test (`test/resume_listening_service_test.dart:44-64`)
- Hive + BLoC: `AudiobookDetailsBloc` emits error state when 4Read id is invalid (`test/audiobook_details_four_read_test.dart:23-49`)
- Hive + handler + history: `MyAudioHandler.seek` writes to `playing_audiobook_details_box` AND `HistoryOfAudiobook` in one call (`test/playback_trust_test.dart:267-291`)

**Widget Tests:**
- App shell: `tester.pumpWidget(MultiProvider(... child: const MyApp()))` + `tester.pump()` + assert `find.byType(MaterialApp)`, `find.text('Flow Book')`, `find.byIcon(Icons.home)` (`test/widget_test.dart:46-67`)
- Settings update flow: `tester.pumpWidget(...)` + `tester.pumpAndSettle()` + `tester.tap(find.text('Check for updates'))` + `tester.pumpAndSettle()` + assert `find.text("You're up to date.")` (`test/settings_update_button_test.dart:30-57`)

**E2E Tests:**
- Not used. No `integration_test/` directory, no `flutter_driver` config

## Common Patterns

**Async Testing:**
```dart
test('emits source-specific error when 4read id is invalid', () async {
  final bloc = AudiobookDetailsBloc();
  final emittedStates = <AudiobookDetailsState>[];
  final sub = bloc.stream.listen(emittedStates.add);

  bloc.add(FetchAudiobookDetails('', false, false, isFourRead: true));

  await Future<void>.delayed(const Duration(milliseconds: 120));

  final errorStates = emittedStates.whereType<AudiobookDetailsError>().toList();
  expect(errorStates, isNotEmpty);
  expect(errorStates.last.message, 'This 4Read title cannot be opened right now. Please retry or choose another title.');

  await sub.cancel();
  await bloc.close();
});
```
(`test/audiobook_details_four_read_test.dart:23-49`)

**Error Testing:**
```dart
test('returns EmptyResumeState when no saved state exists', () async {
  final service = ResumeListeningService();
  final result = await service.getResumeState();
  expect(result, isA<EmptyResumeState>());
});

test('ignores corrupt playing box and falls back to history', () async {
  final box = Hive.box('playing_audiobook_details_box');
  await box.put('audiobook', 'not-a-map');  // corrupt value
  // ... pre-populate history ...
  final service = ResumeListeningService(historyOfAudiobook: history);
  final result = await service.getResumeState();
  expect(result, isA<ResumeState>());
  expect((result as ResumeState).audiobook.title, 'Test Book');
});
```
(`test/resume_listening_service_test.dart:37-42, 103-121`)

**Sleep timer / time-based testing** (uses `tester.pump` to advance clock):
```dart
testWidgets('counts down, formats remaining time, and expires once', (tester) async {
  final timer = OptimizedTimer();
  var expiredCount = 0;
  timer.start(duration: const Duration(seconds: 3), onExpired: () => expiredCount += 1);

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
```
(`test/playback_trust_test.dart:132-153`)

**Equality / value-object testing:**
```dart
test('identical errors are equal', () {
  const a = SourceError(source: SourceProvider.fourRead, stage: SourceStage.details, type: SourceErrorType.notFound, title: 'Not found', message: 'gone');
  const b = SourceError(source: SourceProvider.fourRead, stage: SourceStage.details, type: SourceErrorType.notFound, title: 'Not found', message: 'gone');
  expect(a, equals(b));
});
```
(`test/source_error_mapper_test.dart:132-144`)

**Parser test using inline HTML + RegExp:**
```dart
test('parses cards and normalizes relative urls', () {
  const html = '''
<div class="linek d-flex ai-center has-overlay card">
  <div class="linek__img img-fit-cover">
    <img src="/uploads/posts/2026-02/medium/cover1.jpg" alt="cover-1">
  </div>
  <div class="linek__desc flex-grow-1">
    <a href="https://4read.org/7237-den-simmons-teror.html">
      <div class="linek__title ws-nowrap">Терор - Ден Сіммонс</div>
    </a>
  </div>
</div>
''';
  final service = FourReadTopBooksService();
  final books = service.parseTopBooksFromHtml(html);
  expect(books.length, 1);
  expect(books[0].title, 'Терор');
  expect(books[0].id, 'https://4read.org/7237-den-simmons-teror.html');
});
```
(`test/four_read_top_books_test.dart:36-75`)

## Test Coverage Gaps (Current Failures)

**4 tests currently fail when running `flutter test`** — they reference symbols that do not exist in `lib/`:

**`test/source_error_mapper_test.dart` (entire file fails to load):**
- Missing: `lib/resources/models/source_error.dart` (defines `SourceError`, `SourceErrorType`, `SourceProvider`, `SourceStage`)
- Missing: `lib/resources/services/source_error_mapper.dart` (defines `mapToSourceError()`)
- Both imports at `test/source_error_mapper_test.dart:3-4` resolve to non-existent files
- **Fix approach:** create the two missing files. The test file fully specifies the expected API: `SourceError` const constructor with `source`, `stage`, `type`, `title`, `message`; `mapToSourceError(Exception, {source, stage})` returning `SourceError` with `canRetry`, `canSearchAlternatives`, `sourceUrl` getters; enums `SourceProvider { fourRead, knigavuhe, youtube, librivox }`, `SourceStage { details, search, stream, playback }`, `SourceErrorType { loginRequired, notFound, parseFailure, unknown, blocked, streamUnavailable, timeout }`. Tests assert mapping rules (403→loginRequired, 404→notFound, Cloudflare→blocked, VideoUnavailable→notFound, TimeoutException→timeout, FormatException→parseFailure).

**`test/resume_listening_service_test.dart` (entire file fails to load):**
- Missing: `lib/resources/services/resume_listening_service.dart` (defines `ResumeListeningService`, `ResumeState`, `EmptyResumeState`)
- Import at `test/resume_listening_service_test.dart:6` resolves to a non-existent file
- **Fix approach:** create `lib/resources/services/resume_listening_service.dart`. Tests specify the API: `ResumeListeningService({HistoryOfAudiobook? historyOfAudiobook})` constructor with optional history injection; `Future<ResumeState> getResumeState()` returning `EmptyResumeState` when no saved state, `ResumeState` when `playing_audiobook_details_box` has `audiobook`/`audiobookFiles`/`index`/`position` keys; falls back to `HistoryOfAudiobook` when playing box empty or corrupt; clamps out-of-range `index` to `files.length - 1`; `ResumeState` exposes `audiobook`, `index`, `position`, `currentChapterTitle`, `source`.

**`test/playback_trust_test.dart` (2 tests fail):**
- Failing: `'derives display durations from explicit duration, length, and start offsets'` and `'falls back to next chapter start when no explicit duration exists'`
- Root cause: `AudiobookFile.fromMap` converts `length: null` to `0.0` via `_parseDoubleSafely` (`lib/resources/models/audiobook_file.dart:130-141, 776`). The test's `_sampleFiles()` sets `'length': null` on files 1 and 2 expecting `effectiveTrackLength` to skip the length branch and use `durationMs` instead — but `length` is never null after `fromMap`, it's `0.0`, so `effectiveTrackLength` returns `Duration(seconds: 0)` instead of the `durationMs`-derived duration.
- Files: `lib/resources/models/audiobook_file.dart:130-141` (`_parseDoubleSafely`), `lib/screens/audiobook_player/widgets/track_section_dialog.dart:7-21` (`effectiveTrackLength`)
- **Fix approach:** either (a) make `AudiobookFile.length` nullable and have `_parseDoubleSafely` return `null` for `null` input — but this ripples through every `length`-consuming call site; or (b) change `effectiveTrackLength` to treat `length == 0.0` as "no length, fall through to `durationMs` / `startMs`"; or (c) update the test's `_sampleFiles()` to omit the `length` key entirely (so `fromMap` produces `0.0`) and change `effectiveTrackLength` to skip `length <= 0`. Option (b) or (c) is least invasive.

---

*Testing analysis: 2026-07-13*
