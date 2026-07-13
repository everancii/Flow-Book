# Codebase Concerns

**Analysis Date:** 2026-07-13

## Tech Debt

### Global mutable `isRecommendScreen` flag

- Issue: Top-level mutable `int isRecommendScreen = 0;` set inside `initHive()` and read by `_buildRouter()` to pick the initial route. Mutated across async boundary; router reads it via `late final` capture, so any later mutation is ignored.
- Files: `lib/main.dart:73`, `lib/main.dart:90`, `lib/main.dart:108-115`
- Impact: Route decision is order-dependent; any refactor that touches `initHive()` or `main()` can silently flip the start screen. Not testable in isolation.
- Fix approach: Read `Hive.box('dual_mode_box').get('mode')` directly inside the GoRouter `redirect` / `initialLocation` builder, or inject via a `Provider`. Delete the global.

### `Box<dynamic>` everywhere with no DI

- Issue: ~30 `Hive.box('...')` calls scattered across widgets, BLoCs, services, singletons. Boxes typed `Box<dynamic>` (22 `late Box<dynamic>` declarations). All reads require manual casts: `state.extra as Map<String, dynamic>`, `extras['isDownload'] as bool`, `box.get('index') as int`. No adapter registration; no type-safe boxes.
- Files: `lib/main.dart:78-89`, `lib/widgets/mini_audio_player.dart:20`, `lib/screens/audiobook_details/audiobook_details.dart:54`, `lib/screens/audiobook_player/audiobook_player.dart:40`, `lib/resources/services/download/download_manager.dart:31`, `lib/resources/services/my_audio_handler.dart:207`, `lib/resources/designs/theme_notifier.dart:11`, `lib/resources/designs/language_notifier.dart:5`, `lib/resources/services/listening_stats.dart`, `lib/resources/services/bookmark_service.dart`, `lib/resources/services/four_read/four_read_auth_service.dart:11`, `lib/resources/services/character_service.dart:7`, `lib/resources/services/equalizer_service.dart:12`
- Impact: Runtime `CastError` risk on any malformed data; refactor requires grepping every call site; no compile-time guarantees on box contents.
- Fix approach: Introduce a `BoxRegistry` singleton opened once in `main()`, inject via `Provider`. Generate typed adapters with `hive_generator` (already in dev deps but unused). Migrate high-traffic boxes (`playing_audiobook_details_box`, `favourite_audiobooks_box`, `history_of_audiobook_box`) to typed `Box<Audiobook>` / `Box<HistoryOfAudiobookItem>` first.

### Boolean source flags instead of enum

- Issue: `AudiobookDetails` widget takes 7 boolean source flags (`isDownload`, `isYoutube`, `isYoutubeSearch`, `isLocal`, `isFourRead`, `isKnigavuhe`, `isSoundBooks`). `AudiobookDetailsBloc.fetchAudiobookDetails` dispatches via an if/else chain on those flags. Adding a source = touch widget, route builder, BLoC, and `AudiobookFile.fromXxx` factory.
- Files: `lib/screens/audiobook_details/audiobook_details.dart:26-46`, `lib/main.dart:148-172`, `lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart:50-167`
- Impact: Flag combinations are unguarded (`isFourRead && isKnigavuhe` is nonsense but compiles); 8+ code sites must stay in sync; easy to forget a flag when pushing a route.
- Fix approach: Define `enum Source { librivox, youtube, youtubeSearch, download, local, fourRead, knigavuhe, soundBooks }`. Replace booleans with `final Source source`. Replace if/else chain in BLoC with a `Map<Source, Future<Either<String, List<AudiobookFile>>> Function(String id)>` dispatch table. Pass `Source` via typed `state.extra` (`AudiobookDetailsArgs` record/class).

### 22 empty `catch (_) {}` blocks silently swallowing errors

- Issue: 22 catch blocks across the codebase discard the error and stack trace with no logging. Failures are invisible.
- Files: `lib/screens/download_audiobook/downloads_page.dart:289,358`, `lib/utils/media_helper.dart:239`, `lib/resources/services/download/download_manager.dart:147,383,438`, `lib/resources/services/my_audio_handler.dart:373,601,810,864`, `lib/resources/services/knigavuhe/knigavuhe_detail_service.dart:55`, `lib/resources/services/local/cover_image_service.dart:297,335,350`, `lib/resources/services/youtube/youtube_search_service.dart:60,64`, `lib/resources/services/youtube/youtube_audio_service.dart:47,57,76,86,165`, `lib/screens/download_audiobook/widget/download_button.dart:90`
- Impact: Download cleanup failures, stats writes, cover-art pruning, YouTube cache lookups all fail silently. Debugging production issues requires guessing where errors originate.
- Fix approach: Replace every `catch (_) {}` with `catch (e, s) { AppLogger.debug('<context>: $e', '<tag>'); }`. Where errors are genuinely expected (e.g. "file already deleted"), add a comment explaining why suppression is safe. Add `lint: avoid_catches_without_on_clauses` to `analysis_options.yaml`.

