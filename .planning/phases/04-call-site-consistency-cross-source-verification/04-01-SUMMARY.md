---
phase: "04"
plan: "01"
subsystem: "playback-init"
tags: [call-site-consistency, history-tap, try-catch, hive-write-ordering, uat, cross-source-smoke, sound-books, just_audio-fork]

# Dependency graph
requires:
  - phase: 03-ready-before-play-fix
    provides: "await-ready gate in initSongs (10s timeout) that makes the call awaitable and able to rethrow — the surface this phase's catch block handles"
provides:
  - "history_section.dart onTap hardened to the canonical _autoPlay pattern (async try/catch + await + mounted guard + SnackBar) — closes the last call-site consistency gap"
  - "All four Hive writes relocated before the await in the history tap (D-03 race avoidance — prevents MiniAudioPlayer.didChangeDependencies partial-box read)"
  - "All four user-facing play-init call sites now share the identical SnackBar pattern (3 in audiobook_details.dart + 1 in history_section.dart)"
  - "PLAY-03 manual smoke captured as 04-UAT.md (8-row matrix + <100ms pass bar + dead-URL error-path check)"
affects: [milestone-closeout, release-v1.3]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Race-aware Hive write ordering: all box.put() calls complete synchronously BEFORE the first await in any play-init call site (now applied to all 4 user-facing sites)"

key-files:
  created:
    - .planning/phases/04-call-site-consistency-cross-source-verification/04-UAT.md
  modified:
    - lib/screens/home/widgets/history_section.dart

key-decisions:
  - "D-01: onTap wrapped in async try/catch + await on initSongs (matches _autoPlay / _playChapter / big play button)"
  - "D-02: catch block text is byte-for-byte the canonical pattern — AppLogger.debug + if(!mounted) return + generic SnackBar ('Unable to start playback. Please try again.')"
  - "D-03: all 4 Hive writes (audiobook, audiobookFiles, index, position) moved before the await — the 2 post-initSongs writes (index, position) were safe before only because there was no await"
  - "D-04: initSongs keeps default playImmediately:true (user tapped a book — they want it to play); playImmediately not passed"
  - "D-05: mini_audio_player.dart left UNTOUCHED — startup restore is intentionally fire-and-forget (playImmediately:false + _startupRestoreDone guard)"
  - "D-06/D-07: PLAY-03 smoke captured as 04-UAT.md, manual/user-run; pass bar = zero regressions + <100ms tap-to-audio for known-duration sources"

patterns-established:
  - "Every user-facing await initSongs(...) call site now uses the same 4-step shape: (1) early-return short-circuit, (2) all Hive writes before any await, (3) await initSongs with default playImmediately, (4) canonical catch (AppLogger.debug + mounted guard + generic SnackBar)"

