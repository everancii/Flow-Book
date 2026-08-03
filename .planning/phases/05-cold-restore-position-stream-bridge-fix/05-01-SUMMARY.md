---
phase: 05-cold-restore-position-stream-bridge-fix
plan: 01
subsystem: testing
tags: [flutter, just_audio, rxdart, audio-playback, position-stream, deferred-load, tdd]

# Dependency graph
requires:
  - phase: 04-call-site-consistency-cross-source-verification
    provides: Stable shared initSongs/play()/getPositionStream() code path (v1.0 complete)
provides:
  - Position-stream bridge that emits restored position + non-zero duration after cold-restore + play
  - FakePlaybackEngine deferred-load mode mirroring forked just_audio preload:false semantics
  - RESTORE-01 regression test (RED→GREEN spec)
affects: [v1.1-release, uat-smoke, restore-position-stream]

# Tech tracking
tech-stack:
  added: []  # rxdart (Rx.startWith) was already imported at my_audio_handler.dart:17 — no new dependency (D-07)
  patterns:
    - "Rx.startWith seed on combineLatest3 upstreams to force fresh-subscription emission"
    - "PlaybackEngine.emitPositionState() hook for post-deferred-load stream re-nudge"
    - "FakePlaybackEngine deferred-load mode mirroring fork preload:false semantics"

key-files:
  created: []
  modified:
    - lib/resources/services/my_audio_handler.dart
    - test/playback_trust_test.dart

key-decisions:
  - "D-08 fix layer: position-stream bridge (getPositionStream + play), NOT the initSongs play sequence (D-06) and NOT the forked just_audio package"
  - "Root cause confirmed as BOTH D-04a and D-04b: combineLatest3 never fires on a fresh subscription after the deferred load (D-04b), AND _player.duration is null at emit time (D-04a)"
  - "Fix uses Rx.startWith (rxdart already imported) to seed each combineLatest3 upstream — zero new dependencies (D-07)"
  - "play() calls _player.emitPositionState() (stream nudge, NOT a seek) so existing subscriptions also re-fire — D-05 no-seek invariant preserved"

patterns-established:
  - "Deferred-load fake mode: FakePlaybackEngine mirrors fork preload:false by suppressing positions.add + nulling duration in setAudioSources, resolving both in play()"
  - "Position-stream bridge seeding: combineLatest3 upstreams wrapped in .startWith(currentValue) so fresh subscriptions emit immediately"

requirements-completed: [RESTORE-01]

# Coverage metadata — one entry per shipped deliverable
coverage:
  - id: D1
    description: "getPositionStream() emits the restored saved position (> Duration.zero) after restoreIfNeeded() + play() within a bounded window"
    requirement: "RESTORE-01"
    verification:
      - kind: unit
        ref: "test/playback_trust_test.dart#cold-restore + play emits restored position and non-zero duration on getPositionStream (deferred-load regression)"
        status: pass
    human_judgment: false
  - id: D2
    description: "getPositionStream() emits a non-zero duration after restoreIfNeeded() + play() (D-04a duration-probe-lag branch covered)"
    requirement: "RESTORE-01"
    verification:
      - kind: unit
        ref: "test/playback_trust_test.dart#cold-restore + play emits restored position and non-zero duration on getPositionStream (deferred-load regression)"
        status: pass
    human_judgment: false
  - id: D3
    description: "D-05 no-seek invariant preserved in the playImmediately:false deferred-load path (seekCalls empty before play)"
    requirement: "RESTORE-01"
    verification:
      - kind: unit
        ref: "test/playback_trust_test.dart#initSongs(playImmediately:false) does NOT seek before deferred load (forked just_audio regression)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Full playback_trust_test.dart suite stays green (18 pre-existing + 1 new regression test)"
    requirement: "RESTORE-01"
    verification:
      - kind: unit
        ref: "flutter test test/playback_trust_test.dart (19/19 pass)"
        status: pass
    human_judgment: false
  - id: D5
    description: "On-device: after quitting and returning to the last-played book, pressing play shows the progress bar at the saved position (not 0:00) within 1 second, across all sources (LibriVox, YouTube, 4read, knigavuhe, Sound-Books, local/download); total duration + remaining-time label render non-zero; seeking still works (no jump-back, no stuck thumb)"
    requirement: "RESTORE-01"
    verification: []
    human_judgment: true
    rationale: "Multi-source on-device playback behavior cannot be asserted in the unit-test fake; the regression test proves the bridge contract but the end-to-end render across all 5 sources + local requires the v1.1 UAT smoke (mirrors v1.0's 04-UAT.md pattern). Roadmap success criteria 1-3 are structural-guaranteed by the fix but need on-device confirmation."

# Metrics
duration: ~25min
completed: 2026-08-03
status: complete
---

# Phase 5 Plan 01: Cold-Restore Position-Stream Bridge Fix Summary

**Position-stream bridge fix using Rx.startWith seeds + a post-play emitPositionState() nudge so the progress bar reflects the restored position and a non-zero duration immediately after cold-restore + play — rxdart already imported, no new dependency, no seek in the deferred-load path.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-08-03
- **Completed:** 2026-08-03
- **Tasks:** 3 (TDD: RED → GREEN → REGRESSION)
- **Files modified:** 2

