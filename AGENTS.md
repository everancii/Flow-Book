<!-- GSD:project-start source:PROJECT.md -->

## Project

**Flow Book**

Flow Book (`audiobookflow`) is a Flutter audiobook player that aggregates five audio sources (Librivox/Archive.org, YouTube, 4read, knigavuhe, Sound-Books) plus local/downloaded files into one browsing + playback experience. Targets Android and macOS. Already shipped as v1.2.0+2020 via GitHub Releases.

**Core Value:** Tap a book from any source and it plays — discover to playback in one gesture.

### Constraints

- **Tech stack**: Flutter 3.44.1 / Dart ^3.5.4, `just_audio` (forked), `audio_service`, `flutter_bloc`, `provider`, Hive v2 — no new dependencies for this fix
- **Don't break other sources**: LibriVox/YouTube/knigavuhe/4read auto-play must keep working — any change to `initSongs` play sequence is shared code
- **Don't break `playback_trust_test.dart`**: the 520-line test suite encodes the invariants the fix must preserve
- **Minimal scope**: user explicitly chose "just fix it" — no loading-feedback UI, no cross-source hardening, no details-screen redesign
- **Forked `just_audio`** (`sagarchaulagai/just_audio.git @ a6f8db8`): `ProcessingState` / `setAudioSources` semantics are pinned to this fork; don't assume upstream behavior

<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Languages

- Dart — Flutter app logic, all code under `lib/`
- Kotlin — Android host activity & native update installer (`android/app/src/main/kotlin/`)
- Java — Android plugin registrant (`android/app/src/main/java/`)
- Gradle (Groovy DSL) — Android build scripts (`android/app/build.gradle`, `android/build.gradle`)
- Shell — device update helper (`scripts/update-android-device.sh`)

## Runtime

- Flutter `3.44.1` (pinned in `pubspec.yaml` `environment.flutter`)
- Dart SDK `^3.5.4`
- Android `minSdkVersion` = Flutter default (21 per `flutter_launcher_icons.min_sdk_android`), `targetSdk`/`compileSdk` = Flutter default
- JVM target `17` for Kotlin/Java compile (`android/app/build.gradle`)
- Pub — Flutter/Dart package manager
- Lockfile: `pubspec.lock` (present, committed)
- Gradle — Android native deps (no versioned wrapper file committed; uses Flutter plugin)

## Frameworks

- Flutter `3.44.1` — UI toolkit, app shell (`lib/main.dart`)
- `flutter_bloc` `9.1.1` + `bloc` `9.2.1` — state management for screen-scoped blocs (`lib/screens/*/bloc/`)
- `provider` `6.1.5+1` — app-level `ChangeNotifier` providers (`lib/main.dart` `MultiProvider`)
- `go_router` `17.2.3` — declarative routing with `StatefulShellRoute.indexedStack` (`lib/main.dart`)
- `fpdart` `1.2.0` — `Either<L,R>` for fallible service calls (used across `lib/resources/services/`)
- `flutter_test` (SDK) — widget & unit tests
- No 3rd-party test framework or mocking lib detected
- `build_runner` `2.4.13` — code generation runner (Hive adapters)
- `hive_generator` `2.0.1` — `.g.dart` Hive type adapters
- `flutter_launcher_icons` `0.14.4` — app icon generation
- `flutter_lints` `6.0.0` — lint ruleset (`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`)

## Key Dependencies

