# Phase 5: Cold-Restore Position-Stream Bridge Fix - Context

**Gathered:** 2026-08-03
**Status:** Ready for planning
**Source:** Code-trace investigation during milestone analysis (no discuss-phase; root cause localized)

<domain>
## Phase Boundary

Fix the position-stream bridge between the forked just_audio's deferred-load path and the UI's `ProgressBarWidget` so the progress bar reflects the restored position immediately after cold-restore + play. Single bug, single requirement (RESTORE-01). Audio already resumes at the correct position — only the UI progress bar is wrong.

</domain>

<decisions>
## Implementation Decisions

### Reproduction path (confirmed by code trace)
- **D-01:** The bug path is: app quit → position/index persisted to `playing_audiobook_details_box` (`position`, `index` keys) → app reopen → `MiniAudioPlayer.didChangeDependencies` fires one-shot restore (`_startupRestoreDone` guard) → `initSongs(files, audiobook, index, position, playImmediately: false)` → `setAudioSources(..., preload: false)` (deferred native load) → user presses play on mini bar → `MyAudioHandler.play()` → `_player.play()` triggers fork's deferred native load → `initialSeekValues` applied (audio correct) → **progress bar shows 0:00 / doesn't advance**.
- **D-02:** The progress bar widget is `ProgressBarWidget` (`lib/screens/audiobook_player/widgets/progress_bar_widget.dart`), a `StreamBuilder<PositionData>` bound to `audioHandler.getPositionStream()`.
- **D-03:** `getPositionStream()` (`lib/resources/services/my_audio_handler.dart:785`) is `Rx.combineLatest3(positionStream, bufferedPositionStream, currentIndexStream, ...)`. `combineLatest3` emits only when ALL THREE underlying streams have emitted at least once. The `total` duration is read live from `_player.duration` (a getter) at emit time — NOT part of the stream combination.
- **D-04:** Two candidate failure mechanisms (the diagnostic task must confirm which):
  - **(a) Duration is null/zero at emit time:** `_player.duration` is `null` until the deferred native load's duration probe resolves. `getPositionStream()` falls back to metadata `durationMs` (often `null` for streaming sources), so `PositionData.duration` is `Duration.zero`. `ProgressBarWidget` renders `total: Duration.zero` → bar can't show progress (division by zero / full bar).
  - **(b) `combineLatest3` never re-fires after deferred load:** If one of the three underlying streams doesn't re-emit after the deferred load resolves the position, the combined stream is stuck at its last value (or never fires if the widget subscribed fresh). The `ProgressBarWidget` creates a new `getPositionStream()` on each `build`, so a fresh `Rx.combineLatest3` may wait for all three to emit fresh values.

### Locked constraints (must NOT break)
- **D-05:** The `playImmediately: false` invariant — "NO seek before deferred load" — is protected by `playback_trust_test.dart` (test at line 244, "initSongs(playImmediately:false) does NOT seek before deferred load (forked just_audio regression)"). The fork's `seek()` unconditionally wipes `initialSeekValues`; a seek before the deferred load makes `play()` fall back to index 0 / position 0. The fix MUST NOT add a seek in the `playImmediately: false` path.
- **D-06:** The v1.0 Phase 3 fix (`await ProcessingState.ready` before `play()`) stays intact. The fix layer is in `getPositionStream()` / the position-stream bridge, not in the play sequence.
- **D-07:** No new dependencies (convention from PROJECT.md Constraints).