### `AudioHandlerProvider` constructs a throwaway `MyAudioHandler` then replaces it

- Issue: `late MyAudioHandler _audioHandler = MyAudioHandler();` runs in field initializer, creating an `AudioPlayer`, equalizer, subscriptions. `initialize()` then rebuilds via `AudioService.init(builder: () => MyAudioHandler())` and overwrites `_audioHandler`. The first instance is never disposed.
- Files: `lib/resources/services/audio_handler_provider.dart:6-17`
- Impact: Widgets that call `context.read<AudioHandlerProvider>().audioHandler` between `runApp` and `initialize()` completion (post-frame, async) get the throwaway handler — its `AudioPlayer` is never wired to `AudioService`, so background playback / notification controls silently no-op. The throwaway's `AudioPlayer` and its stream subscriptions leak until GC.
- Fix approach: Make `_audioHandler` nullable (`MyAudioHandler? _audioHandler`). Getter throws `StateError` until `initialize()` completes, OR returns a no-op stub. In `initialize()`, dispose the temp if present. Gate UI on an `isInitialized` `ValueNotifier<bool>`.

### `DownloadManager` never disposes its `StreamController`; `YoutubeExplode` recreated per download

- Issue: `_progressController = StreamController<DownloadProgress>.broadcast()` (line 34) has no `dispose()` method on `DownloadManager`. Singleton lives for app lifetime — acceptable for broadcast controller, but no teardown path exists. `YoutubeExplode` instantiated per `downloadAudiobook()` call (line 90); closed only in `finally` (line 373). If `downloadAudiobook` is called concurrently for multiple books, multiple `YoutubeExplode` instances exist simultaneously, each holding HTTP client + cache.
- Files: `lib/resources/services/download/download_manager.dart:25-37,90,372-375`
- Impact: Memory pressure during batch downloads; `_activeDownloads` map is in-memory only, so app kill mid-YouTube-download leaves orphaned partial files and no resume.
- Fix approach: Hoist `YoutubeExplode` to a class field (`final YoutubeExplode _yt = YoutubeExplode();`), reuse across downloads, close in a `dispose()`. Add `dispose()` to `DownloadManager` that closes `_progressController` and `_yt`. Implement YouTube download resume by persisting per-file byte offset to `download_status_box`.

### `archive_api.dart` is 2022 lines mixing 5 concerns

- Issue: Single file combines: HTTP cache (`_CacheEntry`, `_getJson`), language-clause memoization (`_memoLangClause`, `_memoSelected`, `_invalidateLangMemo`), genre→subject query builder (`_buildSubjectQueryForGenre`, `_categoryFilters` with Hebrew regex tables), `_LanguageSubjectIndex` loader, and `ArchiveApi` public client. Static `http.Client _client` (line 1764) is never closed in production — `dispose()` (line 1825) exists but no caller.
- Files: `lib/resources/archive_api.dart:1-2022`
- Impact: Any change to language filtering risks the search URL builder; tests must import 2000 lines to test one function; regex tables (lines 1700-1704) for Hebrew subject matching are inline data that belongs in a JSON asset.
- Fix approach: Split into `lib/resources/services/archive/archive_client.dart`, `archive_cache.dart`, `archive_language_clause.dart`, `archive_genre_subjects.dart`, `archive_language_index.dart`. Move `_langAliases` and `_categoryFilters` to `assets/archive_language_filters.json`. Call `ArchiveApi.dispose()` from `MyApp.dispose()`.

### `search_audiobook.dart` is 957 lines with 7 private widget classes

- Issue: Single file defines `SearchAudiobook` state + `_SearchResultTile`, `_SourceBadge`, `_SectionHeader`, `_SourceChoiceChips`, `_EmptyPrompt`, plus scroll-listener pagination logic.
- Files: `lib/screens/search/search_audiobook.dart:18-957`
- Impact: Hard to locate a specific widget; rebuilds of one private widget recompile the file; no reuse across screens.
- Fix approach: Extract each private class to `lib/screens/search/widgets/<name>.dart`. Move scroll-pagination listener into a `SearchPaginationController` class bound to `SearchBloc`.

## Known Bugs

### Empty `setState(() {})` rebuilds mask missing reactive bindings

- Symptoms: 7 callsites call `setState(() {})` with no state change. Forces full widget rebuild without indicating what changed. Hides the real reactive source.
- Files: `lib/screens/setting/settings.dart:205,276,371`, `lib/screens/search/search_audiobook.dart:58,71`, `lib/screens/youtube_webview/youtube_webview.dart:92`, `lib/screens/audiobook_details/audiobook_details.dart:171`
- Trigger: Open settings, toggle a chip, observe full-tree rebuild. Open YouTube webview, navigate, observe rebuild on every URL change.
- Workaround: None; works but burns frames.
- Fix: Wrap the actual reactive value in `ValueListenableBuilder` / `ListenableBuilder` / `StreamBuilder`. Remove empty `setState`.