- `just_audio` `0.10.5` — **forked** from `https://github.com/sagarchaulagai/just_audio.git` (ref `a6f8db8`), audio playback engine
- `audio_service` `0.18.18` — background playback + media notification + `MediaBrowserService` integration (`lib/resources/services/my_audio_handler.dart`)
- `just_audio_background` `0.0.1-beta.17` — ties `just_audio` to `audio_service` media items
- `audio_session` `0.2.3` — audio focus management
- `rxdart` `0.28.0` — `BehaviorSubject`/stream combinators for playback state in `my_audio_handler.dart`
- `audio_video_progress_bar` `2.0.3` — seek bar widget
- `youtube_explode_dart` `2.4.1` — **forked** from `https://github.com/sheikhhaziq/youtube_explode_dart.git` (ref `0dc5514`), YouTube stream extraction without API key
- `flutter_media_metadata` `1.0.0` — **forked** from `https://github.com/sagarchaulagai/flutter_media_metadata.git` (ref `7666c7b`), local file metadata parsing
- `saf` `1.0.3+4` — **forked** from `https://github.com/sagarchaulagai/saf.git` (ref `d0ecbf9`), Android Storage Access Framework
- `hive` `2.2.3` + `hive_flutter` `1.1.0` — local NoSQL key-value store, 12 boxes opened in `lib/main.dart` `initHive()`
- `background_downloader` `9.5.5` — resilient file downloads (`lib/resources/services/download/download_manager.dart`)
- `media_store_plus` `0.1.3` — Android MediaStore access for downloads
- `path_provider` `2.1.5` — app/external storage dirs
- `http` `1.6.0` — all REST/HTML fetching (no Dio)
- `cached_network_image` `3.4.1` — cover image loading/caching
- `google_fonts` `8.1.0` — font loading
- `flutter_inappwebview` `6.1.5` — YouTube & 4read WebView login (`lib/screens/youtube_webview/`, `lib/screens/four_read_login/`)
- `permission_handler` `12.0.2` — runtime permissions (`lib/utils/permission_helper.dart`)
- `connectivity_plus` `7.1.1` — online/offline detection
- `device_info_plus` `13.1.0` — ABI detection for APK update selection (`lib/resources/latest_version_fetch.dart`)
- `flutter_background` `1.3.1` — background execution
- `url_launcher` `6.3.1`, `open_file` `3.5.11`, `file_picker` `12.0.0-beta.5`, `image_picker` `1.2.2`, `back_button_interceptor` `8.0.4`, `visibility_detector` `0.4.0+2`, `we_slide` `2.4.0`, `transparent_image` `2.0.1`, `intl` `0.20.2`, `meta` `1.18.0`, `path` `1.9.1`
- `logger` `2.7.0` — wrapped by `lib/utils/app_logger.dart` (file logging to external storage `log/applogs.txt`)

## Configuration

- No `.env` / env-var system. App is config-free — no account, no API keys in env.
- All "config" is user preference persisted in Hive boxes (`settings`, `language_prefs_box`, `theme_mode_box`, `dual_mode_box`).
- Bundled asset `assets/language_subjects.txt` — multi-language subject index parsed at runtime by `_LanguageSubjectIndex` in `lib/resources/archive_api.dart`.
- Bundled asset `assets/version.json` — legacy version string (currently `1.1.18`, superseded by `pubspec.yaml` `version: 1.2.0+2020`).
- `pubspec.yaml` — Dart deps + 3 git-fork overrides (`just_audio`, `flutter_media_metadata`, `saf`, `youtube_explode_dart`)
- `analysis_options.yaml` — `flutter_lints/flutter.yaml` ruleset, excludes `scratch/**`
- `devtools_options.yaml` — DevTools extension config (stub)
- `android/app/build.gradle` — `applicationId com.everancii.audiobookflow`, release signing via `key.properties` (not committed), `minifyEnabled true` + `shrinkResources true` + ProGuard
- `android/app/src/main/AndroidManifest.xml` — `usesCleartextTraffic="true"` (required for unencrypted CDN streams from 4read/knigavuhe), permissions: INTERNET, network state, foreground media service, POST_NOTIFICATIONS, media access, MODIFY_AUDIO_SETTINGS, REQUEST_INSTALL_PACKAGES
- `flutter_launcher_icons` block in `pubspec.yaml` — Android-only icons, `ios: false`

## Platform Requirements

- Flutter SDK `3.44.1`, Dart `^3.5.4`
- JDK 17 (Gradle `kotlinOptions.jvmTarget = "17"`)
- Android SDK with `compileSdk` = Flutter default
- Build: `flutter pub get && flutter build apk --release --split-per-abi`
- Android primary target. App ID `com.everancii.audiobookflow`.
- macOS desktop scaffolding present (`macos/`) but not configured as a shipped target.
- iOS explicitly disabled (`flutter_launcher_icons.ios: false`).
- Distribution: GitHub Releases on `everancii/Flow-Book` — in-app updater fetches `https://api.github.com/repos/everancii/Flow-Book/releases/latest` and installs APK via `MethodChannel('app_update_channel')` → `installApk`.
- No CI pipeline (no `.github/workflows/`). `fastlane/` contains metadata only.
- Local device deploy script: `scripts/update-android-device.sh <ip:port>`.

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Project Context

## Naming Patterns