### Fix layer (locked)
- **D-08:** The fix lives in the position-stream bridge (`getPositionStream()` and/or the `play()` path that must re-emit position/duration to the UI after the deferred load resolves), NOT in the play-init sequence (that was v1.0's scope) and NOT in the persistence layer (position is already correct on the native side — audio proves it).

### Diagnostic-first approach
- **D-09:** Like v1.0 Phase 1, the plan's first task is a diagnostic that confirms which of (a) or (b) [or both] is the actual mechanism before the fix is written. The FakePlaybackEngine currently masks the bug (see D-10); the diagnostic must surface the real behavior, not the fake's.

### Test infrastructure consideration
- **D-10:** `FakePlaybackEngine.setAudioSources` (test line ~748) sets `position = initialPosition` AND emits `positions.add(initialPosition)` synchronously — so its `positionStream` always reflects the restored position immediately. This means the existing test suite would NOT catch the real bug: the forked just_audio with `preload: false` does NOT emit the restored position on `positionStream` until the deferred native load resolves. The regression test must extend `FakePlaybackEngine` (or add a new fake mode) to simulate the deferred-load position-emission gap: `setAudioSources` with `preload: false` should NOT immediately emit the position; instead `play()` should trigger the position emission (mirroring the fork's deferred-load semantics).

### Claude's Discretion
- Exact fix mechanism within `getPositionStream()` / `play()` (e.g., explicitly re-seeding position+duration into a `BehaviorSubject`-backed stream after the deferred load resolves, vs. using `Rx.startWith` / `rxdart` transformers, vs. a post-load broadcast). Must be minimal and not change the forked just_audio package itself.
- Whether to also handle the duration-fallback (D-04a) within the same fix or narrow to the confirmed mechanism.

</decisions>

<specifics>
## Specific Ideas

- The `getPositionStream()` `combineLatest3` + live `_player.duration` getter pattern is the central suspect. A minimal fix likely ensures the combined stream emits a non-zero position AND non-zero duration within a bounded window after the deferred load resolves.
- The regression test should assert: after `restoreIfNeeded()` (or `initSongs(playImmediately: false)`) + `play()`, `getPositionStream()` emits a `PositionData` with `position > Duration.zero` (matching the saved position) and `duration > Duration.zero` within a bounded window (e.g., 1 second / a few stream emissions).

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Position-stream bridge (the fix surface)
- `lib/resources/services/my_audio_handler.dart` §785-811 — `getPositionStream()` implementation (`Rx.combineLatest3` + live `_player.duration` getter)
- `lib/resources/services/my_audio_handler.dart` §1021 — `PositionData` class
- `lib/resources/services/my_audio_handler.dart` §848-857 — `play()` override (triggers deferred load; cold-restore entry point for the bug)
- `lib/resources/services/my_audio_handler.dart` §279-283 — `restoreIfNeeded()` (cold-start restore, silent)
- `lib/resources/services/my_audio_handler.dart` §813-837 — `_restoreQueueFromBoxIfEmpty()` (reads Hive, calls initSongs)
- `lib/resources/services/my_audio_handler.dart` §417-623 — `initSongs()` (full lifecycle; the `playImmediately: false` deferred-load path at §584-590)

### UI consumer (the symptom surface)
- `lib/screens/audiobook_player/widgets/progress_bar_widget.dart` — `ProgressBarWidget`, `StreamBuilder<PositionData>` → `audio_video_progress_bar`'s `ProgressBar` (renders `progress`/`total`/`buffered`)
- `lib/widgets/mini_audio_player.dart` §50-100 — one-shot cold-start restore (`_startupRestoreDone`) calling `initSongs(playImmediately: false)`
- `lib/screens/audiobook_player/audiobook_player.dart` §77-107 — `AudiobookPlayer.didChangeDependencies` (calls `restoreIfNeeded()` if handler empty)

### Invariants that MUST stay green
- `test/playback_trust_test.dart` §211-242 — "restores queue from Hive without starting real playback"
- `test/playback_trust_test.dart` §244-290 — "initSongs(playImmediately:false) does NOT seek before deferred load (forked just_audio regression)" — **the D-05 no-seek invariant**
- `test/playback_trust_test.dart` §440-490 — gen-discard / stale-init finally invariant
- `test/playback_trust_test.dart` §600-700 — `FakePlaybackEngine` implementation (note: `setAudioSources` emits position synchronously — masks the bug; see D-10)

### Forked just_audio semantics (pinned, do not modify)
- `~/.pub-cache/git/just_audio-a6f8db8.../just_audio/lib/just_audio.dart` — fork ref `a6f8db8`; `_pluginLoadRequest.initialSeekValues` applied on deferred load; `seek()` wipes `initialSeekValues` pre-load

### Milestone / requirements context
- `.planning/REQUIREMENTS.md` — RESTORE-01 (the single requirement)
- `.planning/ROADMAP.md` — Phase 5 success criteria (4 criteria, all must hold)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FakePlaybackEngine` (test line ~600) — injectable `PlaybackEngine` fake; the natural extension point for a regression test that simulates the deferred-load position gap. Add a "deferred" mode where `setAudioSources(preload:false)` does NOT emit position, and `play()` triggers the emission.
- `PlaybackEngine` abstract (`lib/resources/services/my_audio_handler.dart:40`) + `JustAudioPlaybackEngine` (`:79`) — testable seam; tests inject the fake, production uses the real engine.
- `PositionData` (`my_audio_handler.dart:1021`) — the DTO the UI binds to; fix target if the bridge changes the data shape.

### Established Patterns
- v1.0 Phase 1 diagnostic pattern: FakePlaybackEngine extended to simulate the race (`processingState = loading` + deferred ready emission), then a test asserts the invariant before the fix is written. This phase's diagnostic should follow the same shape (extend fake → assert gap → fix → assert fixed).
- `Either<String, T>` error handling + SnackBar surfacing (convention) — if the fix needs to surface a failure, follow the v1.0 ERR-01/02 pattern. (Likely not needed for a stream-bridge fix, but available.)

### Integration Points
- `ProgressBarWidget` is the ONLY consumer of `getPositionStream()` today (`grep` confirms). Changes to `getPositionStream()`'s output shape or emission contract propagate to exactly one widget.
- The mini-player (`mini_audio_player.dart`) does NOT bind to `getPositionStream()` — it uses `playbackState` + `mediaItem` streams. So the fix is isolated to the full-screen player's progress bar.

</code_context>

<deferred>
## Deferred Ideas

- RESTORE-02 (duration not showing for streaming sources where the native probe hasn't returned) — separate symptom, tracked as a Future Requirement in REQUIREMENTS.md. The D-04a mechanism may overlap, but if the fix naturally covers it, great; if not, do NOT expand scope.
- RESTORE-03 (mini-player + notification position sync) — not reported, deferred.
- Cross-source restore hardening beyond the progress-bar symptom — explicitly out of scope (minimal milestone).

</deferred>

---

*Phase: 05-cold-restore-position-stream-bridge-fix*
*Context gathered: 2026-08-03 via code-trace investigation*
