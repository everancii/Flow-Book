# Technology Stack

**Analysis Date:** 2026-07-13

## Languages

**Primary:**
- Dart — Flutter app logic, all code under `lib/`

**Secondary:**
- Kotlin — Android host activity & native update installer (`android/app/src/main/kotlin/`)
- Java — Android plugin registrant (`android/app/src/main/java/`)
- Gradle (Groovy DSL) — Android build scripts (`android/app/build.gradle`, `android/build.gradle`)
- Shell — device update helper (`scripts/update-android-device.sh`)

## Runtime

**Environment:**
- Flutter `3.44.1` (pinned in `pubspec.yaml` `environment.flutter`)
- Dart SDK `^3.5.4`
- Android `minSdkVersion` = Flutter default (21 per `flutter_launcher_icons.min_sdk_android`), `targetSdk`/`compileSdk` = Flutter default
- JVM target `17` for Kotlin/Java compile (`android/app/build.gradle`)

**Package Manager:**
- Pub — Flutter/Dart package manager
- Lockfile: `pubspec.lock` (present, committed)
- Gradle — Android native deps (no versioned wrapper file committed; uses Flutter plugin)

## Frameworks

**Core:**
- Flutter `3.44.1` — UI toolkit, app shell (`lib/main.dart`)
- `flutter_bloc` `9.1.1` + `bloc` `9.2.1` — state management for screen-scoped blocs (`lib/screens/*/bloc/`)
- `provider` `6.1.5+1` — app-level `ChangeNotifier` providers (`lib/main.dart` `MultiProvider`)
- `go_router` `17.2.3` — declarative routing with `StatefulShellRoute.indexedStack` (`lib/main.dart`)
- `fpdart` `1.2.0` — `Either<L,R>` for fallible service calls (used across `lib/resources/services/`)

**Testing:**
- `flutter_test` (SDK) — widget & unit tests
- No 3rd-party test framework or mocking lib detected

**Build/Dev:**
- `build_runner` `2.4.13` — code generation runner (Hive adapters)
- `hive_generator` `2.0.1` — `.g.dart` Hive type adapters
- `flutter_launcher_icons` `0.14.4` — app icon generation
- `flutter_lints` `6.0.0` — lint ruleset (`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`)

## Key Dependencies

**Critical (audio pipeline):**
- `just_audio` `0.10.5` — **forked** from `https://github.com/sagarchaulagai/just_audio.git` (ref `a6f8db8`), audio playback engine
- `audio_service` `0.18.18` — background playback + media notification + `MediaBrowserService` integration (`lib/resources/services/my_audio_handler.dart`)
- `just_audio_background` `0.0.1-beta.17` — ties `just_audio` to `audio_service` media items
- `audio_session` `0.2.3` — audio focus management
- `rxdart` `0.28.0` — `BehaviorSubject`/stream combinators for playback state in `my_audio_handler.dart`
- `audio_video_progress_bar` `2.0.3` — seek bar widget

**Critical (media sources):**
- `youtube_explode_dart` `2.4.1` — **forked** from `https://github.com/sheikhhaziq/youtube_explode_dart.git` (ref `0dc5514`), YouTube stream extraction without API key
- `flutter_media_metadata` `1.0.0` — **forked** from `https://github.com/sagarchaulagai/flutter_media_metadata.git` (ref `7666c7b`), local file metadata parsing
- `saf` `1.0.3+4` — **forked** from `https://github.com/sagarchaulagai/saf.git` (ref `d0ecbf9`), Android Storage Access Framework

**Critical (storage & downloads):**
- `hive` `2.2.3` + `hive_flutter` `1.1.0` — local NoSQL key-value store, 12 boxes opened in `lib/main.dart` `initHive()`
- `background_downloader` `9.5.5` — resilient file downloads (`lib/resources/services/download/download_manager.dart`)
- `media_store_plus` `0.1.3` — Android MediaStore access for downloads
- `path_provider` `2.1.5` — app/external storage dirs