- `snake_case.dart` — Dart convention, enforced by analyzer
- Feature-grouped prefixes for related files: `four_read_*` (`lib/resources/services/four_read/four_read_search_service.dart`, `four_read_open_guard.dart`, `four_read_open_telemetry.dart`, `four_read_storage.dart`), `knigavuhe_*`, `soundbooks_*`
- BLoC triad: `<feature>_bloc.dart`, `<feature>_event.dart`, `<feature>_state.dart` in `bloc/` subdirectory (`lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart`)
- Screen entry: `<screen_name>.dart` (`lib/screens/setting/settings.dart`); screen-local widgets in `widgets/` subdirectory
- Utility classes: `<name>_helper.dart`, `<name>_notifier.dart`, `<name>_service.dart` by role
- `PascalCase` — `AudiobookDetailsBloc`, `MyAudioHandler`, `FourReadOpenGuard`, `ArchiveApi`
- BLoC classes: `<Feature>Bloc extends Bloc<Event, State>`
- Notifier classes: `<Feature>Notifier extends ChangeNotifier`
- Service classes: `<Source>Service` / `<Source>DetailService` / `<Source>SearchService` / `<Source>ListService` / `<Source>Http`
- Result DTOs: `<Source>DetailResult` (e.g. `KnigavuheDetailResult`, `SoundBooksDetailResult`)
- Private state classes: `_<Widget>State` (Flutter convention)
- `lowerCamelCase` — `fetchAudiobookDetails`, `getAudiobookFiles`, `validateArticleUrl`
- Private: leading `_` — `_parsePage`, `_fetchAudiobooks`, `_ensureAudioSession`
- Async: return `Future<T>` or `Future<Either<String, T>>`; never `void` for awaitable work (use `Future<void>`)
- Handlers in BLoC: match event verb — `on<FavouriteIconButtonClicked>(favouriteIconButtonClicked)`
- `lowerCamelCase` — `audiobookFiles`, `currentAudiobookId`, `isReinitializing`
- Private: leading `_` — `_player`, `_activeAudiobookId`, `_isReinitializing`
- Constants: top-level `lowerCamelCase` (`const _fields`, `const _langAliases`); static const class fields `lowerCamelCase` (`static const int _librivoxRows = 10`, `static const String youtubeDirName = 'youtube'`)
- ValueNotifiers: `<name>Notifier` field, exposed via `ValueListenable<T> get name` (`lib/utils/optimized_timer.dart`)
- `PascalCase` for classes, enums, typedefs
- Enums: `AppTheme { light, dark, blue }`, `SearchSourceSelection { all, librivox, youtube, archiveOrg, fourRead, knigavuhe, soundBooks }`, `SourceProvider`, `SourceStage`, `SourceErrorType`, `FourReadOpenFailureType { validation, runtime }`
- Typedefs for injectable functions: `typedef AppVersionLoader = Future<String> Function();` (`lib/screens/setting/settings.dart:13`)
- Sealed class hierarchies for BLoC events/states (Dart 3 `sealed`)

## Code Style

- Tool: `flutter_lints` (via `analysis_options.yaml` `include: package:flutter_lints/flutter.yaml`)
- No custom lint rules enabled; commented-out `prefer_single_quotes` and `avoid_print` overrides present but inactive
- `analyzer.exclude: scratch/**` — scratch experiments bypass analysis
- No `.formatter_options` / `line_length` override — uses dartfmt default (80 cols)
- Run formatter: `dart format .` (or `flutter format`)
- `flutter_lints` recommended set only — no `very_good_analysis` / `lints` package
- Suppression: `// ignore: lint_name` for one-line (`lib/resources/archive_api.dart:1709`), `// ignore_for_file: experimental_member_use` for file-level (`lib/resources/services/youtube/youtube_audio_service.dart:1`)
- No `// ignore_for_file: ...` widespread — only 1 file-level suppression in lib

## Import Organization

- None. Always use full `package:audiobookflow/...` paths.
- Not used. Every file imports its dependencies directly.

## Error Handling

- Return `Future<Either<String, T>>` from all network/parse operations
- `Left` carries a user-displayable error string; `Right` carries the success payload
- Wrap entire body in `try { ... } catch (e) { return Left('Failed to <verb>: $e'); }`
- Blocked-detector pattern: `if (<Source>Http.isBlocked(response)) return const Left(<Source>BlockedException.message);`
- Custom exceptions (`KnigavuheBlockedException`, `SoundBooksBlockedException`) declare `static const message` and override `toString()` — used as `Left` payloads, not thrown
- `.fold((l) => emit(<Feature>Error(l)), (r) => emit(<Feature>Loaded(r)))` on the Either
- Wrap fold in `try/catch` — on unexpected throw, `emit(<Feature>Error('Failed to <verb>: $e'))`
- Source-specific UX messages: 4Read path emits `'This 4Read title cannot be opened right now. Please retry or choose another title.'` instead of raw exception text (`lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart:91-109`)
- Emit telemetry for source-specific failures: `FourReadOpenTelemetry.runtimeFailure(stage: 'details_fetch', error: e, audiobookId: id)` before emitting error state
- `try { await handler.initSongs(...); } catch (e) { AppLogger.debug('...: $e'); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to start playback. Please try again.'))); }` (`lib/screens/audiobook_details/audiobook_details.dart:67-91`)
- Always guard `context` use after `await` with `if (!mounted) return;`
- Never let an exception bubble into a red screen — always catch and show SnackBar
- Static `validateArticleUrl(String) → FourReadOpenValidationFailure?` returns null on success, failure object on error
- `FourReadOpenGuardResult` with `factory .success(audiobook)` / `factory .failure(failure)` and `bool get isValid` — no exceptions for control flow
- Throw exceptions across service boundaries — return `Left`
- Use raw `catch (e) { /* swallow */ }` — always log via `AppLogger.debug` or rethrow as `Left`
- Show raw `e.toString()` to end users except for non-source-specific generic errors

