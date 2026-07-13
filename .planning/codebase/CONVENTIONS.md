# Coding Conventions

**Analysis Date:** 2026-07-13

## Project Context

Flutter app (package `audiobookflow`, product name "Flow Book"). Dart SDK `^3.5.4`, Flutter `3.44.1`. Targets Android and macOS. Five audio sources (Librivox/Archive.org, YouTube, 4Read, Knigavuhe, Sound-Books) plus local/downloaded files.

## Naming Patterns

**Files:**
- `snake_case.dart` — Dart convention, enforced by analyzer
- Feature-grouped prefixes for related files: `four_read_*` (`lib/resources/services/four_read/four_read_search_service.dart`, `four_read_open_guard.dart`, `four_read_open_telemetry.dart`, `four_read_storage.dart`), `knigavuhe_*`, `soundbooks_*`
- BLoC triad: `<feature>_bloc.dart`, `<feature>_event.dart`, `<feature>_state.dart` in `bloc/` subdirectory (`lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart`)
- Screen entry: `<screen_name>.dart` (`lib/screens/setting/settings.dart`); screen-local widgets in `widgets/` subdirectory
- Utility classes: `<name>_helper.dart`, `<name>_notifier.dart`, `<name>_service.dart` by role

**Classes:**
- `PascalCase` — `AudiobookDetailsBloc`, `MyAudioHandler`, `FourReadOpenGuard`, `ArchiveApi`
- BLoC classes: `<Feature>Bloc extends Bloc<Event, State>`
- Notifier classes: `<Feature>Notifier extends ChangeNotifier`
- Service classes: `<Source>Service` / `<Source>DetailService` / `<Source>SearchService` / `<Source>ListService` / `<Source>Http`
- Result DTOs: `<Source>DetailResult` (e.g. `KnigavuheDetailResult`, `SoundBooksDetailResult`)
- Private state classes: `_<Widget>State` (Flutter convention)

**Functions:**
- `lowerCamelCase` — `fetchAudiobookDetails`, `getAudiobookFiles`, `validateArticleUrl`
- Private: leading `_` — `_parsePage`, `_fetchAudiobooks`, `_ensureAudioSession`
- Async: return `Future<T>` or `Future<Either<String, T>>`; never `void` for awaitable work (use `Future<void>`)
- Handlers in BLoC: match event verb — `on<FavouriteIconButtonClicked>(favouriteIconButtonClicked)`

**Variables:**
- `lowerCamelCase` — `audiobookFiles`, `currentAudiobookId`, `isReinitializing`
- Private: leading `_` — `_player`, `_activeAudiobookId`, `_isReinitializing`
- Constants: top-level `lowerCamelCase` (`const _fields`, `const _langAliases`); static const class fields `lowerCamelCase` (`static const int _librivoxRows = 10`, `static const String youtubeDirName = 'youtube'`)
- ValueNotifiers: `<name>Notifier` field, exposed via `ValueListenable<T> get name` (`lib/utils/optimized_timer.dart`)

**Types:**
- `PascalCase` for classes, enums, typedefs
- Enums: `AppTheme { light, dark, blue }`, `SearchSourceSelection { all, librivox, youtube, archiveOrg, fourRead, knigavuhe, soundBooks }`, `SourceProvider`, `SourceStage`, `SourceErrorType`, `FourReadOpenFailureType { validation, runtime }`
- Typedefs for injectable functions: `typedef AppVersionLoader = Future<String> Function();` (`lib/screens/setting/settings.dart:13`)
- Sealed class hierarchies for BLoC events/states (Dart 3 `sealed`)

## Code Style

**Formatting:**
- Tool: `flutter_lints` (via `analysis_options.yaml` `include: package:flutter_lints/flutter.yaml`)
- No custom lint rules enabled; commented-out `prefer_single_quotes` and `avoid_print` overrides present but inactive
- `analyzer.exclude: scratch/**` — scratch experiments bypass analysis
- No `.formatter_options` / `line_length` override — uses dartfmt default (80 cols)
- Run formatter: `dart format .` (or `flutter format`)

**Linting:**
- `flutter_lints` recommended set only — no `very_good_analysis` / `lints` package
- Suppression: `// ignore: lint_name` for one-line (`lib/resources/archive_api.dart:1709`), `// ignore_for_file: experimental_member_use` for file-level (`lib/resources/services/youtube/youtube_audio_service.dart:1`)
- No `// ignore_for_file: ...` widespread — only 1 file-level suppression in lib

**Quotes:** project does not enforce single vs double — both appear. JSON keys use double (`"identifier"`), Dart strings mix freely. Recommend matching surrounding file.