### YouTube webview loading state force-dismissed by 8-second timer

- Symptoms: `_loadingTimer = Timer(Duration(seconds: 8), ...)` force-sets `_isWebViewLoading = false` because "YouTube's dynamic loading may never trigger onLoadStop properly".
- Files: `lib/screens/youtube_webview/youtube_webview.dart:47-53`
- Trigger: Open YouTube import webview on a slow connection; loading spinner may dismiss while page is still rendering.
- Workaround: Timer. User sees a blank page if load takes >8s.
- Fix: Replace fixed timeout with a `onProgressChanged` listener that dismisses loading only when progress reaches 100 OR after a longer adaptive timeout tied to `onLoadResource` activity.

### Cold-start race: widgets may read throwaway `AudioHandler` before `AudioService.init` completes

- Symptoms: `main.dart` calls `runApp()` then `addPostFrameCallback(() => audioHandlerProvider.initialize())`. `initialize()` is async (`AudioService.init`). Between first frame and init completion, `Provider.of<AudioHandlerProvider>(context).audioHandler` returns the field-initialized throwaway `MyAudioHandler()` whose `AudioPlayer` is not connected to `AudioService`.
- Files: `lib/main.dart:42-66`, `lib/resources/services/audio_handler_provider.dart:6-17`
- Trigger: Cold start, immediately tap a book on home screen before notification channel is wired.
- Workaround: `restoreIfNeeded()` happens lazily on first `play()`, so most paths self-heal. But notification + background-service integration is missing for the throwaway.
- Fix: See `AudioHandlerProvider` fix in Tech Debt section.

### `Future.delayed(60s, () => sub.cancel())` is fire-and-forget

- Symptoms: In `initSongs`, a `processingStateStream` subscription is cancelled via a detached `Future.delayed`. If `initSongs` re-enters before 60s, multiple delayed-futures stack; if app dies before 60s, sub leaks.
- Files: `lib/resources/services/my_audio_handler.dart:608`
- Trigger: Rapid track-skipping or re-pressing play on a new book within 60s.
- Workaround: The `_initGen` guard discards stale callbacks, but the subscription object itself lingers.
- Fix: Track the subscription in a field (`StreamSubscription? _initSettleSub`), cancel it explicitly at the top of the next `initSongs` and in `dispose`. Drop the `Future.delayed`.

### `_recordListeningSession` silently fails, stats undercounted forever

- Symptoms: `_recordListeningSession()` body wrapped in `catch (_) {}`. If `listening_stats_box` is locked / corrupt, every 10-second listening interval is dropped with no log.
- Files: `lib/resources/services/my_audio_handler.dart:794-811`
- Trigger: Hive box corruption (rare but possible after force-kill mid-write).
- Workaround: None. User sees stale/zero stats with no error.
- Fix: Log the error via `AppLogger.error('stats write failed: $e')`. Consider a retry with backoff, or fall back to an in-memory accumulator that flushes when the box recovers.

### `Audiobook.fromMap` vs `toMap` type mismatch

- Symptoms: `Audiobook.toMap()` returns `Map<dynamic, dynamic>` (line 78) but call sites cast JSON to `Map<String, dynamic>` before calling `fromMap` (`downloads_page.dart:299`, `youtube_audiobook_notifier.dart:53`, `four_read_audiobook_notifier.dart:51`). `Audiobook.fromMap` accepts `Map<dynamic, dynamic>` (line 97). Works because `[]` is polymorphic, but the type signatures disagree.
- Files: `lib/resources/models/audiobook.dart:78,97,115`, `lib/resources/models/audiobook_file.dart:770,787,802`
- Trigger: No runtime bug today, but any code that does `audiobook.toMap() as Map<String, dynamic>` will throw.
- Workaround: None needed yet.
- Fix: Pick one map type. Recommend `Map<String, dynamic>` for both `toMap` and `fromMap` (JSON-interopable). Update all callers.

## Security Considerations

### `android:usesCleartextTraffic="true"` app-wide

- Risk: All network traffic may use HTTP. README justifies for 4read/knigavuhe CDN streams, but the flag is global — any HTTP endpoint (image CDN, analytics, third-party) is allowed. MITM risk on guest Wi-Fi.
- Files: `android/app/src/main/AndroidManifest.xml:36`, `README.md:17`
- Current mitigation: None; cleartext allowed for every domain.
- Recommendations: Replace with `android:networkSecurityConfig="@xml/network_security_config"`. Define a `res/xml/network_security_config.xml` that defaults to HTTPS-only and allowlists cleartext for the specific 4read/knigavuhe CDN hostnames. Document the hostnames in the README.

### 4Read credentials stored in plaintext Hive box