## Logging

- Never call `print()` directly outside `lib/utils/app_logger.dart` — the only 9 `print()` calls in `lib/` are inside AppLogger itself, all guarded by `kDebugMode`
- Log every caught exception: `AppLogger.debug('Error <verb>: $e');` before recovering
- Log every network request URL: `AppLogger.debug('Search URL: $url', 'ArchiveApi');` (`lib/resources/archive_api.dart:1942`)
- Initialize once in `main()`: `await AppLogger.initialize();` (`lib/main.dart:40`)
- File rotation: log file capped at 1 MB, rotated to last 1000 lines (`lib/utils/app_logger.dart:46-69`)

## Comments

- `///` doc comments on public APIs, factories, and non-obvious static methods
- `//` inline for "why" — race conditions, Hive write ordering, browser quirks, encoding edge cases
- Section banners for long files: `// ===== French =====`, `// ─── Simple HTTP cache with ETag/Last-Modified ───`
- Document side effects, ordering constraints, and external service quirks
- Reference issue/root-cause context: `// Write all Hive values synchronously before any await to avoid a race where MiniAudioPlayer.didChangeDependencies reads a partially-updated box` (`lib/screens/audiobook_details/audiobook_details.dart:69-71`)
- Restate what the code already says
- Leave TODO/FIXME — there are currently 0 TODO/FIXME/HACK/XXX comments in `lib/`

## Function Design

- Named required for new APIs: `Future<void> setAudioSources(List<AudioSource> sources, {required int initialIndex, required Duration initialPosition, required bool preload})` (`lib/resources/services/my_audio_handler.dart:61`)
- Named optional with defaults for backwards-compat flags: `this.isYoutubeSearch = false, this.isFourRead = false` (`lib/screens/audiobook_details/bloc/audiobook_details_event.dart:18-24`)
- Positional required for simple data: `Audiobook.fromJson(Map jsonAudiobook)`, `Bookmark(this.audiobookId, this.trackIndex, this.positionMs)`
- `Either<String, T>` for fallible service calls
- `T?` for "might be absent" accessors (`String? get error`, `Duration? get duration`)
- `List<T>` for collections — never `List<T>?` unless the list itself is optional (most methods return `const []` on empty)
- `Future<void>` for async side-effects (Hive writes, downloads)

## Module Design

- One primary class per file; secondary helpers exported alongside (e.g. `KnigavuheDetailResult` + `KnigavuheDetailService` in `knigavuhe_detail_service.dart`, `encodeTrackUrl` + `sanitizePlayerUrl` + `SoundBooksDetailService` in `soundbooks_detail_service.dart`)
- `part` files for BLoC event/state — `part 'audiobook_details_event.dart';` in the bloc file, `part of 'audiobook_details_bloc.dart';` in event/state files
- No `export` directives aggregating modules
- Private constructor + factory:
- Private constructor `ClassName._()` + all static members
- `AppConstants._()` (`lib/utils/app_constants.dart:5`), `StringHelper._()` (`lib/utils/string_helper.dart:5`), `KnigavuheHttp`, `SoundBooksHttp`, `FourReadOpenTelemetry`, `AppEvents`, `AppLogger`
- `int isRecommendScreen = 0;` in `lib/main.dart:73` — set by `initHive()`, read by `_buildRouter()`. Recommend replacing with Hive box read at router build time.
- `bool _startupRestoreDone = false;` static in `_MiniAudioPlayerState` (`lib/widgets/mini_audio_player.dart:42`) — one-shot app-start restore guard
- Memoization caches: `String? _memoLangClause`, `Map<String, String> _genreSubjectMemo`, `Map<String, _CacheEntry> _cache` in `lib/resources/archive_api.dart` — invalidated on Hive `language_prefs_box` watch events
- Not used. Import each module by full path.

## State Management Conventions

