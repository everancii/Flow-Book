---
phase: "03"
plan: "01"
subsystem: "playback-init"
tags: [ready-before-play, await-ready, timeout, sound-books, auto-play, error-surfacing, just_audio-fork]

# Dependency graph
requires:
  - phase: 01-diagnostic-verification-test-infrastructure
    provides: FakePlaybackEngine loading->ready simulation, confirmed play() drop mechanism
  - phase: 02-subscription-lifecycle-state-guard-cleanup
    provides: gen-guarded finally, tracked StreamSubscription _initSettleSub (superseded and removed here)
provides:
  - "initSongs awaits ProcessingState.ready before play() (the actual auto-play fix)"
  - "10s bounded ready-timeout with TimeoutException surfacing to callers"
  - "Big play button call site consistent with _autoPlay/_playChapter (playImmediately:false + explicit play())"
  - "All three call sites show SnackBar on failure with mounted guards"
affects: [phase-04-call-site-consistency-cross-source-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "await-ready gate: processingStateStream.firstWhere(ready).timeout(const) before play()"
    - "BehaviorSubject replay -> synchronous short-circuit for already-ready sources (zero added latency)"
    - "Caller-catches + SnackBar pattern applied uniformly to all play-init call sites"

key-files:
  created: []
  modified:
    - lib/resources/services/my_audio_handler.dart
    - lib/screens/audiobook_details/audiobook_details.dart
    - test/playback_trust_test.dart

key-decisions:
  - "D-01: await processingStateStream.firstWhere(ready).timeout(10s) replaces fire-and-forget play()"
  - "D-02: gen-guard (if (myGen != _initGen) return) AFTER the await, BEFORE play()"
  - "D-03/D-04: _initSettleSub listener + cancel sites + bufferingStarted local fully removed (Phase 2 infra superseded)"
  - "D-05/D-06: static const _readyTimeout = Duration(seconds: 10); on TimeoutException log + rethrow"
  - "D-07: Big play button -> await initSongs(playImmediately:false) + await play() in try/catch"
  - "D-08: Redundant await play() removed from _autoPlay and _playChapter"
  - "D-09: _autoPlay/_playChapter keep playImmediately:true default (initSongs plays internally)"
  - "D-10: setAudioSources try/catch still rethrows after logging"
  - "D-11: all three call sites get mounted guard + SnackBar in catch"
  - "D-12: ALL [DIAG] diagnostic checkpoints removed from initSongs"

patterns-established:
  - "Ready-before-play gate: never call play() until processingStateStream emits ready (bounded timeout)"
  - "BehaviorSubject replay is the zero-latency property that makes the gate cheap for known-duration sources"

requirements-completed: [PLAY-01, PLAY-02, PLAY-04, PLAY-05, PLAY-06, ERR-01, ERR-02]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "initSongs awaits ProcessingState.ready (10s timeout) before _player.play() — the core Sound-Books auto-play fix"
    requirement: PLAY-05
    verification:
      - kind: unit
        ref: "test/playback_trust_test.dart#play() does not fire when processingState stays loading (await-ready gate)"
        status: pass
      - kind: unit
        ref: "test/playback_trust_test.dart#play() does not fire before processingState reaches ready (race detector)"
        status: pass
      - kind: automated_procedural
        ref: "flutter analyze lib/resources/services/my_audio_handler.dart -> No issues found"
        status: pass
    human_judgment: false
  - id: D2
    description: "10s bounded timeout on the ready-await; TimeoutException logged via AppLogger.error then rethrown to caller"
    requirement: PLAY-06
    verification:
      - kind: unit
        ref: "test/playback_trust_test.dart#timeout fallback blocks play when ready never arrives"
        status: pass
      - kind: automated_procedural
        ref: "grep 'on TimeoutException' + 'rethrow' in my_audio_handler.dart"
        status: pass
    human_judgment: false
  - id: D3
    description: "Phase 2 _initSettleSub listener machinery + [DIAG] diagnostics fully removed (await gate supersedes them)"
    requirement: PLAY-05
    verification:
      - kind: automated_procedural
        ref: "grep -c _initSettleSub = 0; grep -c [DIAG] = 0"
        status: pass
    human_judgment: false
  - id: D4
    description: "Big play button consistent with _autoPlay/_playChapter — playImmediately:false + explicit await play(), try/catch + mounted guard + SnackBar"
    requirement: PLAY-04
    verification:
      - kind: automated_procedural
        ref: "grep playImmediately:false + await play() + mounted + SnackBar in audiobook_details.dart"
        status: pass
      - kind: automated_procedural
        ref: "flutter analyze lib/screens/audiobook_details/audiobook_details.dart -> exit 0 (1 info lint, matches existing pattern)"
        status: pass
    human_judgment: false
  - id: D5
    description: "All three play-init call sites (_playChapter, _autoPlay, big button) catch errors and show 'Unable to start playback' SnackBar with mounted guards"
    requirement: ERR-02
    verification:
      - kind: automated_procedural
        ref: "grep 'if (!mounted) return' + 'SnackBar' across all three call sites in audiobook_details.dart"
        status: pass
    human_judgment: false
  - id: D6
    description: "Sound-Books book auto-plays on open within ~10s on a real device (manual verification deferred to Phase 4)"
    requirement: PLAY-01
    verification: []
    human_judgment: true
    rationale: "Requires on-device manual smoke across Sound-Books + the other 4 sources; no automation exercises the real network probe. Phase 4 call-site-consistency-cross-source-verification owns the manual smoke."

# Metrics
duration: ~1 min (documentation close-out; production code committed 2026-07-15)
completed: 2026-07-27
status: complete
---

# Phase 03 Plan 01: Ready-Before-Play Fix Summary

**initSongs now awaits ProcessingState.ready (10s timeout) before play() — the actual Sound-Books auto-play fix; Phase 2 listener machinery and Phase 1 diagnostics removed; big play button made consistent with all callers showing SnackBars on failure.**

## Performance

- **Duration:** Production code committed 2026-07-15 (commit `a863c64`); this SUMMARY + tracking close-out authored 2026-07-27.
- **Started:** 2026-07-15T09:27:07Z (commit `a863c64`)
- **Completed:** 2026-07-27 (verification + documentation)
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- **PLAY-05 (the fix):** `initSongs` gates `_player.play()` behind `await _player.processingStateStream.firstWhere((s) => s == ProcessingState.ready).timeout(_readyTimeout)`. The fork's `processingStateStream` is backed by `BehaviorSubject<ProcessingState>.seeded(idle)` so `firstWhere` replays the last value synchronously — known-duration sources (LibriVox/YouTube/knigavuhe/4read) short-circuit with zero added latency; Sound-Books (loading during its duration probe) waits until ready or 10s.
- **PLAY-06 (timeout):** `static const _readyTimeout = Duration(seconds: 10)`. On `TimeoutException`, `AppLogger.error` logs the failure then the exception is rethrown to the caller (which catches and shows a SnackBar).
- **PLAY-04 (call-site consistency):** Big play button rewritten to `await initSongs(..., playImmediately: false)` then `await play()`, wrapped in try/catch with mounted guard + SnackBar. Redundant `await play()` removed from `_autoPlay` and `_playChapter` (they keep `playImmediately: true`, so `initSongs` plays internally).
- **ERR-01/ERR-02 (error surfacing):** `setAudioSources` try/catch still rethrows after logging. All three call sites (`_playChapter`, `_autoPlay`, big button) now have the canonical `catch (e) { AppLogger.debug(...); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(...) }` pattern.
- **Cleanup:** Removed `_initSettleSub` field + its three cancel sites (Phase 2 infrastructure superseded by the one-shot `firstWhere`). Removed `_waitForProcessingReady` polling method (YouTube special-case — the general await replaces it). Removed all `[DIAG]` diagnostic checkpoints from Phase 1. Removed the `bufferingStarted` local and the 30s buffering-skip / idle-recovery logic the listener carried.
- **Tests:** Phase 1 "fires play() unconditionally" test renamed to "await-ready gate" (asserts `playCount == 0` while loading). Race detector un-skipped and passing. Two `_initSettleSub` listener-tracking tests removed (field no longer exists). Gen-guard test kept.

## Task Commits

The three tasks were implemented atomically in a single production commit (the fix is a tightly coupled refactor across all three files). Commit hashes:

1. **Task 1 + Task 2 + Task 3 (production):** `a863c64` (feat) — ready-before-play gate, call-site consistency, test updates. 3 files, +85 -221.
2. **Task 3 follow-up (Phase 4 work that landed early):** `15899f1` (fix) — fixed the 2 pre-existing chapter-metadata failures (`_parseDoubleSafely`/`_parseIntSafely` nullable) and added the TEST-03 invariant tests (gen-discard during await-ready, timeout fallback blocks play).

**Plan metadata:** this SUMMARY commit (docs).

_Note: production code was committed via the project's conventional `feat(03):` / `fix(04):` prefix rather than the plan's `feat(phase-03/03-01):` prefix. The code is byte-for-byte what the plan specified — see acceptance-criteria verification below._

## Files Created/Modified

- `lib/resources/services/my_audio_handler.dart` — `initSongs` await-ready gate replaces fire-and-forget `play()` + listener; `_readyTimeout` const; `_initSettleSub` field + cancel sites removed; `_waitForProcessingReady` method removed; `[DIAG]` logs removed; gen-guarded finally preserved.
- `lib/screens/audiobook_details/audiobook_details.dart` — `_playChapter` redundant `play()` removed; `_autoPlay` redundant `play()` removed + catch upgraded with mounted guard + SnackBar; big play button rewritten as async `playImmediately:false` + `await play()` + try/catch + mounted guard + SnackBar.
- `test/playback_trust_test.dart` — "unconditionally" test -> "await-ready gate" (asserts playCount==0 during loading); race detector un-skipped; two `_initSettleSub` tests removed; gen-guard test kept. (Phase 4 commit `15899f1` later added gen-discard-during-await and timeout-fallback invariant tests and fixed the 2 pre-existing chapter-metadata failures.)

## Decisions Made

All twelve locked decisions (D-01 through D-12) from `03-CONTEXT.md` were implemented exactly as specified. No new decisions were required — the plan was unambiguous and the existing code patterns (gen-guard, caller-catches + SnackBar) were followed.

## Deviations from Plan

### Auto-fixed Issues

None at the code level — plan executed exactly as written.

### Process Deviation (documentation only)

**1. [Process] Production commits predate the SUMMARY; commit-message prefix differs from plan convention**
- **Found during:** SUMMARY authoring (2026-07-27)
- **Issue:** The plan's `<commit_convention>` specifies `feat(phase-03/03-01): ready-before-play gate in initSongs`. The actual production commit `a863c64` used the project's standing convention `feat(03): ready-before-play fix — THE Sound-Books auto-play fix` and bundled all three tasks. No SUMMARY.md was created at execution time.
- **Resolution:** Did NOT rewrite published history (the commits are already in `main` and shipped in release builds v1.2.1+). Instead, this SUMMARY documents the existing commits retroactively and verifies every acceptance criterion against HEAD. The atomic-close-out invariant (production commits -> SUMMARY -> STATE/ROADMAP) is satisfied by authoring the SUMMARY + tracking updates now.
- **Files modified:** `.planning/phases/03-ready-before-play-fix/03-01-SUMMARY.md` (this file), `.planning/STATE.md`, `.planning/ROADMAP.md`.
- **Verification:** `git log --oneline | grep a863c64` returns the commit; all 27 task-level acceptance criteria pass against HEAD (see Self-Check).
- **Committed in:** this docs commit.

---

**Total deviations:** 1 process deviation (documentation-only; no code deviation).
**Impact on plan:** Zero impact on the fix itself. The code matches the plan exactly; only the commit-message prefix and SUMMARY timing differ.

## Issues Encountered

None. The production code compiled and tested clean on first commit. The Phase 4 follow-up (`15899f1`) fixed the 2 pre-existing chapter-metadata failures that the plan had flagged as "acceptable" — so the test suite now passes 18/18 with zero failures, exceeding the plan's bar.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 03 is complete. The Sound-Books auto-play fix is in `main` and shipped (v1.2.1+).
- **Phase 4** (Call-Site Consistency + Cross-Source Verification) is partially done: call-site consistency (PLAY-04) and TEST-03 invariant tests landed in commits `a863c64` + `15899f1`. Remaining Phase 4 work: PLAY-03 cross-source manual smoke on a real device (the await-ready short-circuit is verified by unit tests but the real-network zero-latency claim needs on-device confirmation), and TEST-02 (the chapter-metadata fix in `15899f1` resolved the pre-existing failures).
- No blockers.

## Self-Check: PASSED

### Task 1 — Ready-Before-Play Gate in initSongs (12/12 acceptance criteria)
- [x] AC1: `await _player.processingStateStream.firstWhere((s) => s == ProcessingState.ready).timeout(_readyTimeout)` present in `if (playImmediately)` block (line 570-572)
- [x] AC2: `static const _readyTimeout = Duration(seconds: 10);` present (line 249)
- [x] AC3: `on TimeoutException` handler logs + rethrows (lines 573-577)
- [x] AC4: `if (myGen != _initGen) return;` AFTER await-ready, BEFORE `_player.play()` (line 580, before 582)
- [x] AC5: `_initSettleSub` absent everywhere (`grep -c` = 0)
- [x] AC6: `bufferingStarted` variable absent (`grep -c` = 0)
- [x] AC7: `[DIAG]` log calls absent (`grep -c` = 0)
- [x] AC8: 30s buffering-skip logic absent (`grep "Duration(seconds: 30)"` = empty)
- [x] AC9: idle recovery logic absent (only `ProcessingState.idle` hits are the AudioProcessingState mapping table)
- [x] AC10: gen-guarded finally present (`if (myGen == _initGen) { _isReinitializing = false; }` line 619)
- [x] AC11: setAudioSources try/catch rethrows (lines 552-555)
- [x] AC12: `flutter analyze lib/resources/services/my_audio_handler.dart` -> "No issues found!" exit 0

### Task 2 — Call-Site Consistency + Error Surfacing (9/9 acceptance criteria)
- [x] AC1: `_playChapter` has no `await play()` after initSongs
- [x] AC2: `_autoPlay` has no `await play()` after initSongs calls
- [x] AC3: `_autoPlay` catch has `if (!mounted) return` + `SnackBar`
- [x] AC4: Big play button has `playImmediately: false` in both initSongs calls (lines 539, 549)
- [x] AC5: Big play button has `await` before both initSongs calls (lines 534, 544)
- [x] AC6: Big play button has `await audioHandlerProvider.audioHandler.play();` after initSongs (line 553)
- [x] AC7: Big play button wrapped in try/catch with `if (!mounted) return` + SnackBar (lines 555-564)
- [x] AC8: `_playChapter` catch unchanged with mounted guard + SnackBar (lines 83-90)
- [x] AC9: `flutter analyze lib/screens/audiobook_details/audiobook_details.dart` -> exit 0 (1 info lint matching existing project pattern)

### Task 3 — Update Tests for Ready-Before-Play Behavior (6/6 acceptance criteria)
- [x] AC1: Test asserting `fake.playCount == 0` when processingState stays loading present (line 394, "await-ready gate" test)
- [x] AC2: Race detector test NOT skipped (no `skip:` parameter; "await Phase 3 ready-before-play fix" string absent)
- [x] AC3: Two listener-tracking tests removed (`grep` for both titles returns empty)
- [x] AC4: Gen-guard test kept (`grep "stale init finally does not clobber"` returns line 438)
- [x] AC5: `flutter test test/playback_trust_test.dart` -> **All 18 tests passed!** zero failures (the 2 pre-existing chapter-metadata failures were fixed by Phase 4 commit `15899f1`, exceeding the plan's bar)
- [x] AC6: Race detector test PASSES (not failing, not skipped — `+14: play() does not fire before processingState reaches ready (race detector)`)

### Phase-level verification (VC1-VC5)
- [x] VC1: `flutter analyze` on both modified files -> exit 0 (1 info lint, matches existing pattern)
- [x] VC2: `flutter test test/playback_trust_test.dart` -> 18/18 pass, race detector passing, zero new failures
- [x] VC3: `grep -c "[DIAG]"` = 0
- [x] VC4: `grep "_initSettleSub"` = empty
- [x] VC5: `grep "firstWhere.*ProcessingState.ready"` returns line 571 (the await-ready gate)
- [ ] VC6/VC7: Manual on-device Sound-Books auto-play + zero-latency for other sources — **deferred to Phase 4** (requires real device + network probe; unit tests verify the mechanism).

---
*Phase: 03-ready-before-play-fix*
*Completed: 2026-07-27*