- Risk: `FourReadAuthService.saveCredentials(username, password)` writes `jsonEncode({'username': ..., 'password': ...})` to Hive box `four_read_auth` with no encryption. Combined with `android:allowBackup="true"` (manifest line 32) and `fullBackupContent="@xml/backup_rules"`, creds may sync to Google Drive. Anyone with file-system access (rooted device, ADB, backup extraction) reads the password.
- Files: `lib/resources/services/four_read/four_read_auth_service.dart:24-29`, `android/app/src/main/AndroidManifest.xml:32-34`
- Current mitigation: None.
- Recommendations: Migrate credentials to `flutter_secure_storage` (Keystore-backed on Android, Keychain on iOS). Keep cookies in Hive if needed (session tokens are short-lived and revocable; passwords are not). Exclude `four_read_auth` box from `backup_rules.xml` via `<exclude domain="sharedpref" path="four_read_auth.hive"/>` (Hive stores in `.` by default — confirm path).

### Auth cookies logged to file in release builds

- Risk: `AppLogger.debug('[FourReadAuth] All cookies: $cookieString', ...)` and `AppLogger.debug('[FourReadWebView] Cookies: $cookies', ...)` write the full cookie string (including `dle_user_id` session token) to `getExternalStorageDirectory()/log/applogs.txt`. `AppLogger._writeToFile` runs unconditionally — only the `print` call is gated on `kDebugMode` (`app_logger.dart:92-95`). Log file is world-readable on Android <10 scoped-storage changes.
- Files: `lib/resources/services/four_read/four_read_auth_service.dart:124`, `lib/screens/four_read_login/four_read_webview_login.dart:80`, `lib/utils/app_logger.dart:90-128`
- Current mitigation: None.
- Recommendations: Gate `_writeToFile` on `kDebugMode` for release builds, OR redact cookie values (keep names, mask values). Add an `AppLogger.redact(String)` helper for sensitive strings. Consider writing logs to `getApplicationDocumentsDirectory()` (app-private) instead of external storage.

### `update_data_backup_service` writes unencrypted backup of user data

- Risk: `createPreUpdateBackup()` serializes `favourite_audiobooks_box`, `history_of_audiobook_box`, `bookmarks_box`, `listening_stats_box`, `playing_audiobook_details_box` to `flowbook_pre_update_backup.json` in `getApplicationDocumentsDirectory()`. Plaintext JSON. Included in auto-backup per `allowBackup="true"`.
- Files: `lib/resources/services/update_data_backup_service.dart:10-37`
- Current mitigation: None.
- Recommendations: Either exclude the backup file from `backup_rules.xml`, or encrypt with a key derived from Android Keystore. Low severity if the box contents are non-sensitive (favorites, history), but listening stats + bookmarks may be considered personal data under GDPR.

### InAppWebView loads third-party sites with JS enabled, no TLS pinning

- Risk: `flutter_inappwebview: ^6.1.5` loads `https://4read.org/` and YouTube with `javaScriptEnabled: true`. `shouldOverrideUrlLoading` only blocks `intent://` and `market://` schemes. No `onReceivedServerTrustAuthRequest` handler — default trust store used. On compromised network, TLS interception not detected.
- Files: `lib/screens/four_read_login/four_read_webview_login.dart:35-50`, `lib/screens/youtube_webview/youtube_webview.dart`
- Current mitigation: `shouldOverrideUrlLoading` blocks app-store intents.
- Recommendations: Add `onReceivedServerTrustAuthRequest` that validates against pinned certificates for 4read/YouTube. Disable JS where not needed (login webview needs JS; YouTube import webview needs JS — both legitimate). Document the trust model.

## Performance Bottlenecks

### Position persistence writes to Hive every 10 seconds during playback

- Problem: `_positionUpdateTimer = Timer.periodic(Duration(seconds: 10), ...)` calls `_persistNow` which does `playingAudiobookDetailsBox.put('index', idx)`, `put('position', liveMs)`, and `historyOfAudiobook.updateAudiobookPosition(...)` (which itself reads + writes the history box). 3+ box writes per 10s while playing.
- Files: `lib/resources/services/my_audio_handler.dart:780-791,265-275`
- Cause: Hive box is disk-backed; every `put` flushes. Position is also written on every `currentIndexStream` change (line 693).
- Improvement path: Keep position in a `ValueNotifier<Duration>` (already streamed from `_player.positionStream`). Persist to Hive only on: pause, track change, app lifecycle pause (`AppLifecycleState.paused`), and every 60s as a safety net. Reduces writes 6×.

### `probeFourReadDurations` creates a new `AudioPlayer` per track, sequentially

- Problem: For each 4read track missing duration, a fresh `AudioPlayer()` is constructed, `setUrl(url)` is awaited (HTTP HEAD + range request to 4read CDN), then `dispose()`. For a 60-track book, 60 sequential HTTP round-trips.
- Files: `lib/screens/audiobook_details/bloc/audiobook_details_bloc.dart:207-237`
- Cause: `AudioPlayer` is cheap but `setUrl` is not — it does a network request per track. Sequential await blocks the BLoC emitter.
- Improvement path: Reuse a single `AudioPlayer` across probes (reset via `setUrl` again). Or parallelize with a bounded pool (4 concurrent probes). Or switch to a lightweight HEAD-only duration probe (`http.head` + parse `Content-Length` / `X-Content-Duration` if the CDN exposes it). 8s per-track timeout (line 219) means worst case 480s for 60 tracks — unacceptable UX.

