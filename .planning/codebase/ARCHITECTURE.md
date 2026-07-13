<!-- refreshed: 2026-07-13 -->
# Architecture

**Analysis Date:** 2026-07-13

## System Overview

Flow Book (package `audiobookflow`) is a Flutter audiobook player that aggregates five audio sources (Librivox/Archive.org, YouTube, 4read, knigavuhe, Sound-Books) plus local/downloaded files into one browsing + playback experience. The app targets Android and macOS.

```text
┌──────────────────────────────────────────────────────────────────────────┐
│                            Presentation Layer                             │
│  `lib/screens/*` (StatefulWidgets + BlocBuilder + Provider.of)            │
├──────────────────────┬──────────────────────┬────────────────────────────┤
│  Screen widgets      │  Per-screen BLoCs    │  Screen-local widgets      │
│  `screens/home/...`  │  `screens/*/bloc/`   │  `screens/*/widgets/`      │
│  `screens/search/...`│  Event/State/Bloc    │  controls, dialogs, etc.   │
│  `screens/...player` │  (flutter_bloc)      │                            │
└──────────┬───────────┴──────────┬───────────┴─────────────┬──────────────┘
           │                      │                         │
           ▼                      ▼                         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       Global State / DI Layer                             │
│  `lib/main.dart` MultiProvider + MultiBlocProvider                        │
│  AudioHandlerProvider · ThemeNotifier · YoutubeAudiobookNotifier ·        │
│  FourReadAudiobookNotifier · WeSlideController · WebViewKeepAliveProvider │
│  + BlocProvider<AudiobookDetailsBloc> · BlocProvider<SearchBloc>          │
└──────────┬───────────────────────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                         Service Layer                                     │
│  `lib/resources/services/*`                                               │
│  ┌──────────────┐ ┌──────────────┐ ┌────────────┐ ┌────────────────────┐ │
│  │ my_audio_    │ │ download/    │ │ youtube/    │ │ four_read/         │ │
│  │ handler.dart │ │ download_    │ │ youtube_    │ │ four_read_*        │ │
│  │ (playback)   │ │ manager.dart │ │ audio_      │ │ (scrape + guard)   │ │
│  └──────────────┘ └──────────────┘ │ service.dart│ └────────────────────┘ │
│  ┌──────────────┐ ┌──────────────┐ └────────────┘ ┌────────────────────┐ │
│  │ knigavuhe/   │ │ soundbooks/  │ │ local/       │ │ bookmark_service   │ │
│  │ knigavuhe_*  │ │ soundbooks_* │ │ chapter_     │ │ equalizer_service  │ │
│  │ (scrape)     │ │ (scrape)     │ │ parser.dart  │ │ character_service  │ │
│  └──────────────┘ └──────────────┘ └──────────────┘ └────────────────────┘ │
└──────────┬───────────────────────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Data / Persistence / External                                            │
│  Hive boxes (12+) · just_audio · audio_service · youtube_explode_dart ·   │
│  Archive.org HTTP · knigavuhe/sound-books/4read HTML scrape ·             │
│  background_downloader · local filesystem (downloads/)                    │
└──────────────────────────────────────────────────────────────────────────┘
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

**Overall:** Feature-first (per-screen) structure with a hybrid Bloc + Provider state-management split.

**Key Characteristics:**
- **Bloc** (`flutter_bloc`) for screen-scoped async workflows with discrete events/states (`AudiobookDetailsBloc`, `SearchBloc`, `SoundBooksListsBloc`, `KnigavuheListsBloc`, `FourReadTopBloc`, `GenreAudiobooksBloc`). Each bloc lives in `screens/<feature>/bloc/` as three `part` files: `*_bloc.dart`, `*_event.dart`, `*_state.dart`. Events/states are `@immutable sealed class`es with `final class` concrete variants.
- **Provider** (`provider`) for app-global singletons exposed in `lib/main.dart`'s `MultiProvider`. Some are true singletons (static `_instance` + `factory`) that are ALSO handed to `ChangeNotifierProvider` — both `Provider.of<T>()` and `T()` resolve to the same instance.
- **fpdart `Either<String, T>`** for service/API error channels instead of exceptions where possible (see `ArchiveApi`, `KnigavuheDetailService`, `SoundBooksDetailService`). Blocs `.fold()` over the Either to emit `*Error` or `*Loaded` states.
- **Scrape-source parallelism**: each scraped source (knigavuhe, sound-books) mirrors the same file quartet: `*_http.dart` (headers + `isBlocked`), `*_list_service.dart`, `*_search_service.dart`, `*_detail_service.dart`. New scraped sources should copy this shape.
- **No Hive TypeAdapters**: all persistence uses raw `Map<dynamic, dynamic>` via `toMap()` / `fromMap()` constructors on models. Boxes are opened eagerly in `initHive()`.

## Layers

**Presentation (`lib/screens/*`):**
- Purpose: per-feature UI screens + their Bloc + local widgets.
- Location: `lib/screens/<feature>/` — screen root widget + optional `bloc/`, `widgets/`, `constants/` subfolders.
- Contains: `StatefulWidget`s that read Bloc state via `BlocBuilder` and global state via `Provider.of` / `context.select`; screen-private widget subcomponents.
- Depends on: services, models, global providers, `widgets/` shared widgets.
- Used by: GoRouter route builders in `lib/main.dart`.

**Global State / DI (`lib/main.dart`):**
- Purpose: assemble the provider tree and router once.
- Location: `lib/main.dart`.
- Contains: `main()`, `initHive()`, `MyApp` + `_MyAppState`, GoRouter definition, `BackButtonInterceptor`.
- Depends on: every provider/bloc it wires up.
- Used by: Flutter runtime (`runApp`).

**Services (`lib/resources/services/*`):**
- Purpose: business logic with side effects (HTTP, audio, filesystem, Hive).
- Location: `lib/resources/services/` with per-source subfolders (`download/`, `youtube/`, `four_read/`, `knigavuhe/`, `soundbooks/`, `local/`).
- Contains: notifiers, HTTP clients, parsers, download manager, audio handler.
- Depends on: models, utils, external packages (just_audio, audio_service, youtube_explode_dart, background_downloader, hive, http).
- Used by: blocs, screens, other services, `main.dart`.

**Models (`lib/resources/models/*`):**
- Purpose: plain data classes with `fromJson` / `fromMap` / `toMap` / `copyWith`.
- Location: `lib/resources/models/`.
- Contains: `Audiobook`, `AudiobookFile`, `HistoryOfAudiobook`, `Bookmark` (in services), `Character`, `EqualizerSettings`, `GoogleBookResult`, `LatestVersionFetchModel`, `LocalAudiobook`.
- Depends on: utils, some services (e.g. `AudiobookFile` calls `FourReadPageService`, `FourReadAuthService` — see Anti-Patterns).
- Used by: services, blocs, screens.

**Resources / Design (`lib/resources/designs/*`):**
- Purpose: theming, colors, reusable visual primitives.
- Location: `lib/resources/designs/`.
- Contains: `Themes`, `AppColors`, `ThemeNotifier`, `LanguageNotifier`, `AppCircularProgressIndicator`.
- Depends on: Hive (theme box), Flutter material.
- Used by: `main.dart`, screens, widgets.

**Utils (`lib/utils/*`):**
- Purpose: cross-cutting helpers, logging, constants, events.
- Location: `lib/utils/`.
- Contains: `AppLogger`, `AppConstants`, `AppEvents`, `MediaHelper`, `OptimizedTimer`, `PermissionHelper`, `StringHelper`, `VersionCompare`.
- Depends on: path_provider, flutter.
- Used by: every other layer.

**Shared Widgets (`lib/widgets/*`):**
- Purpose: cross-screen reusable widgets.
- Location: `lib/widgets/`.
- Contains: `ScaffoldWithNavBar`, `MiniAudioPlayer`, `AudiobookItem`, `FlowLoadingIndicator`, `GlobalLoadingOverlay`, `LowAndHighImage`, `RatingWidget`, `CommonTextField`, `ScaffoldWithNavBar`.
- Depends on: services (audio handler, download manager), models, design.
- Used by: screens and other widgets.

## Data Flow

### Primary Request Path — Browse to Play

1. App starts → `main()` calls `initHive()` (opens 12 Hive boxes, restores update backup, cleans stale downloads) then `runApp(MultiProvider(...))` (`lib/main.dart:35`).
2. GoRouter builds `StatefulShellRoute.indexedStack` → `ScaffoldWithNavBar` with 3 branches: Home / Search / Downloads (`lib/main.dart:122`).
3. User opens an audiobook → `context.go('/audiobook-details', extra: {audiobook, is* flags})` (`lib/main.dart:148`).
4. `AudiobookDetails` creates/reads `AudiobookDetailsBloc` and dispatches `FetchAudiobookDetails` (`lib/screens/audiobook_details/audiobook_details.dart`).
5. Bloc branches on the `is*` origin flags and calls the matching source: `ArchiveApi().getAudiobookFiles(id)`, `AudiobookFile.fromYoutubeFiles(id)`, `AudiobookFile.fromFourReadPageUrl(id)`, `KnigavuheDetailService().getAudiobookFiles(id)`, `SoundBooksDetailService().getAudiobookFiles(id)`, etc. (`lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart:50`).
6. Service returns `Either<String, List<AudiobookFile>>`; bloc `.fold()`s to emit `AudiobookDetailsError` or `AudiobookDetailsLoaded` (`audiobook_details_bloc.dart:169`).
7. UI renders the track list; user taps a chapter → `_playChapter` writes the `playing_audiobook_details_box` Hive values **synchronously before any await** (avoids mini-player race), then calls `audioHandlerProvider.audioHandler.initSongs(files, audiobook, index, 0)` (`lib/screens/audiobook_details/audiobook_details.dart:67`).
8. `MyAudioHandler.initSongs` builds `List<AudioSource>` (YouTube → `YouTubeAudioSource`, clipped/local → `ClippingAudioSource`/`AudioSource.uri`), persists audiobook+files+index+position to Hive, calls `_player.setAudioSources(...)` then `_player.play()` (`lib/resources/services/my_audio_handler.dart:416`).
9. `_broadcastState` maps just_audio `ProcessingState` → `AudioProcessingState` and pushes `playbackState` so the system notification + `MiniAudioPlayer` StreamBuilder update (`my_audio_handler.dart:718`).
10. `MiniAudioPlayer` (inside `ScaffoldWithNavBar`) watches `playingAudiobookDetailsBox` via `StreamBuilder<BoxEvent>` and `handler.playbackState` via `StreamBuilder<PlaybackState>`; tapping it slides up to full `AudiobookPlayer` (`lib/widgets/scaffold_with_nav_bar.dart`, `lib/widgets/mini_audio_player.dart`).

### Position Persistence Flow

1. `MyAudioHandler._startPositionUpdateTimer` starts a `Timer.periodic(10s)` while playing (`my_audio_handler.dart:778`).
2. Each tick → `_persistNow(audiobookId, index)` writes `historyOfAudiobook.updateAudiobookPosition` + `playingAudiobook_details_box.put('position', liveMs)`, debounced to one write per 12s (`_persistInterval`) (`my_audio_handler.dart:705`).
3. On `pause`/`stop`/`seek`/`skipTo*` → immediate `_persistInstant()` flush (`my_audio_handler.dart:887`).
4. Cold start → `_restoreQueueFromBoxIfEmpty()` rebuilds the queue from Hive without auto-playing; `play()` triggers restore if empty (`my_audio_handler.dart:841`, `:877`).

### Search Flow

1. `SearchAudiobook` dispatches `EventSearchIconClicked(query, sourceSelection)` to `SearchBloc` (`lib/screens/search/bloc/search_bloc.dart:37`).
2. Bloc fans out to `YoutubeSearchService`, `FourReadSearchService`, `KnigavuheSearchService`, `SoundBooksSearchService`, and `ArchiveApi` based on `SearchSourceSelection` enum (`search_bloc.dart:30`).
3. `AppEvents.languagesChanged` stream re-triggers the current query when language prefs change (`search_bloc.dart:42`).

**State Management:**
- Global singletons: `AudioHandlerProvider`, `ThemeNotifier`, `YoutubeAudiobookNotifier`, `FourReadAudiobookNotifier`, `WeSlideController`, `WebViewKeepAliveProvider` — all in `MultiProvider` (`lib/main.dart:50`).
- Global blocs: `AudiobookDetailsBloc`, `SearchBloc` — in `MultiBlocProvider` inside `MyApp.build` (`lib/main.dart:242`).
- Screen-local blocs (`SoundBooksListsBloc`, `KnigavuheListsBloc`, `FourReadTopBloc`, `GenreAudiobooksBloc`) are created inline in their screens.
- Persistence: Hive boxes are the source of truth for now-playing state, favourites, history, bookmarks, theme, listening stats, language prefs, 4read auth, settings, download status, recommendations, dual-mode (audiobook vs podcast home).

## Key Abstractions

**PlaybackEngine (abstract class):**
- Purpose: testable seam over `just_audio`'s `AudioPlayer`; exposes getters + stream getters + transport methods.
- Examples: `lib/resources/services/my_audio_handler.dart:40` (abstract), `:79` (`JustAudioPlaybackEngine` impl).
- Pattern: Strategy — `MyAudioHandler` accepts an optional `PlaybackEngine? player` in its constructor so tests can inject a fake.

**BaseAudioHandler (audio_service):**
- Purpose: bridge between just_audio and the Android media session / notification.
- Examples: `MyAudioHandler extends BaseAudioHandler` (`my_audio_handler.dart:191`).
- Pattern: framework-supplied base class; override `play/pause/stop/seek/skipTo*/fastForward/rewind/setSpeed`.

**StreamAudioSource (just_audio):**
- Purpose: custom audio source for YouTube streaming with on-disk caching.
- Examples: `YouTubeAudioSource extends StreamAudioSource` (`lib/resources/services/youtube/youtube_audio_service.dart:20`).
- Pattern: override `request()` to return a `StreamAudioResponse` backed by `AudioStreamClient` + local MP3 file.

**Scrape-source Http base:**
- Purpose: shared headers + DDoS-Guard detection for sites behind ddos-guard.
- Examples: `lib/resources/services/knigavuhe/knigavuhe_http.dart`, `lib/resources/services/soundbooks/soundbooks_http.dart`.
- Pattern: `static const headers` + `static bool isBlocked(http.Response)`; services throw a `*BlockedException` when blocked.

**Singleton ChangeNotifier:**
- Purpose: app-global observable state for imported audiobook lists.
- Examples: `YoutubeAudiobookNotifier`, `FourReadAudiobookNotifier`, `DownloadManager`.
- Pattern: `static final _instance = T._internal(); factory T() => _instance;` + registered in `MultiProvider` so `Provider.of<T>()` and `T()` return the same instance.

**Either error channel (fpdart):**
- Purpose: explicit error handling in services without exceptions.
- Examples: `ArchiveApi.getAudiobookFiles` returns `Either<String, List<AudiobookFile>>`; `KnigavuheDetailService().getAudiobookFiles(id)` same.
- Pattern: services return `Either<errorMessage, payload>`; blocs `.fold((l) => emit Error, (r) => emit Loaded)`.

## Entry Points

**`main()` — Dart entry:**
- Location: `lib/main.dart:35`.
- Triggers: app launch (Flutter runtime).
- Responsibilities: `WidgetsFlutterBinding.ensureInitialized()`, `initHive()` (opens boxes, restore-backup, clean stale downloads), `AppLogger.initialize()`, construct global providers, `runApp(MultiProvider)`, `audioHandlerProvider.initialize()` on post-frame callback, lock to portrait.

**`MyApp` — root widget:**
- Location: `lib/main.dart:100`.
- Triggers: `runApp`.
- Responsibilities: build GoRouter once (`_buildRouter`), register `BackButtonInterceptor` (closes WeSlide on back), wrap in `Consumer<ThemeNotifier>` + `MultiBlocProvider` + `MaterialApp.router`.

**Android entry:**
- Location: `android/app/src/main/kotlin/com/.../MainActivity.kt` (Flutter `MainActivity`), `android/app/src/main/AndroidManifest.xml`.
- Triggers: launcher.
- Responsibilities: hosts the Flutter engine, declares permissions (INTERNET, FOREGROUND_SERVICE_MEDIA_PLAYBACK, POST_NOTIFICATIONS, READ_MEDIA_AUDIO, MODIFY_AUDIO_SETTINGS, REQUEST_INSTALL_PACKAGES), `usesCleartextTraffic="true"` for unencrypted CDN streams.

**macOS entry:**
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

**What happens:** `AudiobookFile` (a model in `lib/resources/models/audiobook_file.dart`) imports `four_read_storage.dart`, `four_read_page_service.dart`, `four_read_auth_service.dart` and exposes static constructors `fromFourReadFiles`, `fromFourReadPageUrl`, `fromYoutubeFiles`, `fromLocalFiles`, `fromDownloadedFiles` that perform HTTP + filesystem + auth work.
**Why it's wrong:** inverts the dependency direction — models should be pure data; fetching belongs in services. This makes `AudiobookFile` untestable without spinning up filesystem/HTTP/auth and forces `audiobook_details_bloc.dart` to call model statics instead of services for 4 of 6 origins.
**Do this instead:** move the fetching logic into dedicated services (`FourReadFileService`, `YoutubeFileService`, `LocalFileService`, `DownloadedFileService`) that return `Either<String, List<AudiobookFile>>`, matching the existing `KnigavuheDetailService` / `SoundBooksDetailService` pattern. Keep `AudiobookFile` as data + `fromJson`/`fromMap`/`toMap`/`copyWith` only.

### Top-level mutable global controls routing

**What happens:** `int isRecommendScreen = 0;` is declared at top level in `lib/main.dart:73`, mutated to `0` inside `initHive()`, and read by `_buildRouter()` to choose `initialLocation` between `/home` and `/recommendation_screen`.
**Why it's wrong:** implicit global mutable state drives routing decisions; reading happens in `_MyAppState.initState`-time `_buildRouter()` which runs once, so later changes to the global have no effect. The global is also redundantly set to the same value it already had.
**Do this instead:** read the recommendation flag directly from the Hive `dual_mode_box` inside `_buildRouter()` (or pass it through `main()` as a local), and delete the `isRecommendScreen` global.

### Direct Hive.box() access scattered across layers

**What happens:** `Hive.box('favourite_audiobooks_box')`, `Hive.box('playing_audiobook_details_box')`, `Hive.box('language_prefs_box')`, `Hive.box('listening_stats_box')`, etc. are opened inline in blocs, widgets, services, and models (e.g. `audiobook_details_bloc.dart:42`, `scaffold_with_nav_bar.dart:26`, `my_audio_handler.dart:207`, `archive_api.dart:72`).
**Why it's wrong:** no repository abstraction; box-name strings are duplicated; every call site assumes `initHive()` already ran (it does, but only by convention); hard to swap storage or add migration logic.
**Do this instead:** introduce a thin `Boxes`/repository facade (e.g. `lib/resources/services/storage/`) that owns box references and exposes typed getters/setters per concern (FavouritesRepository, HistoryRepository, PlaybackStateRepository, etc.). Inject into blocs/services.

### Singleton + Provider dual registration

**What happens:** `YoutubeAudiobookNotifier` and `FourReadAudiobookNotifier` are singletons (`static final _instance` + `factory`) AND registered via `ChangeNotifierProvider(create: (_) => instance)` in `main.dart`. Code accesses them both ways: `Provider.of<YoutubeAudiobookNotifier>(context)` in widgets and `YoutubeAudiobookNotifier()` (static singleton) in services/blocs that have no `BuildContext`.
**Why it's wrong:** two access paths to the same instance is confusing and fragile — a future refactor that changes one path but not the other silently breaks reactivity.
**Do this instead:** pick one access strategy per notifier. Either (a) pure singleton + `ListenableBuilder`/manual `addListener`, or (b) Provider-only and pass the instance explicitly into services that need it.

## Error Handling

**Strategy:** layered — `Either<Left, Right>` (fpdart) at the service boundary, try/catch + `emit(*Error)` in blocs, `KnigavuheBlockedException` / `SoundBooksBlockedException` typed exceptions for scrape sources, silent `catch (_)` swallows in some hot paths (position persistence, cover-art refresh).

**Patterns:**
- Services return `Either<String, T>`; blocs `.fold((l) => emit Error(l), (r) => emit Loaded(r))`. See `audiobook_details_bloc.dart:129`, `:147`.
- Scrape HTTP: `if (KnigavuheHttp.isBlocked(response)) throw const KnigavuheBlockedException();` — caught and rethrown as `Exception(e.toString())` by the list service.
- 4read has explicit guard + telemetry: `FourReadOpenGuard.validateArticleUrl` → `FourReadOpenTelemetry.validationFailure` / `runtimeFailure` for structured failure reporting (`audiobook_details_bloc.dart:84`).
- Player init: `_isReinitializing` flag + generation counter (`_initGen`) to cancel in-flight `initSongs` if a newer one supersedes it (`my_audio_handler.dart:424`, `:526`).
- Buffering recovery: if stuck in `ProcessingState.buffering` > 30s, auto-skip to next track (`my_audio_handler.dart:590`).
- Many hot-path catches are `catch (_) {}` — silent. Acceptable for best-effort persistence, risky for masking real bugs.

## Cross-Cutting Concerns

**Logging:** `AppLogger` (`lib/utils/app_logger.dart`) — static methods `debug/info/warning/error/log(message, [tag])`. Writes to `applogs.txt` under external storage `log/` dir on Android, rotates at 1MB / 1000 lines, also `print`s in debug mode. Tag defaults to `'Flow Book'`. Used throughout services/blocs via `AppLogger.debug(...)`.

**Validation:** `FourReadOpenGuard` validates + normalizes 4read article URLs; `sanitizePlayerUrl` / `encodeTrackUrl` in `my_audio_handler.dart` percent-encode raw non-ASCII/spaces in playback URLs (healing old persisted Hive state). `version_compare.dart` compares semver strings for the update prompt.

**Authentication:** `FourReadAuthService` (`lib/resources/services/four_read/four_read_auth_service.dart`) persists 4read session cookies in `four_read_auth` Hive box; `FourReadWebviewLogin` screen performs webview login. No auth for Librivox/YouTube/knigavuhe/sound-books (public scrape).

**Permissions:** `PermissionHelper` (`lib/utils/permission_helper.dart`) centralizes Android storage/notification/media permissions for downloads. AndroidManifest declares `READ_MEDIA_AUDIO/IMAGES/VIDEO`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `REQUEST_INSTALL_PACKAGES` (for in-app APK self-update via `LatestVersionFetch`).

**Events bus:** `AppEvents` (`lib/utils/app_events.dart`) — two broadcast `StreamController`s: `languagesChanged`, `searchSourcesChanged`. `SearchBloc` listens to `languagesChanged` to re-run the current query. Lightweight decoupling for settings→search fan-out.

**Theming:** `ThemeNotifier` persists `light|dark|blue` to `theme_mode_box` Hive box; `Themes` (`lib/resources/designs/themes.dart`) holds the `ThemeData` instances; `AppColors` holds palette constants. `MaterialApp.router` reads via `Consumer<ThemeNotifier>`.

---

*Architecture analysis: 2026-07-13*
