# Phase 3: Ready-Before-Play Fix - Context

**Gathered:** 2026-07-15
**Status:** Ready for planning

<domain>
## Phase Boundary

THE actual bug fix. Restructure `MyAudioHandler.initSongs` to await `ProcessingState.ready` before calling `_player.play()`, with a bounded timeout and error surfacing. After this phase, Sound-Books books auto-play on open — matching all other sources.

Seven requirements (PLAY-01, PLAY-02, PLAY-04, PLAY-05, PLAY-06, ERR-01, ERR-02):
- Replace fire-and-forget `_player.play()` with an `await processingStateStream.firstWhere(ready).timeout(10s)` gate
- Make the big play button call site consistent with `_autoPlay`/`_playChapter`
- Surface `PlayerException` / `TimeoutException` as user-visible SnackBars
- Guard all call sites with `if (!mounted) return` after awaits
- Remove the Phase 1 [DIAG] diagnostic scaffolding

**Not in scope:** Cross-source regression smoke (Phase 4), new automated test invariants (Phase 4 TEST-02/TEST-03), loading-spinner UI (v2 deferred).

</domain>

<decisions>
## Implementation Decisions

### Await Mechanism Design (PLAY-05)
- **D-01:** Replace the fire-and-forget `_player.play()` + `_initSettleSub` re-trigger listener with:
  ```dart
  await _player.processingStateStream
      .firstWhere((s) => s == ProcessingState.ready)
      .timeout(const Duration(seconds: 10));
  ```
  BehaviorSubject replays the last value to new subscribers, so known-duration sources (LibriVox, YouTube, knigavuhe, 4read) short-circuit synchronously — zero added latency. Sound-Books (unknown duration → loading → ready transition) waits until ready or 10s timeout.