### YouTube search fires 16 concurrent requests with no concurrency cap

- Problem: For each selected language, `YoutubeSearchService.search` launches 2 futures (video search + playlist search). 8 selected languages → 16 concurrent `youtube_explode` search calls via `Future.wait`. No cap.
- Files: `lib/resources/services/youtube/youtube_search_service.dart:53-67`
- Cause: `youtube_explode` uses its own HTTP client; YouTube may rate-limit (429) or serve captcha pages for burst traffic.
- Improvement path: Cap concurrency at 4 with a `Pool` (package `pool`). Deduplicate by query before dispatch. Cache results per `(query, languages)` tuple for 5 minutes in memory.

### `chapter_parser.parseFile` reads entire audiobook into memory

- Problem: `final bytes = await file.readAsBytes();` loads the full MP3/M4B file into a `Uint8List`. A 1GB M4B book spikes 1GB RAM.
- Files: `lib/resources/services/local/chapter_parser.dart:23`
- Cause: ID3v2 CHAP frames and MP4 `chpl` atoms are at the head, but the code reads the whole file regardless.
- Improvement path: For MP3, read only the first `tagSize + 10` bytes (ID3 is at the head). For MP4, stream-parse the `moov` atom (typically at the front or end) without loading the `mdat` body. Use `RandomAccessFile` with `setPosition` + bounded reads.

### `archive_api._cache` is FIFO, not LRU

- Problem: Comment says "tiny LRU-ish trim" but eviction sorts by `storedAt` (oldest first) and drops the stalest 10% — that is FIFO by insert time, not by last access. A hot URL accessed frequently is still evicted if it was inserted early.
- Files: `lib/resources/archive_api.dart:1805-1819`
- Cause: `_CacheEntry` has no `lastAccessedAt`; `storedAt` is set once on insert and never updated on hit.
- Improvement path: Add `lastAccessedAt` to `_CacheEntry`, update on cache hit. Evict by `lastAccessedAt` ascending. Or use package `lru_cache` for a real LRU.

### History box stores full audiobook + all files per entry, unbounded

- Problem: `HistoryOfAudiobookItem.toMap()` serializes the entire `Audiobook` + all `AudiobookFile` objects. No cap on number of history entries. Heavy listener with 200 books in history, each with 50 tracks, stores ~10,000 `AudiobookFile` maps in Hive.
- Files: `lib/resources/models/history_of_audiobook.dart:41-57,138-145`
- Cause: No eviction policy; `addToHistory` only inserts if not present, but never trims.
- Improvement path: Cap history at 200 entries (LRU by `lastModified`). Store only `audiobook.id` + minimal metadata; lazy-load files from the source service on demand. Alternatively, store files in a separate box keyed by `audiobook.id` so history entries are small.

## Fragile Areas

### HTML-scraping services for 4read, knigavuhe, soundbooks

- Files: `lib/resources/services/four_read/four_read_search_service.dart`, `lib/resources/services/four_read/four_read_page_service.dart`, `lib/resources/services/knigavuhe/knigavuhe_search_service.dart`, `lib/resources/services/knigavuhe/knigavuhe_list_service.dart`, `lib/resources/services/knigavuhe/knigavuhe_detail_service.dart`, `lib/resources/services/soundbooks/soundbooks_list_service.dart`, `lib/resources/services/soundbooks/soundbooks_search_service.dart`, `lib/resources/services/soundbooks/soundbooks_detail_service.dart`
- Why fragile: All parse third-party HTML with `RegExp` against CSS class names (`short-item`, `bookkitem`, `poster__link`, `tile-item`). Any site UI change breaks parsing silently — services return `[]` via `if (cards.length <= 1) return [];` guards (6+ occurrences). No fixture-based contract tests. Only `four_read_open_guard_test.dart` (92 lines) and `soundbooks_test.dart` (291 lines) exist; 4read search/page and all knigavuhe services are untested.
- Safe modification: When updating a scraper, capture a real HTML fixture, add a test that parses it, then refactor. Never edit regex blind.
- Test coverage: Critical gap. Add `test/fixtures/<service>.html` files and `test/<service>_fixture_test.dart` per scraper.

### `youtube_explode_dart` fork + YouTube anti-bot cat-and-mouse

- Files: `pubspec.yaml:56-59`, `lib/resources/services/youtube/stream_client.dart:79-89`, `lib/resources/services/youtube/youtube_audio_service.dart`, `lib/resources/services/youtube/youtube_search_service.dart`
- Why fragile: Depends on `sheikhhaziq/youtube_explode_dart.git @ 0dc5514` (fork, commit-pinned). YouTube regularly breaks client keys (`ANDROID`, `androidVr`); `stream_client.dart:79` branches on `url.queryParameters['c'] == 'ANDROID'` and `googlevideo.com` host. If YT drops the ANDROID client (as they have done historically), streaming + downloading break with no fallback.
- Safe modification: Pin to a version range, not a bare commit. Before upgrading, run `test/playback_trust_test.dart` (520L) which covers playback init. Subscribe to upstream `youtube_explode_dart` releases; maintain a diff document explaining why the fork exists.
- Test coverage: `playback_trust_test.dart` covers init/restore; no test for `stream_client` chunking/retry logic. Add tests for 429/500/416 response handling.

