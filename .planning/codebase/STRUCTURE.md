# Codebase Structure

**Analysis Date:** 2026-07-13

## Directory Layout

```
FlowBook/
├── lib/                         # Dart application code (only source shipped)
│   ├── main.dart                # App entry: Hive init, providers, GoRouter
│   ├── resources/               # Non-UI layers: models, services, design, APIs
│   │   ├── archive_api.dart     # Librivox/Archive.org HTTP client + ETag cache
│   │   ├── latest_version_fetch.dart  # In-app update check
│   │   ├── designs/             # Theme, colors, reusable visual primitives
│   │   ├── models/              # Plain data classes (Audiobook, AudiobookFile, ...)
│   │   └── services/            # Business logic with side effects
│   │       ├── audio_handler_provider.dart   # Provider wrapping MyAudioHandler
│   │       ├── my_audio_handler.dart         # Core playback (just_audio + audio_service)
│   │       ├── bookmark_service.dart         # Hive-backed bookmarks
│   │       ├── character_service.dart        # Audiobook character/reader data
│   │       ├── equalizer_service.dart        # Persisted EQ settings
│   │       ├── listening_stats.dart          # Listening time/streak stats
│   │       ├── update_data_backup_service.dart  # Hive box backup across app updates
│   │       ├── download/download_manager.dart   # background_downloader singleton
│   │       ├── youtube/                      # YouTube streaming + import
│   │       ├── four_read/                    # 4read scrape + auth + guard
│   │       ├── knigavuhe/                    # knigavuhe scrape (4-file pattern)
│   │       ├── soundbooks/                   # Sound-Books scrape (4-file pattern)
│   │       └── local/                        # Local file parsing (chapters, covers)
│   ├── screens/                 # Feature-first UI screens (+ per-screen bloc/widgets)
│   │   ├── audiobook_details/   # Audiobook detail screen + bloc + widgets
│   │   ├── audiobook_player/    # Full-screen player + widget subcomponents
│   │   ├── download_audiobook/  # Downloads page + download button widget
│   │   ├── four_read_login/     # 4read webview login flow
│   │   ├── four_read_top/       # 4read top-books screen + bloc
│   │   ├── genre_audiobooks/    # Genre-filtered list screen + bloc
│   │   ├── home/                # Home screen + widgets (+ empty bloc/ constants/)
│   │   ├── knigavuhe_lists/     # knigavuhe browse lists + bloc
│   │   ├── podcast_home/        # Podcast home (dual-mode alternate)
│   │   ├── recommendation/      # Recommendation screen
│   │   ├── search/              # Multi-source search screen + bloc
│   │   ├── setting/             # Settings + listening stats screens
│   │   ├── soundbooks_lists/    # Sound-Books browse lists + bloc
│   │   └── youtube_webview/     # YouTube import webview
│   ├── utils/                   # Cross-cutting helpers (logger, constants, events)
│   └── widgets/                 # Shared cross-screen widgets
├── android/                     # Android platform host (FlutterActivity, manifest, gradle)
├── macos/                       # macOS platform host (Xcode project, Podfile)
├── assets/                      # Bundled assets (icon.png, language_subjects.txt, version.json)
├── bin/                         # Standalone Dart CLI scripts (chapter-parser debug tools)
├── scripts/                     # Shell scripts (update-android-device.sh)
├── test/                        # Flutter test suite
├── openspec/                    # OpenSpec change/spec tracking (proposals, tasks)
├── docs/                        # Documentation (superpowers)
├── fastlane/                    # Fastlane deployment config
├── pubspec.yaml                 # Flutter/Dart deps + assets + launcher icons
├── analysis_options.yaml        # Dart analyzer/lint config (flutter_lints)
└── README.md                    # Project overview + build instructions
```

## Directory Purposes

**`lib/`:**
- Purpose: all shipped Dart application code.
- Contains: `main.dart` + `resources/`, `screens/`, `utils/`, `widgets/` subfolders.
- Key files: `lib/main.dart` (entry), `lib/resources/services/my_audio_handler.dart` (playback core, 1054 lines — largest file in app logic).