- One BLoC per screen with cross-cutting state — `AudiobookDetailsBloc`, `SearchBloc`, `KnigavuheListsBloc`, `SoundBooksListsBloc`, `GenreAudiobooksBloc`, `FourReadTopBloc`
- Events and states: `sealed class` + `@immutable` + `final class` subclasses
- Register handlers in constructor: `on<FetchAudiobookDetails>((event, emit) => fetchAudiobookDetails(event, emit, ...))`
- Always override `close()` to cancel `StreamSubscription`s:
- Provided globally via `BlocProvider(create: (context) => <Feature>Bloc())` in `lib/main.dart:242-249` or per-screen via `BlocProvider` in the screen widget
- Global singletons provided in `lib/main.dart:50-58` `MultiProvider`:
- Read via `Provider.of<T>(context, listen: false)` for one-shot, `Consumer<T>` / `context.watch<T>()` for reactive
- Notifier pattern: private field + getter + `notifyListeners()` on change:
- 12 boxes opened in `initHive()` in `lib/main.dart:75-95`
- Box names: `snake_case_box` (`favourite_audiobooks_box`, `download_status_box`, `playing_audiobook_details_box`, `theme_mode_box`, `history_of_audiobook_box`, `recommened_audiobooks_box`, `dual_mode_box`, `language_prefs_box`, `bookmarks_box`, `listening_stats_box`, `four_read_auth`, `settings`)
- Access: `Hive.box('name')` — no repository abstraction. Models serialize via `toMap()` / `fromMap()`.
- Reactive: `box.watch().listen((event) { ... })` for cross-widget sync (`lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart:43-47`)
- `AppEvents` static `StreamController.broadcast()` for app-wide signals (`lib/utils/app_events.dart`):
- Listeners in BLoCs: `SearchBloc` subscribes in constructor, cancels in `close()` (`lib/screens/search/bloc/search_bloc.dart:42-50,447`)

## HTTP & External Service Conventions

- `KnigavuheHttp.headers` — `Accept-Language: ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7`, `Referer: https://knigavuhe.org/` (`lib/resources/services/knigavuhe/knigavuhe_http.dart:17-27`)
- `SoundBooksHttp.headers` — `Accept-Language: uk-UA,uk;q=0.9,...`, `Referer: https://sound-books.net/` (`lib/resources/services/soundbooks/soundbooks_http.dart:17-27`)

## Dependency Injection for Testability

## Model Conventions

- `Audiobook.fromJson(Map jsonAudiobook)` — Archive.org API shape (`lib/resources/models/audiobook.dart:33`)
- `Audiobook.fromMap(Map<dynamic, dynamic> map)` — Hive persistence shape (`lib/resources/models/audiobook.dart:97`)
- `Audiobook.empty()` — default/blank instance (`lib/resources/models/audiobook.dart:17`)
- `AudiobookFile.fromJson`, `fromYoutubeJson`, `fromLocalJson`, `fromMap` — per source
- `Map<dynamic, dynamic> toMap()` for Hive
- `Map<String, dynamic> toJson()` for JSON
- `static List<T> fromJsonArray(List json)` for batch parsing
- Round-trip: `fromMap(toMap())` must produce equal instance
- `Audiobook.copyWith({String? title, ...})` — rebuilds via `Audiobook.fromMap({...})` to reuse parsing logic (`lib/resources/models/audiobook.dart:134-166`)
- `AudiobookFile.copyWithLength(double length)` — narrow-purpose copy (`lib/resources/models/audiobook_file.dart:66`)

<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## System Overview

```text

```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `MyApp` / GoRouter | App bootstrap, routing, global provider tree | `lib/main.dart` |
| `AudioHandlerProvider` | Wraps `MyAudioHandler`, initializes `AudioService` post-frame | `lib/resources/services/audio_handler_provider.dart` |
| `MyAudioHandler` | Core playback engine: queue, persistence, notification state, equalizer, sleep timer, position tracking | `lib/resources/services/my_audio_handler.dart` |
| `PlaybackEngine` (abstract) | Testable seam over `just_audio`'s `AudioPlayer` | `lib/resources/services/my_audio_handler.dart` |
| `DownloadManager` | Background download of audiobook files (singleton) | `lib/resources/services/download/download_manager.dart` |
| `ArchiveApi` | Librivox/Archive.org search + file listing with HTTP ETag cache | `lib/resources/archive_api.dart` |
| `YoutubeAudiobookNotifier` | Singleton ChangeNotifier for imported YouTube audiobooks | `lib/resources/services/youtube/youtube_audiobook_notifier.dart` |
| `YouTubeAudioSource` | `StreamAudioSource` that streams YouTube audio with local MP3 cache | `lib/resources/services/youtube/youtube_audio_service.dart` |
| `FourReadAudiobookNotifier` | Singleton ChangeNotifier for imported 4read audiobooks | `lib/resources/services/four_read/four_read_audiobook_notifier.dart` |
| `FourReadOpenGuard` | Validates/normalizes 4read article URLs before opening | `lib/resources/services/four_read/four_read_open_guard.dart` |
| `FourReadOpenTelemetry` | Structured telemetry for 4read open attempts/failures | `lib/resources/services/four_read/four_read_open_telemetry.dart` |
| `KnigavuheHttp` / `SoundBooksHttp` | Shared headers + DDoS-Guard detection per scrape source | `lib/resources/services/{knigavuhe,soundbooks}/*_http.dart` |
| `SearchBloc` | Multi-source search fan-out (Librivox/YT/4read/knigavuhe/sound-books) | `lib/screens/search/bloc/search_bloc.dart` |
| `AudiobookDetailsBloc` | Fetches files for one audiobook across all 6 origins | `lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart` |
| `ScaffoldWithNavBar` | Shell route: 3-tab bottom nav + mini player + loading overlay | `lib/widgets/scaffold_with_nav_bar.dart` |
| `MiniAudioPlayer` | Now-playing bar; slides up to full `AudiobookPlayer` via `WeSlide` | `lib/widgets/mini_audio_player.dart` |
| `ThemeNotifier` | Persisted theme (light/dark/blue) backed by Hive | `lib/resources/designs/theme_notifier.dart` |
| `AppLogger` | File-rotating logger (1MB / 1000 lines) | `lib/utils/app_logger.dart` |
| `AppEvents` | Global broadcast streams for cross-widget signals | `lib/utils/app_events.dart` |
| `UpdateDataBackupService` | Backs up + restores protected Hive boxes across app updates | `lib/resources/services/update_data_backup_service.dart` |