### `GoRouter` `state.extra` untyped map with 7 boolean keys

- Files: `lib/main.dart:148-172`
- Why fragile: Every push to `/audiobook-details` must pass `extra: {'audiobook': Audiobook, 'isDownload': bool, 'isYoutube': bool, 'isLocal': bool, 'isYoutubeSearch': bool?, 'isFourRead': bool?, 'isKnigavuhe': bool?, 'isSoundBooks': bool?}`. Missing any key → `CastError` at runtime. No compile-time check.
- Safe modification: Define `class AudiobookDetailsArgs { final Audiobook audiobook; final Source source; const AudiobookDetailsArgs(...); }`. Change route builder to `final args = state.extra as AudiobookDetailsArgs;`. Grep all `context.push('/audiobook-details', extra: ...)` call sites (≥5) and migrate together.
- Test coverage: None. Add a test that pushes the route with `AudiobookDetailsArgs` and asserts no crash.

### `MyAudioHandler` 1054-line state machine

- Files: `lib/resources/services/my_audio_handler.dart:1-1054`
- Why fragile: Manages 6+ pieces of mutable state (`_isReinitializing`, `_canPersistProgress`, `_activeAudiobookId`, `_initGen`, `_sessionConfigured`, `_lastPersistAt`) with guards scattered: `if (myGen != _initGen) return;` appears multiple times. Race conditions between `initSongs`, `_restoreQueueFromBoxIfEmpty`, `_persistInstant`, `_listenForCurrentSongIndexChanges`, and `restoreIfNeeded`. Any new feature touching init flow risks subtle races.
- Safe modification: Before editing, read `test/playback_trust_test.dart` to understand the invariants the tests enforce. Add a test for any new state transition. Prefer adding to the `PlaybackEngine` abstraction (line 40) rather than `MyAudioHandler` directly.
- Test coverage: `playback_trust_test.dart` (520L) covers core trust scenarios. Not enough for init-gen race, cold-start restore, or sleep-timer interaction. Add tests for: rapid `initSongs` calls (gen-discard), `restoreIfNeeded` after `initSongs`, sleep-timer expiry during reinit.

### `DownloadManager` startup-order coupling

- Files: `lib/resources/services/download/download_manager.dart:31`, `lib/main.dart:75-95`
- Why fragile: `final Box<dynamic> downloadStatusBox = Hive.box('download_status_box');` is a field initializer — runs when the singleton is first accessed. If any code accesses `DownloadManager()` before `initHive()` completes, throws `HiveError("Box not found")`. `initHive()` calls `DownloadManager().cleanStaleStatuses()` at line 94, which is the first access — safe today, but any future eager access (e.g. a top-level `final dm = DownloadManager();`) breaks.
- Safe modification: Make `downloadStatusBox` a getter: `Box get downloadStatusBox => Hive.box('download_status_box');`. Or lazy-open in `cleanStaleStatuses`.
- Test coverage: None.

## Scaling Limits

### History box unbounded growth

- Current capacity: Unlimited entries; each entry stores full `Audiobook` + all `AudiobookFile` maps.
- Limit: Device storage. Heavy user (200 books × 50 tracks × ~1KB per file map) → ~10MB+ in Hive, slow box opens, slow `getHistory()` (maps every entry on each call, line 63-67).
- Scaling path: Cap at 200 entries, LRU eviction. Split files into a separate box keyed by `audiobook.id`. See Performance Bottlenecks section.

### Download status box never pruned post-completion

- Current capacity: One `status_<id>` key + one `task_<id>-<i>-<title>` key per file per download. `cleanStaleStatuses()` runs only at startup and only removes completed downloads whose directory is missing.
- Limit: 100 downloads × 30 tracks = 3000 keys + 100 status keys. Never decremented. Box bloats indefinitely.
- Scaling path: After a completed download is opened or deleted, remove its `task_*` keys. Add a `pruneCompletedTasks()` call on downloads-page open. Consider a separate `download_task_box` so `download_status_box` stays small.

### `_genreSubjectMemo` unbounded by genre×language combos

- Current capacity: `Map<String, String>` keyed by `<langs>#<genre>`. Cleared only on language-pref change (`archive_api.dart:1775`).
- Limit: 20 languages × 20 genres = 400 entries worst case — small. But grows without bound if genres are dynamic.
- Scaling path: Cap at 200 entries with LRU. Acceptable as-is; document the invariant.

### In-memory caches lost on app kill