**`lib/resources/`:**
- Purpose: non-UI layers — models, services, design system, external API clients.
- Contains: `archive_api.dart`, `latest_version_fetch.dart`, `designs/`, `models/`, `services/`.
- Key files: `archive_api.dart` (Librivox API, 2022 lines), `services/my_audio_handler.dart`, `services/download/download_manager.dart` (529 lines).

**`lib/resources/services/`:**
- Purpose: business logic with side effects (HTTP, audio, filesystem, Hive).
- Contains: top-level services (`my_audio_handler.dart`, `bookmark_service.dart`, `character_service.dart`, `equalizer_service.dart`, `listening_stats.dart`, `update_data_backup_service.dart`, `audio_handler_provider.dart`) + per-source subfolders.
- Per-source subfolder convention (scraped sources): `<source>/` contains `<source>_http.dart` (headers + `isBlocked`), `<source>_list_service.dart`, `<source>_search_service.dart`, `<source>_detail_service.dart`. Knigavuhe and Sound-Books follow this exactly.
- 4read subfolder is larger: also `four_read_auth_service.dart`, `four_read_open_guard.dart`, `four_read_open_telemetry.dart`, `four_read_page_service.dart`, `four_read_storage.dart`, `four_read_top_books_service.dart`, `four_read_audiobook_notifier.dart`.
- YouTube subfolder: `youtube_audio_service.dart` (`YouTubeAudioSource`), `youtube_audiobook_notifier.dart` (singleton), `youtube_search_service.dart`, `stream_client.dart`, `webview_keep_alive_provider.dart`.
- Local subfolder: `chapter_parser.dart` (MP3 ID3v2 CHAP + MP4 Nero chpl + tx3g), `cover_image_service.dart`.

**`lib/resources/models/`:**
- Purpose: plain data classes with `fromJson`/`fromMap`/`toMap`/`copyWith`.
- Contains: `audiobook.dart`, `audiobook_file.dart` (816 lines — fetching logic mixed in), `character.dart`, `equalizer_settings.dart`, `google_book_result.dart`, `history_of_audiobook.dart`, `latest_version_fetch_model.dart`, `local_audiobook.dart`.

**`lib/resources/designs/`:**
- Purpose: theming + reusable visual primitives.
- Contains: `themes.dart` (light/dark/blue `ThemeData`), `app_colors.dart`, `theme_notifier.dart` (ChangeNotifier over `theme_mode_box`), `language_notifier.dart`, `app_circular_progress_indicator.dart`.

**`lib/screens/`:**
- Purpose: feature-first UI. Each feature folder holds the screen root widget and optional `bloc/` + `widgets/` (+ rarely `constants/`).
- Contains: 15 feature folders (see Directory Layout).
- Key files: `audiobook_details/audiobook_details.dart` (761 lines), `audiobook_player/audiobook_player.dart` (741 lines), `home/home.dart` (410 lines).

**`lib/screens/<feature>/bloc/`:**
- Purpose: flutter_bloc trio for screen-scoped async state.
- Contains: three `part`-of files: `<feature>_bloc.dart` (Bloc subclass + handlers), `<feature>_event.dart` (`sealed class` events), `<feature>_state.dart` (`sealed class` states).
- Present in: `audiobook_details`, `four_read_top`, `genre_audiobooks`, `home` (empty), `knigavuhe_lists`, `search`, `soundbooks_lists`.
- Missing (screen uses Provider/StatefulWidget only): `audiobook_player`, `download_audiobook`, `four_read_login`, `podcast_home`, `recommendation`, `setting`, `youtube_webview`.

**`lib/screens/<feature>/widgets/`:**
- Purpose: screen-private widget subcomponents (dialogs, controls, sections).
- Present in: `audiobook_details`, `audiobook_player`, `download_audiobook`, `home`.

