# External Integrations

**Analysis Date:** 2026-07-13

## APIs & External Services

**LibriVox / Archive.org (primary catalog):**
- Service: Archive.org `advancedsearch.php` for LibriVox collection browse/search/genre/recommendation
- SDK/Client: `package:http` (no SDK), hand-built URLs in `lib/resources/archive_api.dart`
- Endpoints:
  - `https://archive.org/advancedsearch.php?q=collection:(librivoxaudio)+AND+...&fl=...&output=json&page=&rows=` (`archive_api.dart:134`, `archive_api.dart:1941`, `archive_api.dart:1955`)
  - `https://archive.org/download/{identifier}/{file}` for audio files (`lib/resources/models/audiobook_file.dart:14`, `_base` constant)
  - `https://archive.org/services/get-item-image.php?identifier={id}` for cover images (`audiobook.dart:58`, `audiobook_file.dart:210`, `audiobook_file.dart:223`)
- Auth: None. Public API.
- Caching: in-memory ETag/Last-Modified cache (`_CacheEntry` class, `archive_api.dart:14`); language-clause memoization (`_memoLangClause`).

**YouTube (streaming):**
- Service: YouTube audio streaming + playlist/search
- SDK/Client: `youtube_explode_dart` (forked, no API key) — `lib/resources/services/youtube/youtube_audio_service.dart`, `youtube_search_service.dart`, `download_manager.dart`
- Endpoints:
  - `youtube_explode_dart` internal extraction (no key)
  - YouTube InnerTube browse API: `https://www.youtube.com/youtubei/v1/browse?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8` — hardcoded API key, `clientName: ANDROID_VR`, used for playlist video fetching (`lib/resources/models/audiobook_file.dart:403`)
  - Thumbnails: `https://i.ytimg.com/vi/{videoId}/hqdefault.jpg`
- Auth: None. WebView fallback for age/login-gated content at `lib/screens/youtube_webview/youtube_webview.dart`.

**4read.org (Russian audiobook aggregator):**
- Service: HTML scraping — search, top books, book page, m3u playlist
- SDK/Client: `package:http` + regex HTML parsing
- Files: `lib/resources/services/four_read/four_read_*` (auth, search, page, top_books, storage, open_guard, open_telemetry, audiobook_notifier)
- Endpoints:
  - `https://4read.org/` — login (CSRF `dle_login_hash` extraction), search, page fetch
  - `https://4read.org/?do=search&mode=advanced&subaction=search&story={q}&search_start={page}` — search (`four_read_search_service.dart:20`)
  - `https://4read.org/m3u/{playlistName}` — m3u audio playlist (`audiobook_file.dart:699`)
- Auth: Cookie-based form login. Credentials (username + password, JSON-encoded) and cookies persisted in Hive box `four_read_auth` (`four_read_auth_service.dart`). WebView login fallback at `lib/screens/four_read_login/four_read_webview_login.dart`.
- Headers: spoofed Chrome desktop User-Agent, `Referer: https://4read.org/`.

**knigavuhe.org (Russian audiobook aggregator):**
- Service: HTML scraping — search, lists, detail
- SDK/Client: `package:http` + regex HTML parsing
- Files: `lib/resources/services/knigavuhe/knigavuhe_*` (http, search, list, detail)
- Endpoints:
  - `https://knigavuhe.org` base (`knigavuhe_http.dart:15`)
  - Book detail pages parsed for `cur.book` JS object (blocked flag, tracks) — `knigavuhe_detail_service.dart`
- Auth: None. DDoS-Guard browser check handled — `KnigavuheHttp.isBlocked()` detects `ddos-guard` server / "checking your browser" body and surfaces `KnigavuheBlockedException`.
- Headers: spoofed Chrome desktop UA, `Accept-Language: ru-RU`.

**sound-books.net (Ukrainian audiobook aggregator):**
- Service: HTML scraping — search, lists, detail
- SDK/Client: `package:http` + regex HTML parsing
- Files: `lib/resources/services/soundbooks/soundbooks_*` (http, search, list, detail)
- Endpoints:
  - `https://sound-books.net` base (`soundbooks_http.dart:15`)
  - Book detail pages parsed for PlayerJS `file:"...m3u"` playlist URL — `soundbooks_detail_service.dart:122`
- Auth: None. DDoS-Guard handled same as knigavuhe (`SoundBooksHttp.isBlocked()`).
- Headers: spoofed Chrome desktop UA, `Accept-Language: uk-UA`.

**GitHub Releases (in-app updater):**
- Service: GitHub REST API — latest release fetch + APK download
- SDK/Client: `package:http`
- File: `lib/resources/latest_version_fetch.dart`
- Endpoints:
  - `https://api.github.com/repos/everancii/Flow-Book/releases/latest` (header `Accept: application/vnd.github.v3+json`) — `latest_version_fetch.dart:15`
  - APK download URL from release assets, selected by device ABI via `LatestVersionFetchModel.apkDownloadUrlForAbis(androidInfo.supportedAbis)`