- Current capacity: `archive_api._cache` (100 entries), `_coverCache` (256 entries), `FourReadPageService.descriptionCache` (unbounded). All in-memory only.
- Limit: Cold start re-fetches everything. Archive.org cache rebuilds on first browse.
- Scaling path: Optionally persist `archive_api._cache` to a Hive box for cold-start warmth. Low priority — 100 entries is small.

## Dependencies at Risk

### `youtube_explode_dart` fork (commit-pinned)

- Risk: `sheikhhaziq/youtube_explode_dart.git @ 0dc5514` — fork, no version, no upstream sync. YouTube breaks client APIs every few months. Fork may lag upstream fixes.
- Impact: YouTube search, streaming, and downloading all break if fork is stale. 3 of the app's 5 sources rely on it indirectly (YouTube + 4read which sometimes embeds YT).
- Migration plan: Track upstream `youtube_explode_dart` on pub.dev. Document why the fork exists (likely a patch not yet merged upstream). Test upstream as drop-in replacement quarterly. If fork is abandoned, fork-from-upstream with a clear `CHANGES.md`.

### `just_audio` fork (commit-pinned)

- Risk: `sagarchaulagai/just_audio.git @ a6f8db8` — fork of `just_audio`. Upstream is `^0.0.1-beta.20` on pub.dev, actively maintained. Fork reason undocumented.
- Impact: Misses upstream bugfixes (Android 14 media session, ExoPlayer updates). Audio playback is core functionality.
- Migration plan: Diff fork against upstream at the pinned commit. Document the patch. If the patch is merged upstream or no longer needed, switch to pub.dev version. If still needed, maintain a `PATCH.md` and rebase quarterly.

### `flutter_media_metadata` fork (commit-pinned)

- Risk: `sagarchaulagai/flutter_media_metadata.git @ 7666c7b` — fork. Upstream last published 2023; may be stale itself.
- Impact: Local audiobook metadata extraction (`media_helper.dart:5`) breaks if fork has Android-specific regressions.
- Migration plan: Verify fork patch is still needed on current Android versions. Consider migrating to `audiotagger` or `on_audio_query` if upstream is dead.

### `saf` fork (commit-pinned)

- Risk: `sagarchaulagai/saf.git @ d0ecbf9` — Storage Access Framework wrapper. Upstream status unknown.
- Impact: Local file scanning (`media_helper.dart:8`) depends on it. Android scoped-storage changes may require updates.
- Migration plan: Audit whether `saf` is still needed — Android 13+ media access via `READ_MEDIA_AUDIO` may suffice. If keeping, document fork patch.

### Hive v2 (maintainer-archived)

- Risk: `hive: ^2.2.3` + `hive_flutter: ^1.1.0`. Hive v2 maintainer has archived the repo in favor of `isar` / `hive_ce` (community fork). No new patches for v2.
- Impact: No security fixes for Hive itself. Type adapter codegen (`hive_generator: ^2.0.1` in dev deps) is unused — no `.g.dart` files in repo.
- Migration plan: Evaluate `hive_ce` (community fork, drop-in compatible) as a low-risk migration. Long-term, consider `isar` for typed queries if box count grows. Do not invest in Hive v2 adapter codegen now — migrate away instead.

## Missing Critical Features

### No crash reporting / error tracking in production

- Problem: `AppLogger` writes to a local file only. No Sentry, Crashlytics, or equivalent. Production crashes are invisible to the developer unless the user manually sends the log file.
- Blocks: Cannot prioritize fixes by crash frequency. Cannot detect regressions post-release.
- Fix: Integrate `sentry_flutter` (or `firebase_crashlytics`). Wire `Sentry.captureException` into `AppLogger.error`. Add user consent opt-in in Settings. Respect `kDebugMode` to avoid dev noise.

### No retry / circuit breaker on source APIs

- Problem: Archive.org throws on non-200 (`archive_api.dart:1798`). 4read/knigavuhe/soundbooks return `[]` on parse failure. YouTube streaming retries (`stream_client.dart:184-203`) but search does not. No exponential backoff, no circuit breaker, no cached-failure-with-TTL.
- Blocks: Transient network errors surface as "no results" with no retry. User must manually re-search.
- Fix: Add a `retry<E>(Future<E> Function(), {int maxRetries, Duration backoff})` helper. Wrap each source's fetch in it. Cache failures for 30s to avoid hammering a down service.

### No YouTube download resume after app kill

- Problem: `_activeDownloads` is in-memory. YouTube chunked downloads (`download_manager.dart:122-232`) write to a temp file but don't persist byte-offset. App kill mid-download → partial file + no resume button. `cleanStaleStatuses()` at startup may even delete the partial.
- Blocks: Large YouTube audiobooks cannot be downloaded reliably on flaky connections.
- Fix: Persist `receivedBytesForFile` per `task_<id>-<i>-<title>` to `download_status_box`. On app restart, if status is `isDownloading` but `_activeDownloads` is empty, offer resume. Or switch YouTube downloads to `background_downloader` (already a dep) which handles OS-level resume.