**`lib/utils/`:**
- Purpose: cross-cutting helpers used by every layer.
- Contains: `app_constants.dart` (dir names, audio extensions), `app_events.dart` (broadcast streams), `app_logger.dart` (file-rotating logger), `media_helper.dart`, `optimized_timer.dart` (sleep timer), `permission_helper.dart`, `string_helper.dart`, `version_compare.dart`.

**`lib/widgets/`:**
- Purpose: cross-screen reusable widgets.
- Contains: `scaffold_with_nav_bar.dart` (shell route), `mini_audio_player.dart`, `audiobook_item.dart`, `flow_loading_indicator.dart`, `global_loading_overlay.dart`, `low_and_high_image.dart`, `rating_widget.dart`, `common_text_field.dart`.

**`test/`:**
- Purpose: Flutter test suite (`flutter test`).
- Contains: 9 test files — `widget_test.dart`, `audiobook_details_four_read_test.dart`, `four_read_open_guard_test.dart`, `four_read_top_books_test.dart`, `playback_trust_test.dart`, `resume_listening_service_test.dart`, `settings_update_button_test.dart`, `soundbooks_test.dart`, `source_error_mapper_test.dart`.

**`assets/`:**
- Purpose: bundled assets declared in `pubspec.yaml` `flutter.assets`.
- Contains: `icon.png` (launcher icon), `icon.ico`, `language_subjects.txt` (Librivox genre/language subject list), `version.json` (current version string), `Thumbs.db`.

**`bin/`:**
- Purpose: standalone Dart CLI scripts for debugging chapter parsing.
- Contains: `dump_atoms.dart`, `dump_chpl_payload.dart`, `test_chapters.dart`.

**`scripts/`:**
- Purpose: shell scripts for local dev.
- Contains: `update-android-device.sh` (build + install APK to a connected device).

**`openspec/`:**
- Purpose: OpenSpec change/spec tracking — proposals, designs, tasks, specs per change.
- Contains: `config.yaml`, `changes/` (active + `archive/`), `specs/` (capability specs).

**`android/`:**
- Purpose: Android platform host.
- Contains: `app/src/main/AndroidManifest.xml` (permissions, `usesCleartextTraffic=true`), `kotlin/com/.../MainActivity.kt`, gradle, res.

**`macos/`:**
- Purpose: macOS platform host.
- Contains: `Runner/` (Xcode), `Podfile`, `Pods/`, `Flutter/`.

## Key File Locations

**Entry Points:**
- `lib/main.dart`: Dart entry (`main()`), Hive init, provider tree, GoRouter.
- `android/app/src/main/kotlin/com/.../MainActivity.kt`: Android FlutterActivity.
- `macos/Runner/MainFlutterWindow.swift` (via Xcode project): macOS host.

**Configuration:**
- `pubspec.yaml`: deps, assets, launcher icons, SDK constraints (Dart ^3.5.4, Flutter 3.44.1).
- `analysis_options.yaml`: analyzer + `flutter_lints` rules; excludes `scratch/**`.
- `android/app/src/main/AndroidManifest.xml`: permissions, cleartext, FileProvider.
- `android/app/build.gradle` (via `android/app/`): min/target SDK, signing.
- `.gitignore`: ignores build artifacts, `.dart_tool/`, etc.

**Core Logic:**
- `lib/resources/services/my_audio_handler.dart`: playback engine, queue, persistence, notification.
- `lib/resources/archive_api.dart`: Librivox/Archive.org search + file fetch + HTTP ETag cache + language/genre query memoization.
- `lib/resources/services/download/download_manager.dart`: background download (singleton).
- `lib/resources/services/youtube/youtube_audio_service.dart`: `YouTubeAudioSource` streaming + local MP3 cache.
- `lib/resources/services/local/chapter_parser.dart`: MP3 ID3v2 CHAP + MP4 Nero chpl + tx3g chapter extraction (668 lines).

