---
phase: "03"
phase_name: ready-before-play-fix
status: passed
verified_at: "2026-07-27T13:37:10Z"
score: "12/12 must-haves verified"
requirements: [PLAY-01, PLAY-02, PLAY-04, PLAY-05, PLAY-06, ERR-01, ERR-02]
---

# Phase 03 Verification: Ready-Before-Play Fix

## Phase Goal

**Restated:** Opening a Sound-Books book starts playback automatically — the actual bug fix. Restructure `initSongs` to await `ProcessingState.ready` (with bounded timeout + error-state handling) before fire-and-forget `play()`.

**Status: MET (automated evidence).** The code change exists exactly as specified, compiles clean, and the race-detector test passes. The actual on-device Sound-Books auto-play smoke is a manual-only item explicitly deferred to Phase 4 (per plan `Verification Criteria` items 6-7) and is therefore a documented handoff, not a gap.

## Must-Haves Verification

Verification was performed by reading the actual production code on disk against each must-have truth statement. The SUMMARY was used only as a cross-reference; every pass below is backed by a direct read of the source.

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| D-01 | await-ready gate inside `if (playImmediately)` before `_player.play()` | ✓ PASS | `lib/resources/services/my_audio_handler.dart:569-572` — `await _player.processingStateStream.firstWhere((s) => s == ProcessingState.ready).timeout(_readyTimeout);` inside the `if (playImmediately) {` block (line 559), before `_player.play()` (line 582). Also `static const _readyTimeout = Duration(seconds: 10);` at line 249. |
| D-02 | `if (myGen != _initGen) return;` AFTER the await, BEFORE `_player.play()` | ✓ PASS | `my_audio_handler.dart:580` — gen-guard sits between the await-ready block (569-577) and `_player.play()` (582). Correct ordering confirmed by direct read. |
| D-03 | `_initSettleSub` listener fully removed (ready re-trigger, 30s buffering-skip, idle recovery gone) | ✓ PASS | `grep -c "_initSettleSub" my_audio_handler.dart` → **0**. `grep "Duration(seconds: 30)"` → empty. `grep "ProcessingState.idle && _player.playing"` → empty. All three listener behaviors eliminated. |
| D-04 | `_initSettleSub` field + cancel sites (top of initSongs, stop(), finally) + `bufferingStarted` local all removed | ✓ PASS | `_initSettleSub` count = 0 (field, cancels, assignment — all gone). `bufferingStarted` count = 0. initSongs top (427-435) has no cancel; stop() (874-880) has no cancel; finally block (616-622) has no cancel — only the gen-guard remains. `_waitForProcessingReady` method also removed (count = 0). |
| D-05 | On `TimeoutException`: `AppLogger.error` logs then rethrows | ✓ PASS | `my_audio_handler.dart:573-577` — `} on TimeoutException { AppLogger.error('initSongs: timed out waiting for ProcessingState.ready after ${_readyTimeout.inSeconds}s'); rethrow; }`. Uses `AppLogger.error` (not debug). |
| D-06 | 10s bounded timeout via `.timeout(const Duration(seconds: 10))` as static const | ✓ PASS | `_readyTimeout` const at line 249; applied at line 572. Satisfies D-05/D-06 in CONTEXT (D-06 is the same decision as D-05). |
| D-07 | Big play button: `await initSongs(..., playImmediately: false)` then `await play()` in try/catch with mounted guard + SnackBar | ✓ PASS | `audiobook_details.dart:517-565` — `onTap: () async { try { ... await initSongs(..., playImmediately: false) (lines 534, 544) ...; await audioHandlerProvider.audioHandler.play(); (553); _weSlideController.show(); } catch (e) { AppLogger.debug(...); if (!mounted) return; ScaffoldMessenger...SnackBar('Unable to start playback...'); } }`. (Note: widget is `InkWell.onTap`, not `onPressed` — the play circle; semantics identical.) |
| D-08 | Redundant `await play()` removed from `_autoPlay` and `_playChapter` | ✓ PASS | `_playChapter` (67-91) has no `play()` call; `_autoPlay` (93-139) has no `play()` call. Both end with `_weSlideController.show()` only. |
| D-09 | `_autoPlay` and `_playChapter` keep `playImmediately: true` default (do NOT pass `playImmediately: false`) | ✓ PASS | `_playChapter` initSongs call (80-81) and both `_autoPlay` initSongs calls (113, 122) omit the `playImmediately` parameter entirely. `playImmediately: false` appears ONLY in the big button (lines 539, 549). |
| D-10 | `setAudioSources` try/catch rethrows after logging | ✓ PASS | `my_audio_handler.dart:543-555` — `try { await _player.setAudioSources(...); } catch (e) { AppLogger.debug('initSongs: setAudioSources failed: $e'); rethrow; }`. |
| D-11 | All three call sites have `if (!mounted) return` + SnackBar in catch blocks | ✓ PASS | `_playChapter` catch (83-90): `AppLogger.debug(...); if (!mounted) return; ScaffoldMessenger...SnackBar(...)`. `_autoPlay` catch (131-138): same pattern. Big button catch (555-564): same pattern. All three verified by direct read. |
| D-12 | Zero `[DIAG]` log calls in `my_audio_handler.dart` | ✓ PASS | `grep -c '\[DIAG\]' my_audio_handler.dart` → **0**. All Phase 1 diagnostic checkpoints removed. |

