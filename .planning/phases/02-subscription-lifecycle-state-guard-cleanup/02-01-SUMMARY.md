---
phase: "02"
plan: "01"
subsystem: "playback-init"
tags: [refactor, subscription-lifecycle, state-guard, gen-guard, leak-fix]
requires: [phase-01]
provides: [gen-guarded-finally]
affects: [phase-03]
tech-stack:
  added: []
  patterns: [gen-guard-finally, tracked-StreamSubscription]
key-files:
  created: []
  modified:
    - lib/resources/services/my_audio_handler.dart
    - test/playback_trust_test.dart
decisions:
  - D-01: Gen-guard finally block so stale init can't clobber _isReinitializing
  - D-03/D-04: Tracked StreamSubscription replaces fire-and-forget Future.delayed cancel
  - D-05: Cancel at three sites — initSongs re-entry, stop(), and finally
  - D-07: Remove orphan processingStateStream.listen (log-only, never cancelled)
  - D-08: Preserve [DIAG] diagnostic checkpoints
  - D-09: Add 3 refactor tests for gen-guard, tracked-sub, and orphan teardown
metrics:
  duration: 3 min
  completed_at: "2026-07-15T01:58:58Z"
  tasks: 2
  files: 2
status: complete
---

# Phase 02 Plan 01: Subscription Lifecycle + State-Guard Cleanup Summary

Commit `351a75d` addressed three requirements (PLAY-07, PLAY-08, PLAY-09) with pure refactors inside `MyAudioHandler.initSongs`. Zero user-visible behavior change.

## What Was Built

### PLAY-07: Gen-Guard on Finally Block
The `finally` block at end of `initSongs` now checks `if (myGen == _initGen)` before clearing `_isReinitializing`. Only the active generation clears the flag — a stale init (superseded by a newer `++_initGen`) skips the clear, preventing clobber of the newer init's flag.

### PLAY-08: Tracked StreamSubscription
Added `StreamSubscription<ProcessingState>? _initSettleSub` field. The processingStateStream listener (with ready re-trigger, idle recovery, 30s buffering-skip behaviors) was assigned to this tracked field instead of a local `sub` variable. Cancellation occurs at three sites:
1. Top of next `initSongs` — cancels previous init's listener on re-entry
2. `stop()` — full teardown
3. Guarded `finally` block — cleanup on normal completion

The fire-and-forget `Future.delayed(const Duration(seconds: 60), () => sub.cancel())` was deleted.

### PLAY-09: Orphan Listener Removal
Removed the standalone `_player.processingStateStream.listen((state) { AppLogger.debug(...); })` that logged only, was never cancelled, and leaked one subscription per `initSongs` call.

### Tests Added
Three refactor tests in `test/playback_trust_test.dart` `MyAudioHandler with fake playback engine` group:
1. **Gen-discard clobber protection** — verifies stale init's finally doesn't clobber newer init's `_isReinitializing`
2. **Tracked-sub cancellation on re-entry** — verifies only one active listener after rapid re-init
3. **Stop cancels all listeners** — verifies `stop()` tears down all processingStateStream listeners

Suite result at commit: +13 ~1 -2 (2 pre-existing chapter-metadata failures unchanged).

## Post-Phase Evolution

> **Phase 03** (commit `a863c64`, "ready-before-play fix") rewrote the `playImmediately` block to use `await _player.processingStateStream.firstWhere((s) => s == ProcessingState.ready).timeout(_readyTimeout)`. This replaced the entire processingStateStream listener that `_initSettleSub` was tracking with a one-shot `firstWhere` pattern.

**Consequences:**
- `_initSettleSub` field: **removed** by Phase 03 (no longer needed — `firstWhere` is one-shot, no subscription to track)
- Cancellation sites (re-entry, stop, finally): **removed** by Phase 03
- Tests 2 (tracked-sub cancellation) and 3 (stop teardown): **removed** by Phase 03 (tested a mechanism that no longer exists)
- Test 1 (gen-guard finally): **preserved** and passes on HEAD
- `[DIAG]` logs: **removed** in Phase 03 restructuring (superseded by new diagnostic approach)

## Current State (HEAD)

| Deliverable | Status |
|---|---|
| Gen-guarded finally (PLAY-07) | **PRESENT** in HEAD code |
| `_initSettleSub` field | Absent (superseded by Phase 03) |
| Fire-and-forget Future.delayed(60s) cancel | Absent (removed, not reintroduced) |
| Orphan processingStateStream.listen | Absent (removed, not reintroduced) |
| Test: stale init finally guard | **PRESENT** and **PASSING** |
| Test: tracked-sub cancellation | Absent (obsoleted by Phase 03) |
| Test: stop cancels listeners | Absent (obsoleted by Phase 03) |
| Full test suite | **16/16 passing**, zero failures |

## Deviations from Plan

### Superseded by Later Phases

**1. [Rule 4 - Architectural] _initSettleSub field removed by Phase 03**
- **Found during:** Phase 03 execution
- **Issue:** Phase 03's `firstWhere` + `await` pattern replaced the entire processingStateStream listener block, making `_initSettleSub` unnecessary
- **Resolution:** Phase 03 legitimately removed the field. This is correct — the subscription tracking mechanism was a precondition step that Phase 03's cleaner architecture rendered obsolete.

**2. [Rule 4 - Architectural] Tests 2 and 3 obsoleted**
- **Found during:** Phase 03 execution
- **Issue:** Tests for `_initSettleSub` cancellation behavior cannot pass when the tracked subscription mechanism no longer exists
- **Resolution:** Phase 03 removed tests 2 and 3. Test 1 (gen-guard finally) survives and continues to verify PLAY-07's core invariant.

**3. [Phase 03 decision] [DIAG] logs removed**
- **Found during:** Phase 03 execution
- **Issue:** D-08 said to preserve [DIAG] logs, but Phase 03's architectural refactor removed the code blocks containing them
- **Resolution:** Phase 03 replaced diagnostic checkpoints with its own instrumentation. This was a deliberate decision — the [DIAG] logs were Phase 1's temporary debugging aid, and Phase 03's restructured code needed different instrumentation.

### None - plan executed exactly as written at commit 351a75d.
All subsequent changes were deliberate Phase 03/04 architectural decisions, not deviations from Phase 02's execution.

## Threat Flags

None — pure refactors in existing code paths. No new network endpoints, auth paths, file access patterns, or trust-boundary schema changes.

## Known Stubs

None — no hardcoded empty values, placeholder text, or un-wired components introduced.

## Self-Check: PASSED

- [x] Commit `351a75d` exists in git history
- [x] Gen-guarded finally block present in HEAD code (line 610)
- [x] Fire-and-forget `Future.delayed(60s)` absent from HEAD
- [x] Orphan `processingStateStream.listen` absent from HEAD
- [x] Test "stale init finally does not clobber" present and passes
- [x] Full test suite: 16/16 passing, zero failures
- [x] SUMMARY.md created at correct path