**Critical (network & UI):**
- `http` `1.6.0` — all REST/HTML fetching (no Dio)
- `cached_network_image` `3.4.1` — cover image loading/caching
- `google_fonts` `8.1.0` — font loading
- `flutter_inappwebview` `6.1.5` — YouTube & 4read WebView login (`lib/screens/youtube_webview/`, `lib/screens/four_read_login/`)

**Infrastructure:**
- `permission_handler` `12.0.2` — runtime permissions (`lib/utils/permission_helper.dart`)
- `connectivity_plus` `7.1.1` — online/offline detection
- `device_info_plus` `13.1.0` — ABI detection for APK update selection (`lib/resources/latest_version_fetch.dart`)
- `flutter_background` `1.3.1` — background execution
- `url_launcher` `6.3.1`, `open_file` `3.5.11`, `file_picker` `12.0.0-beta.5`, `image_picker` `1.2.2`, `back_button_interceptor` `8.0.4`, `visibility_detector` `0.4.0+2`, `we_slide` `2.4.0`, `transparent_image` `2.0.1`, `intl` `0.20.2`, `meta` `1.18.0`, `path` `1.9.1`
- `logger` `2.7.0` — wrapped by `lib/utils/app_logger.dart` (file logging to external storage `log/applogs.txt`)

## Configuration

**Environment:**
- No `.env` / env-var system. App is config-free — no account, no API keys in env.
- All "config" is user preference persisted in Hive boxes (`settings`, `language_prefs_box`, `theme_mode_box`, `dual_mode_box`).
- Bundled asset `assets/language_subjects.txt` — multi-language subject index parsed at runtime by `_LanguageSubjectIndex` in `lib/resources/archive_api.dart`.
- Bundled asset `assets/version.json` — legacy version string (currently `1.1.18`, superseded by `pubspec.yaml` `version: 1.2.0+2020`).

**Build:**
- `pubspec.yaml` — Dart deps + 3 git-fork overrides (`just_audio`, `flutter_media_metadata`, `saf`, `youtube_explode_dart`)
- `analysis_options.yaml` — `flutter_lints/flutter.yaml` ruleset, excludes `scratch/**`
- `devtools_options.yaml` — DevTools extension config (stub)
- `android/app/build.gradle` — `applicationId com.everancii.audiobookflow`, release signing via `key.properties` (not committed), `minifyEnabled true` + `shrinkResources true` + ProGuard
- `android/app/src/main/AndroidManifest.xml` — `usesCleartextTraffic="true"` (required for unencrypted CDN streams from 4read/knigavuhe), permissions: INTERNET, network state, foreground media service, POST_NOTIFICATIONS, media access, MODIFY_AUDIO_SETTINGS, REQUEST_INSTALL_PACKAGES
- `flutter_launcher_icons` block in `pubspec.yaml` — Android-only icons, `ios: false`

## Platform Requirements

**Development:**
- Flutter SDK `3.44.1`, Dart `^3.5.4`
- JDK 17 (Gradle `kotlinOptions.jvmTarget = "17"`)
- Android SDK with `compileSdk` = Flutter default
- Build: `flutter pub get && flutter build apk --release --split-per-abi`

**Production:**
- Android primary target. App ID `com.everancii.audiobookflow`.
- macOS desktop scaffolding present (`macos/`) but not configured as a shipped target.
- iOS explicitly disabled (`flutter_launcher_icons.ios: false`).
- Distribution: GitHub Releases on `everancii/Flow-Book` — in-app updater fetches `https://api.github.com/repos/everancii/Flow-Book/releases/latest` and installs APK via `MethodChannel('app_update_channel')` → `installApk`.
- No CI pipeline (no `.github/workflows/`). `fastlane/` contains metadata only.
- Local device deploy script: `scripts/update-android-device.sh <ip:port>`.

---

*Stack analysis: 2026-07-13*