**Score: 12/12 must-haves verified PASS against actual code on disk.**

## Requirement Traceability

| Req ID | Must-Have Coverage | Status |
|--------|-------------------|--------|
| PLAY-01 | D-01, D-02 (the await-ready gate that makes Sound-Books auto-play on open). On-device smoke deferred to Phase 4 (D6 in SUMMARY coverage map). | ✓ (mechanism verified; on-device smoke deferred to Phase 4) |
| PLAY-02 | D-01, D-02 — the gate applies to the resume path (`_autoPlay` history branch, audiobook_details.dart:106-118) the same way as the fresh-open path. | ✓ (same mechanism; on-device resume smoke deferred to Phase 4) |
| PLAY-04 | D-07 — big play button now consistent with `_autoPlay`/`_playChapter` (explicit `play()` after `initSongs(playImmediately: false)`). | ✓ |
| PLAY-05 | D-01 (core gate), D-03/D-04 (superseded listener removed). | ✓ |
| PLAY-06 | D-05/D-06 (10s timeout + `TimeoutException` rethrow). | ✓ |
| ERR-01 | D-10 — `setAudioSources` try/catch rethrows; caller catches and shows SnackBar. | ✓ |
| ERR-02 | D-11 — all three call sites have `if (!mounted) return` + SnackBar in catch. | ✓ |

All seven assigned requirement IDs (PLAY-01, PLAY-02, PLAY-04, PLAY-05, PLAY-06, ERR-01, ERR-02) are accounted for by at least one passing must-have.

## Automated Checks

- `grep -n "firstWhere.*ProcessingState.ready" my_audio_handler.dart` → `571: .firstWhere((s) => s == ProcessingState.ready)` ✓
- `grep -n "timeout.*_readyTimeout" my_audio_handler.dart` → `572: .timeout(_readyTimeout);` ✓
- `grep -c "_initSettleSub" my_audio_handler.dart` → **0** ✓
- `grep -c '\[DIAG\]' my_audio_handler.dart` → **0** ✓
- `grep -A3 "} finally {" my_audio_handler.dart | grep "myGen == _initGen"` → `if (myGen == _initGen) {` ✓ (gen-guarded finally preserved)
- `grep -n "_readyTimeout" my_audio_handler.dart` → line 249 (const), 572 (apply), 575 (log) ✓
- `flutter analyze lib/resources/services/my_audio_handler.dart lib/screens/audiobook_details/audiobook_details.dart` → **exit 0**; 1 info lint (`use_build_context_synchronously` at `audiobook_details.dart:559:62`). This lint is informational (not error/warning), matches the pre-existing pattern already present in `_playChapter`'s identical catch block, and is the documented expected state per the SUMMARY. Not a regression.
- `flutter test test/playback_trust_test.dart` → **All 18 tests passed, 0 failures.** The race detector test passes (`play() does not fire before processingState reaches ready (race detector)`); the await-ready gate test passes; both Phase 4 invariant tests (gen-discard during await-ready, timeout fallback) pass. The 2 pre-existing chapter-metadata failures flagged by the plan were resolved by Phase 4 commit `15899f1`, so the suite now exceeds the plan's bar.