- Auth: None (public repo). `REQUEST_INSTALL_PACKAGES` permission + `MethodChannel('app_update_channel')` → native `installApk` for install.
- Pre-install: `UpdateDataBackupService.createPreUpdateBackup()` backs up Hive data before update.

**Google Books (dead code):**
- Model `lib/resources/models/google_book_result.dart` exists with `fromJson` parser, but no caller — `GoogleBookResult` is never imported outside its own file. Not wired to any service or screen. No API key, no endpoint usage.

## Data Storage

**Databases:**
- Hive (local NoSQL key-value) — no remote DB
  - Client: `hive` `2.2.3` + `hive_flutter` `1.1.0`
  - Init: `lib/main.dart` `initHive()` opens 12 boxes before `runApp`:
    - `favourite_audiobooks_box`, `download_status_box`, `playing_audiobook_details_box`, `theme_mode_box`, `history_of_audiobook_box`, `recommened_audiobooks_box`, `dual_mode_box`, `language_prefs_box`, `bookmarks_box`, `listening_stats_box`, `four_read_auth`, `settings`
  - Adapters: generated via `hive_generator` + `build_runner` (`*.g.dart`)
  - Post-update restore: `UpdateDataBackupService.restoreMissingDataAfterUpdate()` called in `initHive()`.

**File Storage:**
- Local filesystem only — no cloud file storage
  - App docs dir: `getApplicationDocumentsDirectory()` — Hive box files, `downloads/`, per-source subdirs (`youtube/`, `4read/`, `knigavuhe/`, `soundbooks/`, `local/` per `lib/utils/app_constants.dart`)
  - External storage: `getExternalStorageDirectory()` on Android — downloads, APK update cache (`{version}.apk`), log file `log/applogs.txt`
  - 4read audiobook dirs: base64url-encoded audiobook ID under `4read/` (`four_read_storage.dart`)
  - Cover images: local cache via `lib/resources/services/local/cover_image_service.dart`
  - `media_store_plus` for Android MediaStore integration on downloads

**Caching:**
- In-memory HTTP cache with ETag/Last-Modified for Archive.org only (`_CacheEntry` in `archive_api.dart:14`)
- Image cache: `cached_network_image` (Flutter `ImageCache` underneath)
- No external cache service (no Redis, no shared pref cache layer)

## Authentication & Identity

**Auth Provider:**
- No app-level auth. "No account required" per `README.md`.
- 4read.org only: cookie-based site login managed by `FourReadAuthService` (`four_read_auth_service.dart`). CSRF token (`dle_login_hash`) scraped from login page HTML, form POST with `login_name`/`login_password`/`login_hash=submit`, cookies collected from `Set-Cookie` headers + redirect chain, persisted in Hive box `four_read_auth`.
  - Credentials stored as plaintext JSON `{username, password}` in Hive — no encryption.
  - WebView login fallback: `lib/screens/four_read_login/four_read_webview_login.dart` loads `https://4read.org/` and extracts cookies.

## Monitoring & Observability

**Error Tracking:**
- None. No Sentry, Crashlytics, or remote error reporting.

**Logs:**
- Custom `AppLogger` (`lib/utils/app_logger.dart`) wraps `package:logger`.
- File logging to Android external storage `log/applogs.txt` (append-mode, timestamped).
- Tagged calls: `AppLogger.debug/info/error(message, tag)` used throughout services.
- No log shipping — local file only.

## CI/CD & Deployment

**Hosting:**
- GitHub Releases on `everancii/Flow-Book` — APK artifacts, in-app self-update.
- No app store distribution configured (fastlane metadata present but no lane config).

**CI Pipeline:**
- None. No `.github/`, no CI config files detected.

**Release flow (manual):**
1. Bump `pubspec.yaml` `version: x.y.z+N`
2. `flutter build apk --release --split-per-abi`
3. Upload APKs to GitHub Release
4. App auto-detects via `LatestVersionFetch.getLatestVersion()` and prompts user

## Environment Configuration

**Required env vars:**
- None. App runs with zero environment configuration.

**Secrets location:**
- No secrets management. Hardcoded values:
  - YouTube InnerTube API key `AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8` in `lib/resources/models/audiobook_file.dart:403` (public Android VR client key, not a secret per se)
  - 4read user credentials stored in Hive as plaintext JSON (user-supplied, not app secret)
- Android release signing: `android/key.properties` (not committed) referenced by `android/app/build.gradle` — keystore path + passwords kept off-repo.

## Webhooks & Callbacks

**Incoming:**
- None. No server, no webhook receivers.

**Outgoing:**
- None. App is purely a client/consumer.

## Native Platform Channels

- `MethodChannel('app_update_channel')` — `installApk` method invoked from `LatestVersionFetch.installUpdate()` (`latest_version_fetch.dart:13`). Native Kotlin/Java handler in `android/app/src/main/kotlin/` triggers Android package installer intent.

---

*Integration audit: 2026-07-13*