## Pattern Overview

- **Bloc** (`flutter_bloc`) for screen-scoped async workflows with discrete events/states (`AudiobookDetailsBloc`, `SearchBloc`, `SoundBooksListsBloc`, `KnigavuheListsBloc`, `FourReadTopBloc`, `GenreAudiobooksBloc`). Each bloc lives in `screens/<feature>/bloc/` as three `part` files: `*_bloc.dart`, `*_event.dart`, `*_state.dart`. Events/states are `@immutable sealed class`es with `final class` concrete variants.
- **Provider** (`provider`) for app-global singletons exposed in `lib/main.dart`'s `MultiProvider`. Some are true singletons (static `_instance` + `factory`) that are ALSO handed to `ChangeNotifierProvider` — both `Provider.of<T>()` and `T()` resolve to the same instance.
- **fpdart `Either<String, T>`** for service/API error channels instead of exceptions where possible (see `ArchiveApi`, `KnigavuheDetailService`, `SoundBooksDetailService`). Blocs `.fold()` over the Either to emit `*Error` or `*Loaded` states.
- **Scrape-source parallelism**: each scraped source (knigavuhe, sound-books) mirrors the same file quartet: `*_http.dart` (headers + `isBlocked`), `*_list_service.dart`, `*_search_service.dart`, `*_detail_service.dart`. New scraped sources should copy this shape.
- **No Hive TypeAdapters**: all persistence uses raw `Map<dynamic, dynamic>` via `toMap()` / `fromMap()` constructors on models. Boxes are opened eagerly in `initHive()`.

## Layers

- Purpose: per-feature UI screens + their Bloc + local widgets.
- Location: `lib/screens/<feature>/` — screen root widget + optional `bloc/`, `widgets/`, `constants/` subfolders.
- Contains: `StatefulWidget`s that read Bloc state via `BlocBuilder` and global state via `Provider.of` / `context.select`; screen-private widget subcomponents.
- Depends on: services, models, global providers, `widgets/` shared widgets.
- Used by: GoRouter route builders in `lib/main.dart`.
- Purpose: assemble the provider tree and router once.
- Location: `lib/main.dart`.
- Contains: `main()`, `initHive()`, `MyApp` + `_MyAppState`, GoRouter definition, `BackButtonInterceptor`.
- Depends on: every provider/bloc it wires up.
- Used by: Flutter runtime (`runApp`).
- Purpose: business logic with side effects (HTTP, audio, filesystem, Hive).
- Location: `lib/resources/services/` with per-source subfolders (`download/`, `youtube/`, `four_read/`, `knigavuhe/`, `soundbooks/`, `local/`).
- Contains: notifiers, HTTP clients, parsers, download manager, audio handler.
- Depends on: models, utils, external packages (just_audio, audio_service, youtube_explode_dart, background_downloader, hive, http).
- Used by: blocs, screens, other services, `main.dart`.
- Purpose: plain data classes with `fromJson` / `fromMap` / `toMap` / `copyWith`.
- Location: `lib/resources/models/`.
- Contains: `Audiobook`, `AudiobookFile`, `HistoryOfAudiobook`, `Bookmark` (in services), `Character`, `EqualizerSettings`, `GoogleBookResult`, `LatestVersionFetchModel`, `LocalAudiobook`.
- Depends on: utils, some services (e.g. `AudiobookFile` calls `FourReadPageService`, `FourReadAuthService` — see Anti-Patterns).
- Used by: services, blocs, screens.
- Purpose: theming, colors, reusable visual primitives.
- Location: `lib/resources/designs/`.
- Contains: `Themes`, `AppColors`, `ThemeNotifier`, `LanguageNotifier`, `AppCircularProgressIndicator`.
- Depends on: Hive (theme box), Flutter material.
- Used by: `main.dart`, screens, widgets.
- Purpose: cross-cutting helpers, logging, constants, events.
- Location: `lib/utils/`.
- Contains: `AppLogger`, `AppConstants`, `AppEvents`, `MediaHelper`, `OptimizedTimer`, `PermissionHelper`, `StringHelper`, `VersionCompare`.
- Depends on: path_provider, flutter.
- Used by: every other layer.
- Purpose: cross-screen reusable widgets.
- Location: `lib/widgets/`.
- Contains: `ScaffoldWithNavBar`, `MiniAudioPlayer`, `AudiobookItem`, `FlowLoadingIndicator`, `GlobalLoadingOverlay`, `LowAndHighImage`, `RatingWidget`, `CommonTextField`, `ScaffoldWithNavBar`.
- Depends on: services (audio handler, download manager), models, design.
- Used by: screens and other widgets.