requirements-completed: [PLAY-03, TEST-02, TEST-03]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "history_section.dart onTap hardened — async closure, await on initSongs, all 4 Hive writes before the await, try/catch with AppLogger.debug + mounted guard + 'Unable to start playback' SnackBar"
    requirement: PLAY-04
    verification:
      - kind: automated_procedural
        ref: "grep -nE 'onTap: \\(\\) async \\{' lib/screens/home/widgets/history_section.dart (line 156)"
        status: pass
      - kind: automated_procedural
        ref: "grep -c 'await audioHandlerProvider.audioHandler.initSongs(' lib/screens/home/widgets/history_section.dart == 1"
        status: pass
      - kind: automated_procedural
        ref: "grep -c 'AppLogger.debug(\\'Error resuming audiobook from history' lib/screens/home/widgets/history_section.dart == 1"
        status: pass
      - kind: automated_procedural
        ref: "flutter analyze lib/screens/home/widgets/history_section.dart -> No issues found! (exit 0)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Race-avoidance ordering — all 4 Hive writes (audiobook, audiobookFiles, index, position) complete synchronously before the await initSongs; no put() after the await inside the try"
    requirement: PLAY-04
    verification:
      - kind: automated_procedural
        ref: "awk scan of onTap body: zero 'playingAudiobookDetailsBox.put(' lines after 'await audioHandlerProvider.audioHandler.initSongs('"
        status: pass
    human_judgment: false
  - id: D3
    description: "TEST-02 holds — playback_trust_test.dart stays 18/18 green after the history_section change (no regression in the await-ready gate or race detector)"
    requirement: TEST-02
    verification:
      - kind: unit
        ref: "test/playback_trust_test.dart -> +18: All tests passed! (18/18)"
        status: pass
    human_judgment: false
  - id: D4
    description: "TEST-03 satisfied — 2 landed invariant tests (gen-discard during await-ready @474, timeout fallback @523) pass; 4 N/A invariants confirmed via _initSettleSub grep=0 (Phase 3 removed the infrastructure they would test)"
    requirement: TEST-03
    verification:
      - kind: unit
        ref: "test/playback_trust_test.dart#gen-discard during await-ready prevents stale init from playing"
        status: pass
      - kind: unit
        ref: "test/playback_trust_test.dart#timeout fallback blocks play when ready never arrives"
        status: pass
      - kind: automated_procedural
        ref: "grep -c '_initSettleSub' lib/resources/services/my_audio_handler.dart == 0"
        status: pass
    human_judgment: false
  - id: D5
    description: "PLAY-03 cross-source manual smoke captured as 04-UAT.md (8-row matrix: Sound-Books x4 entry points + LibriVox/YouTube/knigavuhe/4read) with <100ms pass bar + dead-URL error-path check — to be run by the user on a real device"
    requirement: PLAY-03
    verification: []
    human_judgment: true
    rationale: "Requires a real device + real network probe against all 5 sources. The fake playback engine in playback_trust_test.dart never makes a network call, so the zero-latency claim (BehaviorSubject replay short-circuits the await) and cross-source health can only be confirmed on-device. The error-path check (dead Sound-Books URL -> SnackBar) validates Task 1's catch block end-to-end, which unit tests cannot exercise without injecting a failing source."

# Metrics
duration: ~2 min
completed: 2026-07-27
status: complete
---

# Phase 04 Plan 01: History-Section Hardening + Cross-Source Verification Summary

**history_section.dart's onTap now matches the canonical _autoPlay pattern (async try/catch + await + mounted guard + SnackBar) with all 4 Hive writes relocated before the await — closing the last call-site consistency gap; TEST-02 stays 18/18 and PLAY-03 is captured as an 8-row manual smoke.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-07-27T22:24:08Z (commit `47bb60d`)
- **Completed:** 2026-07-27T22:25:34Z
- **Tasks:** 2
- **Files modified:** 1 (production) + 1 (planning artifact created)

## Accomplishments