## Task Acceptance Criteria Spot-Check

Cross-referenced the SUMMARY's self-check claims against the code; all confirmed:

- **Task 1 (12/12 AC):** await-ready gate (570-572), `_readyTimeout` const (249), `on TimeoutException` + rethrow (573-577), gen-guard after await before play (580), `_initSettleSub`=0, `bufferingStarted`=0, `[DIAG]`=0, 30s buffering-skip absent, idle-recovery absent, gen-guarded finally (619), setAudioSources rethrow (554), analyze clean. All PASS.
- **Task 2 (9/9 AC):** `_playChapter`/`_autoPlay` no redundant `play()`, `_autoPlay` catch upgraded with mounted+SnackBar, big button has `playImmediately: false` × 2 (539, 549) + `await` × 2 + `await play()` (553) + try/catch+mounted+SnackBar (555-564), `_playChapter` catch unchanged. All PASS.
- **Task 3 (6/6 AC):** `playCount == 0` assertion present (line 394), race detector NOT skipped (0 `skip:` params, skip-string absent), both `_initSettleSub` listener tests removed (0 occurrences), gen-guard test kept (line 438), full suite 18/18 green, race detector passes. All PASS.

## Phase Goal Assessment

The phase achieved its goal at the level the Phase 3 bar requires: the code change exists exactly as the locked decisions specified, it compiles, it passes the full test suite (including the un-skipped race detector and the new await-ready gate tests), and it meets every one of the 12 must-haves. The fix replaces the fire-and-forget `_player.play()` with a bounded await on `ProcessingState.ready`, gated by a stale-init gen-check, with timeout errors surfacing as user-visible SnackBars at all three call sites.

The actual on-device confirmation — "tap a Sound-Books book and it plays within ~10s" and "other 4 sources still auto-play with zero perceptible latency" — is a manual-only smoke that the plan explicitly deferred to Phase 4 (`Verification Criteria` items 6-7). That is a documented handoff, not a gap in Phase 3. The BehaviorSubject-replay zero-latency property for known-duration sources is a code-level guarantee (confirmed by Phase 1 research) and is exercised by the passing tests.

## Deferred Items

- **On-device Sound-Books auto-play smoke** → Phase 4 (per plan Verification Criteria 6). The unit tests prove the await-ready gate defers `play()` until ready and the gen-guard prevents stale-init play; they do not exercise the real Sound-Books network duration probe.
- **On-device cross-source latency check** (zero added latency for LibriVox/YouTube/knigavuhe/4read) → Phase 4 (per plan Verification Criteria 7). The BehaviorSubject synchronous short-circuit is verified at the code/unit level only.
- **On-device resume-from-history auto-play** (PLAY-02 on-device) → Phase 4.
- **`use_build_context_synchronously` info lint** at `audiobook_details.dart:559` — pre-existing pattern, informational only, not a blocker. Could be silenced with a `// ignore:` directive or by guarding with `context.mounted`, but the existing `_playChapter` catch carries the same lint and the project treats it as acceptable.

## human_verification

None required at the Phase 3 bar. The only items requiring manual testing are the three on-device smokes listed under Deferred Items, all owned by Phase 4.

## Conclusion

Phase 03 PASSES verification. All 12 must-haves (D-01 through D-12) are verified PASS against the actual code on disk, every assigned requirement ID (PLAY-01, PLAY-02, PLAY-04, PLAY-05, PLAY-06, ERR-01, ERR-02) is covered by passing must-haves, `flutter analyze` exits clean (1 pre-existing info lint), and `flutter test test/playback_trust_test.dart` passes 18/18 including the un-skipped race detector. The await-ready gate, stale-init gen-guard, bounded 10s timeout with `TimeoutException` surfacing, call-site consistency, and mounted-guard + SnackBar error surfacing are all present exactly as the locked decisions specified. The on-device smoke tests remain a documented Phase 4 handoff, not a Phase 3 gap.