**State / Routing:**
- `lib/main.dart`: GoRouter with `StatefulShellRoute.indexedStack` (3 branches: Home/Search/Downloads) + detail/player/four_read_top/knigavuhe_lists/soundbooks_lists routes on the home branch.
- `lib/widgets/scaffold_with_nav_bar.dart`: shell with bottom nav + mini player + loading overlay.
- `lib/resources/services/audio_handler_provider.dart`: ChangeNotifier wrapping `MyAudioHandler`.

**Persistence (Hive boxes — opened in `initHive()`):**
- `favourite_audiobooks_box`, `download_status_box`, `playing_audiobook_details_box`, `theme_mode_box`, `history_of_audiobook_box`, `recommened_audiobooks_box`, `dual_mode_box` (0=audiobook home, 1=podcast home), `language_prefs_box`, `bookmarks_box`, `listening_stats_box`, `four_read_auth`, `settings`.

**Testing:**
- `test/`: 9 test files (see above).
- No `test/helpers/` or shared fixture directory detected.

## Naming Conventions

**Files:**
- `snake_case.dart` (Dart convention, enforced by analyzer).
- Screen root widget: `<feature>.dart` (e.g. `home.dart`, `audiobook_details.dart`, `search_audiobook.dart` — note: search uses `search_audiobook.dart`, not `search.dart`).
- Bloc trio: `<feature>_bloc.dart`, `<feature>_event.dart`, `<feature>_state.dart` (all `part of '<feature>_bloc.dart'`).
- Services: `<source>_<concern>_service.dart` (e.g. `knigavuhe_list_service.dart`, `knigavuhe_search_service.dart`, `knigavuhe_detail_service.dart`).
- HTTP base: `<source>_http.dart` (e.g. `knigavuhe_http.dart`, `soundbooks_http.dart`).
- Models: singular noun (`audiobook.dart`, `audiobook_file.dart`, `character.dart`).
- Utils: `app_<concern>.dart` (`app_logger.dart`, `app_constants.dart`, `app_events.dart`) or `<concern>_helper.dart` (`permission_helper.dart`, `string_helper.dart`, `media_helper.dart`).
- Widgets: `<descriptive>.dart` (`mini_audio_player.dart`, `flow_loading_indicator.dart`, `global_loading_overlay.dart`).

**Directories:**
- Feature folder per screen: `screens/<feature>/` with optional `bloc/`, `widgets/`, `constants/`.
- Source subfolder per scraped source: `resources/services/<source>/`.
- No `src/` or `core/` conventions — everything sits directly under `lib/`.

**Classes:**
- `PascalCase` for classes, `camelCase` for methods/variables, `SCREAMING_SNAKE_CASE` for constants.
- Bloc: `<Feature>Bloc`, `<Feature>Event` (sealed), `<Feature>State` (sealed), concrete events/states prefixed with the feature (e.g. `FetchAudiobookDetails`, `AudiobookDetailsLoaded`).
- Services: `<Source><Concern>Service` (e.g. `KnigavuheDetailService`, `SoundBooksListService`), or `<Concern>Service` for non-source (`BookmarkService`, `CharacterService`, `EqualizerService`).
- Notifiers: `<Source>AudiobookNotifier` (e.g. `YoutubeAudiobookNotifier`, `FourReadAudiobookNotifier`).
- Models: singular `PascalCase` noun (`Audiobook`, `AudiobookFile`, `HistoryOfAudiobook`).

**Hive box names:** `snake_case_box` suffix (mostly — `four_read_auth` and `settings` lack the `_box` suffix).

## Where to Add New Code

**New screen / feature:**
- Create `lib/screens/<feature>/<feature>.dart` (StatefulWidget).
- Add a GoRoute in `lib/main.dart`'s `_buildRouter()` — pick the right `StatefulShellBranch` (home branch for browse-related, or a new branch for a new tab).
- If the screen has async data fetching, add `lib/screens/<feature>/bloc/` with the three `part`-of files and register a `BlocProvider` either in `MyApp.build`'s `MultiBlocProvider` (if global) or inline in the screen.
- Screen-private widgets → `lib/screens/<feature>/widgets/`.