- **Call-site consistency closed (PLAY-04 / ERR-02):** The home history-carousel tap — the one call site Phase 3's hardening missed — is now byte-for-byte consistent with `_autoPlay`, `_playChapter`, and the big play button. All four user-facing play-init call sites now share the identical `catch (e) { AppLogger.debug(...); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to start playback. Please try again.'))); }` pattern. A timeout (Phase 3 D-05/D-06) or `setAudioSources` rethrow (Phase 3 D-10) from the history tap now surfaces a SnackBar instead of failing silently.
- **Race avoidance applied (D-03):** All four Hive writes (`audiobook`, `audiobookFiles`, `index`, `position`) now complete synchronously before `await initSongs(...)`. Previously `index` and `position` were written AFTER the (then-unawaited) `initSongs` call — safe only because there was no await. Adding `await` would have let `MiniAudioPlayer.didChangeDependencies` read a partially-updated box; the relocation prevents that race (mirrors the comment at `audiobook_details.dart:69-71`).
- **TEST-02 verified (18/18 green):** `flutter test test/playback_trust_test.dart` reports `+18: All tests passed!` with zero failures after the change. The history_section edit touches neither `MyAudioHandler` nor the test file, so this is a regression guard — passed.
- **TEST-03 satisfied:** The 2 landed invariant tests (`gen-discard during await-ready` @474, `timeout fallback blocks play` @523) pass. The 4 missing invariants are confirmed N/A: `_initSettleSub` grep returns 0 (Phase 3 removed the listener infrastructure that "tracked-subscription cancellation" and "no orphan listeners" would test), and the other 2 are covered indirectly by the existing await-ready gate + race-detector tests.
- **PLAY-03 captured (D-06/D-07):** `04-UAT.md` documents the 8-row manual on-device smoke (Sound-Books x4 entry points + LibriVox/YouTube/knigavuhe/4read), the <100ms tap-to-audio pass bar for known-duration sources, and a dead-URL error-path check that validates Task 1's catch block end-to-end.

## Task Commits

Each task was committed atomically:

1. **Task 1: Harden history_section.dart onTap** — `47bb60d` (feat) — async closure, await on initSongs, 4 Hive writes relocated before await, try/catch + mounted guard + SnackBar, AppLogger import. 1 file, +30 -17.
2. **Task 2: Verify TEST-02 + capture PLAY-03 UAT** — `3892427` (test) — 04-UAT.md created (80 lines). TEST-02 re-verified 18/18 (no code change).

**Plan metadata:** this SUMMARY commit (docs).

## Files Created/Modified

- `lib/screens/home/widgets/history_section.dart` — `_buildHistoryItem` onTap: converted to `async`, added `await` on `initSongs(...)`, relocated `index`/`position` Hive writes before the await, added `try/catch` with `AppLogger.debug('Error resuming audiobook from history: $e')` + `if (!mounted) return` + generic SnackBar. Added `import 'package:audiobookflow/utils/app_logger.dart';`. The early-return short-circuit (currently-playing guard) and `_weSlideController.show()` (now inside the try, after the await) are preserved. Nothing else in the file changed (onLongPress, delete dialog, cover tile, build, etc. untouched).
- `.planning/phases/04-call-site-consistency-cross-source-verification/04-UAT.md` — manual PLAY-03 smoke matrix (8 rows: Sound-Books x4 entry points + LibriVox + YouTube + knigavuhe + 4read), <100ms pass bar, dead-URL error-path check, regression-check row, results section. Marked manual / user-run.

## Decisions Made

All seven locked decisions (D-01 through D-07) from `04-CONTEXT.md` were implemented exactly as specified. No new decisions were required — the plan was unambiguous and the existing `_autoPlay` / `_playChapter` patterns in `audiobook_details.dart` were the canonical reference.

Specifically:
- D-01/D-02: the catch block is a mechanical copy of `_autoPlay`'s, with only the log message string changed to `'Error resuming audiobook from history: $e'` (per the plan's exact text).
- D-03: the race-avoidance comment was copied from `audiobook_details.dart:69-71` (slightly expanded to mention `index`) so the invariant is self-documenting at the new site.
- D-04: `playImmediately` is NOT passed — the default `true` is correct (user tapped a book).
- D-05: `mini_audio_player.dart` confirmed untouched (`git diff --name-only` empty).

## Deviations from Plan

None — plan executed exactly as written.

One observation worth noting (not a deviation): the plan's verify-block grep `flutter test ... | grep -E "All [0-9]+ tests passed"` does not match this Flutter version's output format, which is `+18: All tests passed!` (no number between "All" and "tests"). The result is unambiguous — the `+18` cumulative counter plus "All tests passed!" confirms 18/18 with zero failures. No action needed; documenting so a future executor is not confused.

## Issues Encountered

None. The change compiled and analyzed clean on first attempt. The test suite stayed green.

## User Setup Required

None — no external service configuration required. The only user-facing follow-up is running the `04-UAT.md` manual smoke on a real device before release (a human-judgment deliverable, not a setup step).

## Next Phase Readiness

- Phase 04 plan 01 is complete. All four user-facing play-init call sites are now consistent; the Sound-Books auto-play fix from Phase 3 is fully consumed from every entry point.
- The milestone's code work is done. Remaining: the user runs the `04-UAT.md` manual smoke on a real device (PLAY-03 sign-off) before release.
- No blockers. The deferred items (4 N/A TEST-03 invariants, 2 orphaned test files breaking full-suite `flutter test`, widget test for the history tap, loading-spinner UI, cross-source hardening) remain explicitly out of scope per `04-CONTEXT.md` Deferred.
- Call-site consistency invariant for future work: any NEW `await initSongs(...)` call site must (a) write all Hive values before the await, (b) use `playImmediately:true` unless the caller explicitly drives play, and (c) catch with the canonical `AppLogger.debug + mounted guard + generic SnackBar` block.

---
*Phase: 04-call-site-consistency-cross-source-verification*
*Completed: 2026-07-27*
