---
status: human_needed
phase: 05-cold-restore-position-stream-bridge-fix
score: 4/4
verified: 2026-08-03
source: [05-01-PLAN.md, 05-01-SUMMARY.md, 05-CONTEXT.md]
next_action: "Run the v1.1 UAT smoke (on-device) to confirm criteria 1-3 across all sources"
next_command: "/gsd:verify-work 05"
---

# Phase 5 Verification: Cold-Restore Position-Stream Bridge Fix

## Goal Achievement

**Phase Goal:** Fix the position-stream bridge between the forked just_audio's deferred-load path and the UI's `ProgressBarWidget` so the progress bar reflects the restored position immediately after cold-restore + play.

**Result:** ✅ **Achieved at the unit-test level.** The bridge contract is proven by the RESTORE-01 regression test. On-device confirmation across all sources is the remaining UAT step.

## Requirement Traceability

| Requirement | Status | Evidence |
|-------------|--------|----------|
| RESTORE-01 | ✅ Unit-proven; UAT pending | `test/playback_trust_test.dart#cold-restore + play emits restored position and non-zero duration on getPositionStream (deferred-load regression)` passes (position == 123456ms, duration > zero) |

## ROADMAP Success Criteria

### Criterion 1: Progress bar shows saved position within 1 second of playback after cold-restore
**Status:** Unit-proven (bridge contract); on-device UAT pending.
- The regression test proves `getPositionStream()` emits the saved position (`Duration(milliseconds:123456)`) after `restoreIfNeeded()` + `play()` within a bounded 1-second window.
- On-device confirmation across all sources (LibriVox, YouTube, 4read, knigavuhe, Sound-Books, local/download) requires the UAT smoke.

### Criterion 2: Total duration + remaining-time label render non-zero
**Status:** Unit-proven (bridge contract); on-device UAT pending.
- The regression test asserts `emitted.duration > Duration.zero` after cold-restore + play.
- The `getPositionStream()` duration fallback (live `_player.duration` → `metaDuration` from MediaItem extras `durationMs`) covers the D-04a probe-lag branch.
- On-device: streaming sources where the native duration probe lags still need visual confirmation.

### Criterion 3: Seek still works (no jump-back, no stuck thumb)
**Status:** Structurally guaranteed; on-device UAT pending.
- The fix ONLY adds position re-emission (`Rx.startWith` seeds + `emitPositionState()` nudge). It never removes, races, or modifies the existing seek path.
- The existing seek tests pass unchanged: `seek writes latest position` (§345), `skipToQueueItem seeks to chapter start` (§322), `initSongs(playImmediately:true) still seeks after load` (§292).
- `grep` confirms no new `seek()` call was added in any path reachable when `playImmediately` is false (Gate 4 below).

### Criterion 4: playback_trust_test.dart stays green (D-05 + restore invariants)
**Status:** ✅ Automated — PASS.
- `flutter test test/playback_trust_test.dart` → 19/19 pass (18 pre-existing + 1 new regression).
- D-05 no-seek invariant (`initSongs(playImmediately:false) does NOT seek before deferred load`) passes unchanged.
- Restore test (`restores queue from Hive without starting real playback`) passes unchanged.

## Automated Verification Gates (all PASS)

### Gate 1: Full suite green
```
$ flutter test test/playback_trust_test.dart
00:00 +19: All tests passed!
```
19 tests pass (18 pre-existing + 1 new RESTORE-01 regression test).

### Gate 2: Analyzer clean
```
$ flutter analyze lib/resources/services/my_audio_handler.dart test/playback_trust_test.dart
No issues found! (ran in 2.0s)
```

### Gate 3: Prohibition — forked just_audio package unchanged
```
$ git diff --stat 8b83c5c..HEAD -- lib/ test/ pubspec.yaml pubspec.lock
 lib/resources/services/my_audio_handler.dart | 63 +++++++++++-
 test/playback_trust_test.dart                | 139 +++++++++++++++++++++++++++
 2 files changed, 199 insertions(+), 3 deletions(-)
```
Only `my_audio_handler.dart` and `playback_trust_test.dart` changed. `pubspec.yaml` / `pubspec.lock` untouched (no new dependency — D-07). The forked just_audio package (`sagarchaulagai/just_audio.git @ a6f8db8`) is git-overridden and not tracked by this repo — zero edits.

### Gate 4: Prohibition — no new seek in the playImmediately:false path
All `_player.seek(...)` calls in `my_audio_handler.dart`:
- Line 172: `JustAudioPlaybackEngine.seek()` method body (engine delegate)
- **Line 587: `await _player.seek(...)` — INSIDE `if (playImmediately)` block (line 584)** ✓ correct
- Line 941: `MyAudioHandler.seek()` override (user seek)
- Line 948: `skipToNext` / `skipToPrevious`
- Line 973, 980: `fastForward` / `rewind`
- Line 1064: `skipToQueueItem`

The `playImmediately:false` deferred-load branch (§609+) introduces **no new seek**. The `play()` override calls `_player.emitPositionState()` — a stream nudge, NOT a seek (D-05 preserved).

### Gate 5: Invariant tests pass unchanged
- D-05 no-seek test (§244-290): assertion text and `seekCalls`-emptiness check byte-for-byte identical to pre-fix baseline → PASS
- Restore test (§211-242): `playCount == 0`, queue titles correct → PASS

## Human Verification Items (UAT)

The following require on-device testing before the phase can be marked fully complete. Captured separately as the v1.1 UAT smoke (mirrors v1.0's `04-UAT.md` pattern).

### UAT-1: Cold-restore progress bar position (all sources)
**Expected:** After quitting the app and returning to the last-played book, pressing play shows the progress bar at the saved position (not 0:00) within 1 second of playback starting — for LibriVox, YouTube, 4read, knigavuhe, Sound-Books, and local/download sources.
**How to test:** Play a book to a mid-track position → quit the app → reopen → open the full-screen player → press play → observe the progress bar thumb position within the first second.

### UAT-2: Duration + remaining-time label render non-zero
**Expected:** The total duration and "Time Remaining" label render correct non-zero values after cold-restore + play.
**How to test:** Same flow as UAT-1 → observe the duration label and remaining-time label are non-zero and match the track.

### UAT-3: Seek still works after cold-restore + play
**Expected:** Dragging the progress bar to seek still works correctly after a cold-restore + play (no jump-back to 0, no stuck thumb).
**How to test:** Same flow as UAT-1 → after playback starts, drag the thumb to a new position → release → confirm playback jumps to the new position and the thumb tracks playback smoothly.

## Coverage

All 5 SUMMARY deliverables classified:
- D1-D4: `human_judgment: false` with passing unit-test verification → auto-pass eligible
- D5 (on-device multi-source): `human_judgment: true` → requires UAT (UAT-1/2/3 above)

## Conclusion

The phase goal is achieved at the unit-test level. The RESTORE-01 bridge contract is proven by an automated regression test, all v1.0 invariants are preserved, and all prohibition gates pass. The remaining work is the on-device UAT smoke (criteria 1-3) which cannot be automated in the unit-test fake.

**Status: `human_needed`** — run `/gsd:verify-work 05` to walk through UAT-1/2/3 on-device.

---
*Phase: 05-cold-restore-position-stream-bridge-fix*
*Verified: 2026-08-03*