- **D-02:** After the await resolves, check `if (myGen != _initGen) return;` before calling `_player.play()`. A stale init (superseded during the await) must not play.
- **D-03:** The `_initSettleSub` listener is **REMOVED entirely**. The await replaces its ready re-trigger purpose. All three behaviors it carried are eliminated:
  - Ready re-trigger → replaced by the await (play only fires after ready)
  - 30s buffering-skip → removed (the 10s timeout supersedes it; if ready doesn't arrive in 10s, the TimeoutException surfaces an error)
  - Idle recovery → removed (was a workaround for the same root cause — play() during non-ready state)
- **D-04:** The `_initSettleSub` field, its cancel sites (top of initSongs, stop(), finally), and the `bufferingStarted` local are ALL removed since the listener no longer exists. Phase 2's tracking infrastructure is cleaned up.

### Timeout + Error Behavior (PLAY-06)
- **D-05:** 10-second bounded timeout via `.timeout(const Duration(seconds: 10))` on the `firstWhere` future. Hardcoded as a top-level or static const. Matches Phase 1 probe-duration findings.
- **D-06:** On timeout: log via `AppLogger.error('initSongs: timed out waiting for ProcessingState.ready after 10s')`, then rethrow the `TimeoutException`. The caller (`_autoPlay` / `_playChapter` / big play button) catches it and shows the "Unable to start playback" SnackBar.

### Call-Site Consistency (PLAY-04)
- **D-07:** **Big play button** (`audiobook_details.dart:527-544`): change to `await initSongs(..., playImmediately: false)` then `await play()`. Wrap in a try/catch with `if (!mounted) return` + SnackBar. This makes the button explicit: load first (no internal play), then explicitly call play() after.
- **D-08:** **`_autoPlay`** (line 131) and **`_playChapter`** (line 82): remove the redundant `await audioHandlerProvider.audioHandler.play()` calls. With the new await-ready mechanism inside `initSongs` (when `playImmediately: true`), `initSongs` handles play internally — the separate `play()` calls are no-ops.
- **D-09:** `_autoPlay` and `_playChapter` continue using `playImmediately: true` (the default) — `initSongs` loads, awaits ready, then plays internally.

### Error Surfacing + Mounted Guards (ERR-01, ERR-02)
- **D-10:** Keep the existing Phase 1 try/catch around `setAudioSources` that **rethrows** after logging. The caller catches the exception (whether `PlayerException` from a failed duration probe, or `TimeoutException` from the ready-await) and shows the SnackBar. No error-state stream or notifier needed.
- **D-11:** All three call sites get the same catch-block pattern (matching `_playChapter`'s existing pattern at lines 84-91):
  ```dart
  } catch (e) {
    AppLogger.debug('Error <context>: $e');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Unable to start playback. Please try again.')),
    );
  }
  ```
  - `_playChapter` (line 84-91): **already has this pattern** — no change needed.
  - `_autoPlay` (line 133-135): **upgrade** — currently only logs, needs `mounted` guard + SnackBar added.
  - Big play button (line 527-547): **new try/catch** — add the full pattern around the new `await initSongs(...) + await play()` sequence.

### Diagnostic Logs
- **D-12:** Remove ALL `[DIAG]` diagnostic checkpoints from Phase 1 (lines 542-604 in initSongs). Phase 1 verification is complete, Phase 2 preserved them, Phase 3 is THE fix. Keep the non-`[DIAG]` `AppLogger.debug` calls that existed before Phase 1 (e.g., `AppLogger.debug('initSongs: processingState=$state')` if it predates Phase 1 — check git history).

### Claude's Discretion
- Whether to extract the 10s timeout as a static const field (e.g., `static const _readyTimeout = Duration(seconds: 10);`) or inline it — pick whichever matches the file's convention.
- Whether to remove the `_waitForProcessingReady` polling method (line 690) if it becomes unused after the await-ready refactor — check if any other call site still uses it before removing.
- Exact test updates — the Phase 1 "race detector" test (currently skipped) and the "fires play() unconditionally" test both need updating to reflect the new await-ready behavior. The "unconditionally" test should become "fires play() after ready" and the skip on the race detector should be removed.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 1 Research (root-cause confirmation)
- `.planning/phases/01-diagnostic-verification-test-infrastructure/01-RESEARCH.md` — Confirms `processingStateStream` is a `BehaviorSubject<ProcessingState>.seeded(idle)` in the fork (line 135-136, 487-488). Documents the exact play() drop mechanism (audioSession.setActive fails when player isn't ready, lines 1106-1127). Critical for understanding why the await-before-play fix works.
- `.planning/phases/01-diagnostic-verification-test-infrastructure/01-PATTERNS.md` — Pattern map for initSongs + playback_trust_test.dart. Contains code conventions, gen-guard pattern, FakePlaybackEngine fields, test construction shape.

### Phase 2 Context (predecessor — infrastructure being modified)
- `.planning/phases/02-subscription-lifecycle-state-guard-cleanup/02-CONTEXT.md` — Documents the `_initSettleSub` field, its three cancel sites, and the three listener behaviors that Phase 3 will REMOVE. The gen-guard on finally (D-01) STAYS — only the listener and its cancel sites go.

### Requirements
- `.planning/REQUIREMENTS.md` §Auto-Play Reliability — PLAY-01, PLAY-02, PLAY-04. §Play-Init Sequence — PLAY-05, PLAY-06. §Error Surfacing — ERR-01, ERR-02.

### Codebase Concerns
- `.planning/codebase/CONCERNS.md` §`MyAudioHandler` 1054-line state machine — fragile-area note: "read `playback_trust_test.dart` to understand the invariants the tests enforce" before editing initSongs.

### Source Code (files being modified)
- `lib/resources/services/my_audio_handler.dart` lines 416-680 (`initSongs` — the main refactor target: await-ready gate replaces play()+listener), 690-697 (`_waitForProcessingReady` — may be removed if unused), 940-947 (`stop()` — remove `_initSettleSub?.cancel()`)
- `lib/screens/audiobook_details/audiobook_details.dart` lines 67-136 (`_playChapter` + `_autoPlay` — remove redundant play(), upgrade _autoPlay catch), 520-547 (big play button — add await + try/catch)
- `test/playback_trust_test.dart` lines 293-359 (Phase 1 tests — update "unconditionally" test, un-skip race detector test)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Gen-guard pattern** (`if (myGen != _initGen) return;`): already used at lines 526, 566, 656 (now shifted by Phase 2 edits). The await-ready gate needs the same guard AFTER the await resolves — before calling `play()`.
- **`processingStateStream`**: backed by `BehaviorSubject.seeded(idle)` in the fork. `firstWhere(ready)` replays current value synchronously. This is the key insight that makes the fix zero-latency for known-duration sources.
- **Existing try/catch around setAudioSources** (lines 565-568, added in Phase 1): rethrows after logging. Phase 3 keeps this — the rethrow propagates to the caller's catch.

### Established Patterns
- **Caller catches + SnackBar**: `_playChapter` (lines 84-91) is the canonical pattern: `catch (e) { AppLogger.debug(...); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(...); }`. Phase 3 applies this to all three call sites.
- **Gen-staleness on await**: existing pattern at line 575 (`await _waitForProcessingReady(...)` for YouTube resume) — after the await, the gen-guard `if (myGen != _initGen) return;` at line 571 protects against stale init. Phase 3's await-ready follows the same shape.

### Integration Points
- **`initSongs` play-init block** (lines 584-647): the entire `if (playImmediately) { _player.play(); ... _initSettleSub listener ... }` block is replaced by the await-ready gate + single `_player.play()`.
- **Big play button** (lines 527-544): currently fire-and-forget `initSongs(...)` without await, no play() call, no try/catch. Phase 3 wraps it in `async` try/catch with `await initSongs(playImmediately: false)` + `await play()`.
- **`_autoPlay` catch** (line 133-135): currently `catch (e) { AppLogger.debug(...); }` — no mounted guard, no SnackBar. Phase 3 upgrades to match `_playChapter`.

</code_context>

<specifics>
## Specific Ideas

- The user emphasized **zero added latency** for known-duration sources. The BehaviorSubject replay property is critical — `firstWhere(ready)` must complete synchronously when already ready. The Phase 1 research confirmed this (fork source line 135-136: `BehaviorSubject<ProcessingState>.seeded(idle).stream.distinct()`).
- The user wants the [DIAG] scaffolding fully cleaned up — Phase 3 is the fix, not a debugging phase.
- The big play button fix is intentionally explicit (`playImmediately: false` + separate `play()`) rather than relying on the internal mechanism — makes the button's intent clear and testable.

</specifics>

<deferred>
## Deferred Ideas

- Loading spinner / buffering feedback for non-YouTube sources — deferred to v2 (already in REQUIREMENTS.md v2 list)
- Unifying `_waitForProcessingReady` (poll) with the new stream-based await — if the poll method becomes unused, remove it; if other callers exist, defer unification to v2

</deferred>

---

*Phase: 3-Ready-Before-Play Fix*
*Context gathered: 2026-07-15*