## Import Organization

**Order (observed in `lib/main.dart`, `lib/screens/audiobook_details/audiobook_details.dart`):**
1. `dart:` — `dart:async`, `dart:convert`, `dart:io`
2. `package:audiobookflow/...` — project imports (alphabetical by path)
3. `package:<third_party>/...` — Flutter, bloc, hive, http, fpdart, etc.
4. Relative `../../` — only used in `lib/screens/audiobook_details/audiobook_details.dart:24` (`import '../../resources/models/history_of_audiobook.dart';`). Prefer `package:audiobookflow/...` absolute imports.

**Path Aliases:**
- None. Always use full `package:audiobookflow/...` paths.

**Barrel Files:**
- Not used. Every file imports its dependencies directly.

**Restrictive imports:** `import 'package:fpdart/fpdart.dart' show Either;` (`lib/screens/setting/settings.dart:11`) — narrow fpdart to only `Either` when that's all that's needed.

## Error Handling

**Strategy:** Two-tier — `Either<String, T>` for service boundaries, try/catch + state emission for UI.

**Service layer (`lib/resources/services/`, `lib/resources/archive_api.dart`):**
- Return `Future<Either<String, T>>` from all network/parse operations
- `Left` carries a user-displayable error string; `Right` carries the success payload
- Wrap entire body in `try { ... } catch (e) { return Left('Failed to <verb>: $e'); }`
- Blocked-detector pattern: `if (<Source>Http.isBlocked(response)) return const Left(<Source>BlockedException.message);`
- Custom exceptions (`KnigavuheBlockedException`, `SoundBooksBlockedException`) declare `static const message` and override `toString()` — used as `Left` payloads, not thrown

**Pattern — service returning Either:**
```dart
Future<Either<String, KnigavuheDetailResult>> getAudiobookFiles(String bookUrl) async {
  try {
    final client = http.Client();
    try {
      final response = await client.get(Uri.parse(bookUrl), headers: KnigavuheHttp.headers);
      if (KnigavuheHttp.isBlocked(response)) return const Left(KnigavuheBlockedException.message);
      if (response.statusCode != 200) return Left('Failed to load knigavuhe page: ${response.statusCode}');
      return _parsePage(response.body);
    } finally {
      client.close();
    }
  } catch (e) {
    return Left('Failed to load knigavuhe audiobook: $e');
  }
}
```
(`lib/resources/services/knigavuhe/knigavuhe_detail_service.dart:16`)

**BLoC layer (`lib/screens/*/bloc/`):**
- `.fold((l) => emit(<Feature>Error(l)), (r) => emit(<Feature>Loaded(r)))` on the Either
- Wrap fold in `try/catch` — on unexpected throw, `emit(<Feature>Error('Failed to <verb>: $e'))`
- Source-specific UX messages: 4Read path emits `'This 4Read title cannot be opened right now. Please retry or choose another title.'` instead of raw exception text (`lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart:91-109`)
- Emit telemetry for source-specific failures: `FourReadOpenTelemetry.runtimeFailure(stage: 'details_fetch', error: e, audiobookId: id)` before emitting error state

**UI layer (`lib/screens/`):**
- `try { await handler.initSongs(...); } catch (e) { AppLogger.debug('...: $e'); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to start playback. Please try again.'))); }` (`lib/screens/audiobook_details/audiobook_details.dart:67-91`)
- Always guard `context` use after `await` with `if (!mounted) return;`
- Never let an exception bubble into a red screen — always catch and show SnackBar

**Validation guards (`lib/resources/services/four_read/four_read_open_guard.dart`):**
- Static `validateArticleUrl(String) → FourReadOpenValidationFailure?` returns null on success, failure object on error
- `FourReadOpenGuardResult` with `factory .success(audiobook)` / `factory .failure(failure)` and `bool get isValid` — no exceptions for control flow

**Do NOT:**
- Throw exceptions across service boundaries — return `Left`
- Use raw `catch (e) { /* swallow */ }` — always log via `AppLogger.debug` or rethrow as `Left`
- Show raw `e.toString()` to end users except for non-source-specific generic errors

## Logging

**Framework:** `AppLogger` static class at `lib/utils/app_logger.dart`. Wraps `print` (guarded by `kDebugMode`) and appends to a rotated log file on Android external storage.

**API:**
```dart
AppLogger.debug(String message, [String? tag]);
AppLogger.info(String message, [String? tag]);
AppLogger.warning(String message, [String? tag]);
AppLogger.error(String message, [String? tag]);
AppLogger.log(String message, [String? tag]);
```