### No user-facing data export/import

- Problem: `UpdateDataBackupService` creates an internal pre-update backup, but users cannot export favorites, history, bookmarks, or listening stats. Uninstall = total loss (README line 43 acknowledges).
- Blocks: Users cannot migrate devices or back up their library manually.
- Fix: Add "Export library" in Settings → writes a JSON file to user-chosen location (`file_picker` already a dep). Add "Import library" that merges into boxes with conflict resolution (newest `lastModified` wins).

## Test Coverage Gaps

### Core search and download paths untested

- What's not tested: `archive_api.dart` (2022 lines, all LibriVox/Archive.org search + language filtering + genre subject building), `download_manager.dart` (529 lines, download state machine, cleanup, cancel, pause/resume), `search_bloc.dart` (461 lines, multi-source aggregation + pagination).
- Files: `lib/resources/archive_api.dart`, `lib/resources/services/download/download_manager.dart`, `lib/screens/search/bloc/search_bloc.dart`
- Risk: Any change to Archive.org URL format, download status schema, or search merge logic breaks silently. The 9 existing test files (1498 lines total) cover 4read/soundbooks details, playback trust, resume, source error mapping, settings button, app shell — none cover the primary search→details→play flow.
- Priority: High. Add `test/archive_api_test.dart` with mocked `http.Client` (use `http_mock_adapter` or `MockClient`). Add `test/download_manager_test.dart` with a fake `FileDownloader`. Add `test/search_bloc_test.dart` with stubbed source services.

### All HTML scrapers lack fixture-based contract tests

- What's not tested: `four_read_search_service`, `four_read_page_service`, `knigavuhe_search_service`, `knigavuhe_list_service`, `knigavuhe_detail_service`, `soundbooks_list_service`, `soundbooks_search_service`. Only `soundbooks_detail_service` is partially tested (`soundbooks_test.dart` 291L).
- Files: `lib/resources/services/four_read/*.dart`, `lib/resources/services/knigavuhe/*.dart`, `lib/resources/services/soundbooks/*_list_service.dart`, `lib/resources/services/soundbooks/*_search_service.dart`
- Risk: Site HTML changes break parsing silently (services return `[]`). No CI signal until users report "no results".
- Priority: High. Capture one HTML fixture per service per page type (list, search, detail). Commit to `test/fixtures/`. Add a test per fixture that asserts the parser extracts expected fields. Re-capture fixtures quarterly or when a service breaks.

### `chapter_parser.dart` binary parsing untested

- What's not tested: ID3v2 CHAP frame parsing, MP4 `chpl` atom parsing, MP4 tx3g chapter track extraction. 668 lines of byte-offset arithmetic with no tests.
- Files: `lib/resources/services/local/chapter_parser.dart`
- Risk: A malformed MP3/M4B (truncated tag, bad syncsafe int) could throw or return wrong chapter offsets. No regression net.
- Priority: Medium. Add `test/chapter_parser_test.dart` with small fixture MP3/M4B files (or synthetic byte arrays) covering: valid CHAP, missing CHAP, Nero chpl, tx3g track, truncated file, non-audio file.

### `AudioHandlerProvider` cold-start race untested

- What's not tested: The window between `runApp()` and `AudioService.init` completion where `audioHandler` returns the throwaway `MyAudioHandler`.
- Files: `lib/resources/services/audio_handler_provider.dart`, `lib/main.dart:42-66`
- Risk: Any new code that calls `audioHandler` in `initState` of a top-level widget may hit the throwaway. No test asserts the contract.
- Priority: Medium. Add a test that constructs `AudioHandlerProvider`, accesses `audioHandler` before `initialize()`, and asserts either a clear error or a no-op stub (depending on the chosen fix).

### `cover_image_service.dart` LRU cache + mapping untested

- What's not tested: `_CoverCache` LRU eviction (256 entries), `resolveCoverForLocal` 4-tier fallback (key → id → folder → embedded), `getMappedCoverImage` stale-file pruning, `cleanupUnusedCoverImages`.
- Files: `lib/resources/services/local/cover_image_service.dart`
- Risk: Cache eviction bug → repeated disk IO. Fallback order bug → wrong cover shown. Pruning bug → mappings point to deleted files forever.
- Priority: Medium. Add `test/cover_image_service_test.dart` with a temp Hive box and temp image files. Assert LRU evicts oldest, fallback order is correct, stale mappings are pruned.

### `permission_helper.dart` branch coverage

- What's not tested: Android SDK <33 vs ≥33 branching, iOS path, non-Android/iOS no-op path, dialog flow.
- Files: `lib/utils/permission_helper.dart`
- Risk: Android 12 vs 13 permission logic regression (storage vs notification). Already has commented-out dead code (youtube_webview.dart:104-110) suggesting prior permission confusion.
- Priority: Low-Medium. Add `test/permission_helper_test.dart` with mocked `DeviceInfoPlugin` and `Permission` mocks. Test each SDK branch.

---

*Concerns audit: 2026-07-13*