## Data Flow

### Primary Request Path — Browse to Play

### Position Persistence Flow

### Search Flow

- Global singletons: `AudioHandlerProvider`, `ThemeNotifier`, `YoutubeAudiobookNotifier`, `FourReadAudiobookNotifier`, `WeSlideController`, `WebViewKeepAliveProvider` — all in `MultiProvider` (`lib/main.dart:50`).
- Global blocs: `AudiobookDetailsBloc`, `SearchBloc` — in `MultiBlocProvider` inside `MyApp.build` (`lib/main.dart:242`).
- Screen-local blocs (`SoundBooksListsBloc`, `KnigavuheListsBloc`, `FourReadTopBloc`, `GenreAudiobooksBloc`) are created inline in their screens.
- Persistence: Hive boxes are the source of truth for now-playing state, favourites, history, bookmarks, theme, listening stats, language prefs, 4read auth, settings, download status, recommendations, dual-mode (audiobook vs podcast home).

## Key Abstractions

- Purpose: testable seam over `just_audio`'s `AudioPlayer`; exposes getters + stream getters + transport methods.
- Examples: `lib/resources/services/my_audio_handler.dart:40` (abstract), `:79` (`JustAudioPlaybackEngine` impl).
- Pattern: Strategy — `MyAudioHandler` accepts an optional `PlaybackEngine? player` in its constructor so tests can inject a fake.
- Purpose: bridge between just_audio and the Android media session / notification.
- Examples: `MyAudioHandler extends BaseAudioHandler` (`my_audio_handler.dart:191`).
- Pattern: framework-supplied base class; override `play/pause/stop/seek/skipTo*/fastForward/rewind/setSpeed`.
- Purpose: custom audio source for YouTube streaming with on-disk caching.
- Examples: `YouTubeAudioSource extends StreamAudioSource` (`lib/resources/services/youtube/youtube_audio_service.dart:20`).
- Pattern: override `request()` to return a `StreamAudioResponse` backed by `AudioStreamClient` + local MP3 file.
- Purpose: shared headers + DDoS-Guard detection for sites behind ddos-guard.
- Examples: `lib/resources/services/knigavuhe/knigavuhe_http.dart`, `lib/resources/services/soundbooks/soundbooks_http.dart`.
- Pattern: `static const headers` + `static bool isBlocked(http.Response)`; services throw a `*BlockedException` when blocked.
- Purpose: app-global observable state for imported audiobook lists.
- Examples: `YoutubeAudiobookNotifier`, `FourReadAudiobookNotifier`, `DownloadManager`.
- Pattern: `static final _instance = T._internal(); factory T() => _instance;` + registered in `MultiProvider` so `Provider.of<T>()` and `T()` return the same instance.
- Purpose: explicit error handling in services without exceptions.
- Examples: `ArchiveApi.getAudiobookFiles` returns `Either<String, List<AudiobookFile>>`; `KnigavuheDetailService().getAudiobookFiles(id)` same.
- Pattern: services return `Either<errorMessage, payload>`; blocs `.fold((l) => emit Error, (r) => emit Loaded)`.

## Entry Points

- Location: `lib/main.dart:35`.
- Triggers: app launch (Flutter runtime).
- Responsibilities: `WidgetsFlutterBinding.ensureInitialized()`, `initHive()` (opens boxes, restore-backup, clean stale downloads), `AppLogger.initialize()`, construct global providers, `runApp(MultiProvider)`, `audioHandlerProvider.initialize()` on post-frame callback, lock to portrait.
- Location: `lib/main.dart:100`.
- Triggers: `runApp`.
- Responsibilities: build GoRouter once (`_buildRouter`), register `BackButtonInterceptor` (closes WeSlide on back), wrap in `Consumer<ThemeNotifier>` + `MultiBlocProvider` + `MaterialApp.router`.
- Location: `android/app/src/main/kotlin/com/.../MainActivity.kt` (Flutter `MainActivity`), `android/app/src/main/AndroidManifest.xml`.
- Triggers: launcher.
- Responsibilities: hosts the Flutter engine, declares permissions (INTERNET, FOREGROUND_SERVICE_MEDIA_PLAYBACK, POST_NOTIFICATIONS, READ_MEDIA_AUDIO, MODIFY_AUDIO_SETTINGS, REQUEST_INSTALL_PACKAGES), `usesCleartextTraffic="true"` for unencrypted CDN streams.
- Location: `macos/Runner/` (Xcode project), `macos/Podfile`.
- Triggers: app bundle launch.
- Responsibilities: hosts Flutter engine via CocoaPods (`just_audio`, `audio_service`, etc.).