**Tag convention:** pass source/owner name as second arg — `AppLogger.debug('Search URL: $url', 'ArchiveApi')`. Default tag is `'Flow Book'`. Telemetry classes use their own tag: `FourReadOpenTelemetry` uses `'_tag = 'FourReadOpen''` (`lib/resources/services/four_read/four_read_open_telemetry.dart:4`).

**Structured telemetry:** for feature-level events, emit key=value pairs:
```dart
AppLogger.warning('event=four_read_open_failure source=4read failure_type=validation stage=$stage reason=$reason audiobook_id=${_safe(audiobookId)}', _tag);
```
(`lib/resources/services/four_read/four_read_open_telemetry.dart:13-22`)

**Rules:**
- Never call `print()` directly outside `lib/utils/app_logger.dart` — the only 9 `print()` calls in `lib/` are inside AppLogger itself, all guarded by `kDebugMode`
- Log every caught exception: `AppLogger.debug('Error <verb>: $e');` before recovering
- Log every network request URL: `AppLogger.debug('Search URL: $url', 'ArchiveApi');` (`lib/resources/archive_api.dart:1942`)
- Initialize once in `main()`: `await AppLogger.initialize();` (`lib/main.dart:40`)
- File rotation: log file capped at 1 MB, rotated to last 1000 lines (`lib/utils/app_logger.dart:46-69`)

## Comments

**When to Comment:**
- `///` doc comments on public APIs, factories, and non-obvious static methods
- `//` inline for "why" — race conditions, Hive write ordering, browser quirks, encoding edge cases
- Section banners for long files: `// ===== French =====`, `// ─── Simple HTTP cache with ETag/Last-Modified ───`

**JSDoc/TSDoc equivalent — Dartdoc:**
```dart
/// Searches YouTube for audiobooks using [youtube_explode_dart] — no API key required.
///
/// Runs parallel searches (videos + playlists) for each selected language
/// and merges results so that:
/// - Single-file audiobooks (e.g. a 7-hour Carrie video) are found via video search.
/// - Multi-chapter series (e.g. "Воно # 01…67") appear as one playlist card.
class YoutubeSearchService { ... }
```
(`lib/resources/services/youtube/youtube_search_service.dart:7-13`)

**Do:**
- Document side effects, ordering constraints, and external service quirks
- Reference issue/root-cause context: `// Write all Hive values synchronously before any await to avoid a race where MiniAudioPlayer.didChangeDependencies reads a partially-updated box` (`lib/screens/audiobook_details/audiobook_details.dart:69-71`)

**Don't:**
- Restate what the code already says
- Leave TODO/FIXME — there are currently 0 TODO/FIXME/HACK/XXX comments in `lib/`

## Function Design

**Size:** varies — BLoC handlers run 50-150 lines (orchestration), service methods 30-80 lines, helpers <20 lines. No hard limit enforced.

**Parameters:**
- Named required for new APIs: `Future<void> setAudioSources(List<AudioSource> sources, {required int initialIndex, required Duration initialPosition, required bool preload})` (`lib/resources/services/my_audio_handler.dart:61`)
- Named optional with defaults for backwards-compat flags: `this.isYoutubeSearch = false, this.isFourRead = false` (`lib/screens/audiobook_details/bloc/audiobook_details_event.dart:18-24`)
- Positional required for simple data: `Audiobook.fromJson(Map jsonAudiobook)`, `Bookmark(this.audiobookId, this.trackIndex, this.positionMs)`

**Return Values:**
- `Either<String, T>` for fallible service calls
- `T?` for "might be absent" accessors (`String? get error`, `Duration? get duration`)
- `List<T>` for collections — never `List<T>?` unless the list itself is optional (most methods return `const []` on empty)
- `Future<void>` for async side-effects (Hive writes, downloads)

## Module Design

**Exports:**
- One primary class per file; secondary helpers exported alongside (e.g. `KnigavuheDetailResult` + `KnigavuheDetailService` in `knigavuhe_detail_service.dart`, `encodeTrackUrl` + `sanitizePlayerUrl` + `SoundBooksDetailService` in `soundbooks_detail_service.dart`)
- `part` files for BLoC event/state — `part 'audiobook_details_event.dart';` in the bloc file, `part of 'audiobook_details_bloc.dart';` in event/state files
- No `export` directives aggregating modules