## Accomplishments
- Confirmed the cold-restore progress-bar root cause is **both** D-04a (duration null at emit time) AND D-04b (combineLatest3 never fires on a fresh subscription after the deferred load) — surfaced via a new FakePlaybackEngine deferred-load mode that mirrors the forked just_audio `preload:false` semantics (CONTEXT D-10, fork ref a6f8db8).
- Fixed the position-stream bridge (D-08 layer): `getPositionStream()` now seeds each `Rx.combineLatest3` upstream via `Rx.startWith(currentValue)` so any fresh subscription emits immediately with the restored position/buffered/currentIndex; `play()` calls `_player.emitPositionState()` (a stream nudge, NOT a seek) so existing subscriptions also re-fire after the deferred load resolves.
- Added a regression test proving RESTORE-01 at the unit level: after `restoreIfNeeded()` + `play()`, `getPositionStream()` emits a `PositionData` with `position == 123456ms` (the saved position) and `duration > Duration.zero` within a bounded window.
- Preserved every v1.0 invariant: the D-05 no-seek test, the restore-without-playback test, the playImmediately:true ready-driven seek test, the skipToQueueItem test, and the gen-discard/stale-init invariants all pass byte-for-byte unchanged.

## Task Commits

Each task was committed atomically (TDD RED → GREEN → REGRESSION):

1. **Task 1 (RED): Extend FakePlaybackEngine with deferred-load mode + failing regression test** — `75f63cf` (test)
2. **Task 2 (GREEN): Fix position-stream bridge in my_audio_handler.dart** — `b4b0a8e` (feat)
3. **Task 3 (REGRESSION): Expand deferred-load doc comment + confirm full suite green** — `5fdde9f` (docs)

## Files Created/Modified
- `test/playback_trust_test.dart` — FakePlaybackEngine gains a `deferPositionEmission` deferred-load mode (field + `setAudioSources` suppression when `preload:false` + `play()` resolution + `emitPositionState()` override) with a doc comment citing CONTEXT D-10 / fork ref a6f8db8; new regression test 'cold-restore + play emits restored position and non-zero duration on getPositionStream (deferred-load regression)' added to the fake-engine group.
- `lib/resources/services/my_audio_handler.dart` — `getPositionStream()` wraps each `combineLatest3` upstream in `Rx.startWith(_player.<current>)` so fresh subscriptions emit immediately; `play()` override calls `_player.emitPositionState()` after `_player.play()` resolves the deferred load; new `PlaybackEngine.emitPositionState()` abstract method (documented no-op in `JustAudioPlaybackEngine`, drives broadcast controllers in `FakePlaybackEngine`); duration fallback in getPositionStream already covered D-04a via the existing metaDuration fallback (unchanged).

## Decisions Made
- **Fix mechanism (D-08, Claude's discretion per CONTEXT.md):** Chose `Rx.startWith` seeds on the `combineLatest3` upstreams + an `emitPositionState()` hook called from `play()`. Rationale: (1) rxdart was already imported (§17) — zero new dependencies (D-07); (2) the seed closes the D-04b fresh-subscription gap deterministically (every fresh subscription emits immediately); (3) `emitPositionState()` closes the existing-subscription gap without a seek (D-05); (4) the return type stays `Stream<PositionData>` so `ProgressBarWidget` is unchanged.
- **emitPositionState() on JustAudioPlaybackEngine is a documented no-op:** The real `just_audio` re-emits position/bufferedPosition on its periodic streams (~200ms) after the deferred load resolves; the production D-04b gap is the fresh-subscription case, which the `Rx.startWith` seeds close. Pushing into the real player's internal sinks is not exposed by just_audio's API and is unnecessary.
- **Diagnostic result (Task 1):** The RED test failed with `getPositionStream must emit` (null — the `TimeoutException` path), confirming D-04b as the primary mechanism in the fake. The D-04a duration-lag branch is structurally covered by the existing metaDuration fallback in getPositionStream and by the fake nulling duration during the deferred window.

## Deviations from Plan

None - plan executed exactly as written. The plan granted Claude discretion on the exact fix mechanism within the position-stream bridge layer (CONTEXT.md "Claude's Discretion"); the chosen `Rx.startWith` + `emitPositionState()` approach satisfies all five constraints the plan listed (no new dependency, no seek in playImmediately:false, no fork modification, await-ready gate intact, return type unchanged).

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- RESTORE-01 is delivered at the unit-test level: the regression test proves the bridge contract.
- The full `playback_trust_test.dart` suite is green (19/19), preserving all v1.0 invariants.
- **Remaining for v1.1 release:** the on-device UAT smoke (roadmap success criteria 1-3 across all 5 sources + local/download) is captured separately as the v1.1 UAT, mirroring v1.0's `04-UAT.md` pattern. Criterion 4 (suite green) is already satisfied.
- Out of scope (deferred per REQUIREMENTS.md): RESTORE-02 (streaming duration probe), RESTORE-03 (mini-player sync).

---
*Phase: 05-cold-restore-position-stream-bridge-fix*
*Completed: 2026-08-03*