## Architectural Constraints

- **Threading:** single-threaded Dart isolate on the UI thread; all audio/download work is async via platform channels and `background_downloader` (separate native worker). No Dart isolates used.
- **Global state:** `int isRecommendScreen = 0` top-level mutable global in `lib/main.dart:73`, mutated inside `initHive()` and read by `_buildRouter()` to pick `initialLocation`. Several Hive boxes are opened at field-initialization time inside service classes (e.g. `MyAudioHandler.playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box')`) — relies on `initHive()` having completed first.
- **Persistence coupling:** services and widgets reach for `Hive.box('<name>')` directly throughout (no repository abstraction). Box names are string literals duplicated across the codebase.
- **Platform gating:** equalizer + loudness enhancer are Android-only (`Platform.isAndroid` checks in `my_audio_handler.dart`); iOS/macOS silently no-op those calls.
- **Circular-ish dependency:** `lib/resources/models/audiobook_file.dart` imports `four_read_storage.dart`, `four_read_page_service.dart`, `four_read_auth_service.dart` to implement `fromFourReadFiles` / `fromFourReadPageUrl` / `fromYoutubeFiles` static constructors — the model layer depends on the service layer (see Anti-Patterns).
- **Webview keep-alive:** `WebViewKeepAliveProvider` holds a long-lived `FlutterInAppWebView` instance so YouTube/4read webviews survive navigation.

## Anti-Patterns

### Model layer imports service layer

### Top-level mutable global controls routing

### Direct Hive.box() access scattered across layers

### Singleton + Provider dual registration

## Error Handling

- Services return `Either<String, T>`; blocs `.fold((l) => emit Error(l), (r) => emit Loaded(r))`. See `audiobook_details_bloc.dart:129`, `:147`.
- Scrape HTTP: `if (KnigavuheHttp.isBlocked(response)) throw const KnigavuheBlockedException();` — caught and rethrown as `Exception(e.toString())` by the list service.
- 4read has explicit guard + telemetry: `FourReadOpenGuard.validateArticleUrl` → `FourReadOpenTelemetry.validationFailure` / `runtimeFailure` for structured failure reporting (`audiobook_details_bloc.dart:84`).
- Player init: `_isReinitializing` flag + generation counter (`_initGen`) to cancel in-flight `initSongs` if a newer one supersedes it (`my_audio_handler.dart:424`, `:526`).
- Buffering recovery: if stuck in `ProcessingState.buffering` > 30s, auto-skip to next track (`my_audio_handler.dart:590`).
- Many hot-path catches are `catch (_) {}` — silent. Acceptable for best-effort persistence, risky for masking real bugs.

## Cross-Cutting Concerns

<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

| Skill | Description | Path |
|-------|-------------|------|
| openspec-apply-change | Implement tasks from an OpenSpec change. Use when the user wants to start implementing, continue implementation, or work through tasks. | `.claude/skills/openspec-apply-change/SKILL.md` |
| openspec-archive-change | Archive a completed change in the experimental workflow. Use when the user wants to finalize and archive a change after implementation is complete. | `.claude/skills/openspec-archive-change/SKILL.md` |
| openspec-explore | Enter explore mode - a thinking partner for exploring ideas, investigating problems, and clarifying requirements. Use when the user wants to think through something before or during a change. | `.claude/skills/openspec-explore/SKILL.md` |
| openspec-propose | Propose a new change with all artifacts generated in one step. Use when the user wants to quickly describe what they want to build and get a complete proposal with design, specs, and tasks ready for implementation. | `.claude/skills/openspec-propose/SKILL.md` |
| caveman | > Ultra-compressed communication mode. Cuts output tokens 65% (measured) by speaking like caveman while keeping full technical accuracy. Supports intensity levels: lite, full (default), ultra, wenyan-lite, wenyan-full, wenyan-ultra. Use when user says "caveman mode", "talk like caveman", "use caveman", "less tokens", "be brief", or invokes /caveman. Also auto-triggers when token efficiency is requested. | `.agents/skills/caveman/SKILL.md` |
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