**Singletons:**
- Private constructor + factory:
```dart
class FourReadAudiobookNotifier extends ChangeNotifier {
  static final FourReadAudiobookNotifier _instance = FourReadAudiobookNotifier._internal();
  factory FourReadAudiobookNotifier() => _instance;
  FourReadAudiobookNotifier._internal();
}
```
(`lib/resources/services/four_read/four_read_audiobook_notifier.dart:12-18`, also `DownloadManager`, `MyAudioHandler` via `AudioService.init`)

**Static utility classes:**
- Private constructor `ClassName._()` + all static members
- `AppConstants._()` (`lib/utils/app_constants.dart:5`), `StringHelper._()` (`lib/utils/string_helper.dart:5`), `KnigavuheHttp`, `SoundBooksHttp`, `FourReadOpenTelemetry`, `AppEvents`, `AppLogger`

**Global mutable state (module-level):**
- `int isRecommendScreen = 0;` in `lib/main.dart:73` — set by `initHive()`, read by `_buildRouter()`. Recommend replacing with Hive box read at router build time.
- `bool _startupRestoreDone = false;` static in `_MiniAudioPlayerState` (`lib/widgets/mini_audio_player.dart:42`) — one-shot app-start restore guard
- Memoization caches: `String? _memoLangClause`, `Map<String, String> _genreSubjectMemo`, `Map<String, _CacheEntry> _cache` in `lib/resources/archive_api.dart` — invalidated on Hive `language_prefs_box` watch events

**Barrel Files:**
- Not used. Import each module by full path.

## State Management Conventions

**BLoC (`flutter_bloc`):**
- One BLoC per screen with cross-cutting state — `AudiobookDetailsBloc`, `SearchBloc`, `KnigavuheListsBloc`, `SoundBooksListsBloc`, `GenreAudiobooksBloc`, `FourReadTopBloc`
- Events and states: `sealed class` + `@immutable` + `final class` subclasses
- Register handlers in constructor: `on<FetchAudiobookDetails>((event, emit) => fetchAudiobookDetails(event, emit, ...))`
- Always override `close()` to cancel `StreamSubscription`s:
```dart
@override
Future<void> close() {
  _favouriteBoxSubscription?.cancel();
  return super.close();
}
```
(`lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart:267-271`)
- Provided globally via `BlocProvider(create: (context) => <Feature>Bloc())` in `lib/main.dart:242-249` or per-screen via `BlocProvider` in the screen widget

**Provider (`provider` package, `ChangeNotifier`):**
- Global singletons provided in `lib/main.dart:50-58` `MultiProvider`:
  - `AudioHandlerProvider`, `WeSlideController`, `ThemeNotifier`, `YoutubeAudiobookNotifier`, `FourReadAudiobookNotifier`, `WebViewKeepAliveProvider`
- Read via `Provider.of<T>(context, listen: false)` for one-shot, `Consumer<T>` / `context.watch<T>()` for reactive
- Notifier pattern: private field + getter + `notifyListeners()` on change:
```dart
List<Audiobook> _audiobooks = [];
List<Audiobook> get audiobooks => _audiobooks;
// ... mutate _audiobooks ...
notifyListeners();
```

**Hive as persistence:**
- 12 boxes opened in `initHive()` in `lib/main.dart:75-95`
- Box names: `snake_case_box` (`favourite_audiobooks_box`, `download_status_box`, `playing_audiobook_details_box`, `theme_mode_box`, `history_of_audiobook_box`, `recommened_audiobooks_box`, `dual_mode_box`, `language_prefs_box`, `bookmarks_box`, `listening_stats_box`, `four_read_auth`, `settings`)
- Access: `Hive.box('name')` — no repository abstraction. Models serialize via `toMap()` / `fromMap()`.
- Reactive: `box.watch().listen((event) { ... })` for cross-widget sync (`lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart:43-47`)

**Cross-widget event bus:**
- `AppEvents` static `StreamController.broadcast()` for app-wide signals (`lib/utils/app_events.dart`):
  - `AppEvents.languagesChanged.stream` — fire when language prefs change
  - `AppEvents.searchSourcesChanged.stream` — fire when enabled search sources change
- Listeners in BLoCs: `SearchBloc` subscribes in constructor, cancels in `close()` (`lib/screens/search/bloc/search_bloc.dart:42-50,447`)

## HTTP & External Service Conventions

**Client:** `package:http` (`http.Client()` per request, closed in `finally`). `ArchiveApi` reuses a static `http.Client _client` for TCP keep-alive (`lib/resources/archive_api.dart:1764`).