**New scraped audio source (mirror knigavuhe / sound-books):**
- Create `lib/resources/services/<source>/` with:
  - `<source>_http.dart`: `static const baseUrl`, `static const headers`, `static bool isBlocked(http.Response)`, `<Source>BlockedException`.
  - `<source>_list_service.dart`: `fetchLatestBooks`, `fetchTopBooks`, etc. returning `List<Audiobook>`.
  - `<source>_search_service.dart`: search returning `List<Audiobook>`.
  - `<source>_detail_service.dart`: `getAudiobookFiles(id)` returning `Either<String, DetailResult>` (files + description).
- Add a `SearchSourceSelection` enum value in `lib/screens/search/bloc/search_bloc.dart` and wire it into `_onSearchSubmitted`.
- Add an `is<Source>` bool flag to `AudiobookDetails` widget + `FetchAudiobookDetails` event + the branch in `AudiobookDetailsBloc.fetchAudiobookDetails`.
- Add a browse screen + bloc (`lib/screens/<source>_lists/`) if the source has discoverable lists.
- Add a Hive box for auth if the source needs login (mirror `four_read_auth` + `four_read_login/` screen).
- Add a directory name constant in `lib/utils/app_constants.dart`.

**New service (non-source):**
- Place in `lib/resources/services/<concern>_service.dart`.
- If it needs global observable state, extend `ChangeNotifier` and register in `lib/main.dart`'s `MultiProvider` (and/or use the singleton `static final _instance` + `factory` pattern if accessed from non-widget code).
- If it returns data with error channel, use `fpdart` `Either<String, T>`.

**New model:**
- Place in `lib/resources/models/<noun>.dart`.
- Provide `fromJson` (for external API shape), `fromMap` / `toMap` (for Hive persistence), `copyWith`.
- Keep fetching logic OUT of the model — put it in a service (see Anti-Patterns in ARCHITECTURE.md).

**New shared widget:**
- Place in `lib/widgets/<descriptive>.dart`.
- If it's screen-private, place in `lib/screens/<feature>/widgets/` instead.

**New util / helper:**
- Place in `lib/utils/`.

**New Hive box:**
- Open it in `initHive()` in `lib/main.dart` (add `await Hive.openBox('<name>_box');`).
- If it holds user data that must survive app updates, add it to `UpdateDataBackupService._protectedBoxes` in `lib/resources/services/update_data_backup_service.dart`.

**New test:**
- Place in `test/<feature>_<concern>_test.dart` (matches existing naming).
- Inject a fake `PlaybackEngine` into `MyAudioHandler` for playback tests.

**New bundled asset:**
- Drop the file in `assets/`.
- Add the path to `pubspec.yaml` under `flutter.assets`.

## Special Directories

**`build/`:**
- Purpose: Flutter build output (APK, intermediates).
- Generated: yes (by `flutter build`).
- Committed: no (gitignored).

**`.dart_tool/`:**
- Purpose: Dart analyzer + pub cache pointers.
- Generated: yes.
- Committed: no (gitignored).

**`scratch/`:**
- Purpose: throwaway experimentation scripts.
- Generated: no.
- Committed: yes (but excluded from analyzer via `analysis_options.yaml` `analyzer.exclude`).

**`openspec/`:**
- Purpose: OpenSpec change-tracking (proposals, designs, tasks, capability specs).
- Generated: partially (by OpenSpec tooling).
- Committed: yes.

**`openspec/changes/archive/`:**
- Purpose: completed/archived OpenSpec changes (dated folders `YYYY-MM-DD-<slug>`).
- Generated: by OpenSpec archive flow.
- Committed: yes.

**`.planning/`:**
- Purpose: GSD planning artifacts (codebase maps, phase plans, etc.).
- Generated: by GSD commands.
- Committed: yes (this document lives here).

**`fastlane/`:**
- Purpose: Fastlane deployment config.
- Generated: partially.
- Committed: yes.

**`bin/`:**
- Purpose: standalone Dart CLI scripts for debugging (chapter-parser inspection).
- Generated: no.
- Committed: yes.

---

*Structure analysis: 2026-07-13*