**Headers per source:** static `headers` map on `<Source>Http` class — browser User-Agent, Accept, Accept-Language, Cache-Control, Referer:
- `KnigavuheHttp.headers` — `Accept-Language: ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7`, `Referer: https://knigavuhe.org/` (`lib/resources/services/knigavuhe/knigavuhe_http.dart:17-27`)
- `SoundBooksHttp.headers` — `Accept-Language: uk-UA,uk;q=0.9,...`, `Referer: https://sound-books.net/` (`lib/resources/services/soundbooks/soundbooks_http.dart:17-27`)

**Blocked-detection:** `<Source>Http.isBlocked(http.Response)` checks DDoS-Guard server header and body markers — return `true` → service returns `Left(<Source>BlockedException.message)`.

**URL encoding:** custom `encodeTrackUrl(String raw) → String` walks UTF-8 bytes, preserves existing `%XX` sequences (no double-encoding), encodes space as `%20`, encodes non-ASCII as uppercase `%XX` (`lib/resources/services/soundbooks/soundbooks_detail_service.dart:53-90`). Use `sanitizePlayerUrl(String) → String` wrapper for player URLs (`lib/resources/services/my_audio_handler.dart:34-38`).

**HTTP caching:** `ArchiveApi._getJson` implements ETag/Last-Modified conditional requests with a tiny in-memory LRU (`lib/resources/archive_api.dart:1780-1822`). `_maxStale = 15 minutes`, `_maxEntries = 100`.

## Dependency Injection for Testability

**Typedef + default static method pattern** (`lib/screens/setting/settings.dart:13-34`):
```dart
typedef AppVersionLoader = Future<String> Function();
typedef LatestVersionFetcher = Future<Either<String, LatestVersionFetchModel>> Function();

class Settings extends StatefulWidget {
  const Settings({
    super.key,
    this.loadAppVersion = _loadBundledAppVersion,
    this.fetchLatestVersion = _fetchLatestVersion,
  });
  final AppVersionLoader loadAppVersion;
  final LatestVersionFetcher fetchLatestVersion;

  static Future<String> _loadBundledAppVersion() async { ... }
  static Future<Either<String, LatestVersionFetchModel>> _fetchLatestVersion() { ... }
}
```
Tests pass overrides: `Settings(loadAppVersion: () async => '1.1.17', fetchLatestVersion: () async => Right(LatestVersionFetchModel(latestVersion: '1.1.17')))`.

**Interface + fake pattern** (`lib/resources/services/my_audio_handler.dart:40-77`):
```dart
abstract class PlaybackEngine { /* all player methods as abstract getters/methods */ }
class JustAudioPlaybackEngine implements PlaybackEngine { /* wraps real AudioPlayer */ }
class MyAudioHandler extends BaseAudioHandler {
  MyAudioHandler({PlaybackEngine? player, bool configureAudioSession = true})
      : _configureAudioSession = configureAudioSession {
    _player = player ?? JustAudioPlaybackEngine(AudioPlayer(...));
  }
}
```
Tests inject `FakePlaybackEngine implements PlaybackEngine` (see `test/playback_trust_test.dart:350-499`).

## Model Conventions

**Plain Dart classes** — no `freezed`, no codegen, no `json_serializable` for core models (`Audiobook`, `AudiobookFile`, `Bookmark`, `HistoryOfAudiobookItem`).

**Named constructors** for each input shape:
- `Audiobook.fromJson(Map jsonAudiobook)` — Archive.org API shape (`lib/resources/models/audiobook.dart:33`)
- `Audiobook.fromMap(Map<dynamic, dynamic> map)` — Hive persistence shape (`lib/resources/models/audiobook.dart:97`)
- `Audiobook.empty()` — default/blank instance (`lib/resources/models/audiobook.dart:17`)
- `AudiobookFile.fromJson`, `fromYoutubeJson`, `fromLocalJson`, `fromMap` — per source

**Serialization:**
- `Map<dynamic, dynamic> toMap()` for Hive
- `Map<String, dynamic> toJson()` for JSON
- `static List<T> fromJsonArray(List json)` for batch parsing
- Round-trip: `fromMap(toMap())` must produce equal instance

**`copyWith`:**
- `Audiobook.copyWith({String? title, ...})` — rebuilds via `Audiobook.fromMap({...})` to reuse parsing logic (`lib/resources/models/audiobook.dart:134-166`)
- `AudiobookFile.copyWithLength(double length)` — narrow-purpose copy (`lib/resources/models/audiobook_file.dart:66`)

**Parsing helpers:** static `_parseTrack`, `_parseIntSafely`, `_parseDoubleSafely` — never throw, return `0` / `0.0` on parse failure and log via `AppLogger.debug` (`lib/resources/models/audiobook_file.dart:105-141`).

---

*Convention analysis: 2026-07-13*
