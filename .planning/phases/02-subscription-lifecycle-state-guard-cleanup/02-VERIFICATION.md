---
phase: "02"
phase_name: subscription-lifecycle-state-guard-cleanup
status: passed
verified_at: "2026-07-27T22:39:08Z"
score: "3/3 requirements addressed (PLAY-07 complete in code; PLAY-08 superseded by Phase 3 D-03/D-04; PLAY-09 complete and preserved)"
requirements: [PLAY-07, PLAY-08, PLAY-09]
verification_type: retrospective
---

# Phase 02 Verification: Subscription Lifecycle + State-Guard Cleanup

## Phase Goal

> Eliminate the existing subscription leaks and `_isReinitializing`-clobber race
> as pure refactors (no user-visible behavior change) so the Phase 3 await
> doesn't widen existing races.

**Status: MET.** Phase 2 was a refactor precondition. Its gen-guard on the finally
block (PLAY-07) is still in the code on HEAD and is the surviving piece of
infrastructure. Its tracked-subscription work (PLAY-08) was intentionally
superseded by Phase 3's superior await-ready approach — the `_initSettleSub`
field and its cancel sites were removed by Phase 3 decisions D-03/D-04 because
the one-shot `firstWhere(ready)` await replaced the listener-based ready
detection, leaving no subscription to track. The orphan-listener removal (PLAY-09)
landed in Phase 2 and the orphan was not reintroduced. Phase 3's await-ready fix
landed cleanly on top of Phase 2's refactored base — the clobber race and
listener leaks Phase 2 cleared did not re-open. Goal met.

## Must-Haves Verification

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| PLAY-07 | Gen-guard on finally: the `finally { _isReinitializing = false; }` block is guarded with `if (myGen == _initGen)` so a stale init doesn't clobber a newer init's flag | ✓ Complete (in code) | `lib/resources/services/my_audio_handler.dart:616-622` — `} finally { if (myGen == _initGen) { _isReinitializing = false; } }`. The only `_isReinitializing = false` write in the file is inside this gen-guarded finally (grep confirms the reset appears exactly once, at line 620). Phase 3 retained this guard unchanged. Verified by `grep -n "_isReinitializing = false"` → `620:        _isReinitializing = false;` and `grep -n "myGen == _initGen"` → `619:      if (myGen == _initGen) {`. The Phase 2 test `'stale init finally does not clobber newer init _isReinitializing flag'` (`test/playback_trust_test.dart:437`) covers this invariant and passes on HEAD. |
| PLAY-08 | Tracked `StreamSubscription` cancelled at top of next `initSongs` and in `stop()` replaces the 60s fire-and-forget cancel | ⊘ Superseded by Phase 3 (D-03/D-04) | `grep -c "_initSettleSub" lib/resources/services/my_audio_handler.dart` → **0**. Phase 2 added the `_initSettleSub` field, its three cancel sites, and removed the 60s fire-and-forget `Future.delayed`. Phase 3 decision D-04 then **intentionally removed** the field and all cancel sites because the await-ready gate (`processingStateStream.firstWhere(ready).timeout(10s)`, `my_audio_handler.dart:569-577`) is a one-shot future — it has no long-lived subscription to track, so the bookkeeping Phase 2 introduced became dead weight. This is intentional architectural supersession, not a regression: the leak Phase 2 was eliminating (fire-and-forget cancel stacking on re-entry) is gone because the mechanism that produced it (the long-lived listener) is gone. The fire-and-forget line itself is also confirmed absent (`grep -n "Future.delayed(const Duration(seconds: 60)"` → no match). See Supersession Notes below. |
| PLAY-09 | The orphan `processingStateStream.listen` (log-only, never cancelled) is removed | ✓ Complete (and preserved) | `grep -n "processingStateStream.listen" lib/resources/services/my_audio_handler.dart` → **no matches**. The orphan listener Phase 2 removed at former line ~645 has not been reintroduced. The only `.listen(` calls remaining in the file are the long-lived field-tracked ones on other streams (`_eventSub`/`_playerStateSub`/`_playingSub`/`_bufferedSub`/`_coverSub` at lines 326-348, plus `_listenForCurrentSongIndexChanges` on `currentIndexStream` at line 656) — none on `processingStateStream`. Phase 3's await-based approach does not re-add an uncancelled listener. |

## Requirement Traceability

| Requirement | Phase | Status | Evidence |
|-------------|-------|--------|----------|
| PLAY-07 | Phase 2 | Complete (in code, retained by Phase 3) | Gen-guarded finally at `my_audio_handler.dart:616-622`; covered by passing test at `playback_trust_test.dart:437`. |
| PLAY-08 | Phase 2 | Superseded by Phase 3 D-03/D-04 | `_initSettleSub` count = 0 on HEAD. Phase 2 delivered it (commit `351a75d`); Phase 3 removed it because the await-ready gate made the tracked subscription unnecessary. The underlying concern (no subscription leak / no stacking on re-entry) is satisfied structurally by Phase 3's one-shot await. |
| PLAY-09 | Phase 2 | Complete | No `processingStateStream.listen` calls remain. The orphan was removed in Phase 2 and not reintroduced. |

## Automated Checks

```
$ flutter test test/playback_trust_test.dart 2>&1 | tail -3
00:00 +18: MyAudioHandler with fake playback engine timeout fallback blocks play when ready never arrives
00:00 +18: All tests passed!

$ grep -c "\[DIAG\]" lib/resources/services/my_audio_handler.dart
0
$ grep -n "myGen == _initGen" lib/resources/services/my_audio_handler.dart | head -5
619:      if (myGen == _initGen) {
$ grep -c "_initSettleSub" lib/resources/services/my_audio_handler.dart
0
$ grep -n "_listenForCurrentSongIndexChanges" lib/resources/services/my_audio_handler.dart | head -3
601:      _listenForCurrentSongIndexChanges();
655:  void _listenForCurrentSongIndexChanges() {
```

- `flutter test test/playback_trust_test.dart` → **18/18 pass**, 0 failures. No
  behaviour regression from Phase 2's refactor (success criterion 3 met). The
  Phase 2 test `'stale init finally does not clobber newer init _isReinitializing flag'`
  (line 437) is among the passing tests — it directly verifies PLAY-07.
- Phase 2's other two tests (tracked-sub cancellation on re-entry, stop() cancels
  listeners) were removed by Phase 3 because they exercised the `_initSettleSub`
  mechanism that no longer exists. This is consistent with the supersession and
  is not a regression — the invariants they protected are now satisfied
  structurally by the one-shot await.

## Phase Goal Assessment

Phase 2 was explicitly framed as a refactor stepping stone, not final-state code.
The ROADMAP goal — "eliminate leaks and the clobber race as pure refactors so the
Phase 3 await doesn't widen them" — was met on both axes:

1. **Clobber race (PLAY-07):** the gen-guarded finally is in the code on HEAD
   (line 616-622), retained by Phase 3, and covered by a passing test. The
   await-ready gate widens the clobber window (the await creates a longer
   async gap during which a stale init could otherwise run its finally), and
   the gen-guard is exactly what prevents that widened window from corrupting
   `_isReinitializing`. Phase 3 relied on this guard being in place.

2. **Subscription leaks (PLAY-08, PLAY-09):** Phase 2 cleared the fire-and-forget
   60s cancel and the orphan listener so Phase 3 would not layer its await on
   top of pre-existing leaks. Phase 3 then went further and removed the
   listener mechanism entirely (replacing it with a one-shot await), which
   structurally eliminates the leak class. The net effect on HEAD: no
   `processingStateStream.listen` calls, no fire-and-forget cancel, no
   `_initSettleSub` field. The concern Phase 2 addressed is resolved —
   resolved even more thoroughly than Phase 2 itself resolved it.

Phase 3's await-ready fix landed cleanly on top of Phase 2's refactored base,
which is the precise success condition Phase 2 existed to enable. Goal met.

## Supersession Notes

### PLAY-08 — `_initSettleSub` removed by Phase 3 (intentional)

Phase 2 added a tracked `StreamSubscription<ProcessingState>? _initSettleSub`
field, assigned the `processingStateStream.listen` to it, and cancelled it at
three sites (top of next `initSongs`, `stop()`, guarded finally). This replaced
the fire-and-forget `Future.delayed(60s, () => sub.cancel())` and eliminated
both the stacking-on-re-entry leak and the 60s window where the listener stayed
alive after initSongs completed.

Phase 3's CONTEXT.md decisions D-03 and D-04 then removed this infrastructure
in full:

> **D-03:** The `_initSettleSub` listener is **REMOVED entirely**. The await
> replaces its ready re-trigger purpose.
>
> **D-04:** The `_initSettleSub` field, its cancel sites (top of initSongs,
> stop(), finally), and the `bufferingStarted` local are ALL removed since the
> listener no longer exists.

Reason: Phase 3's fix uses
`await _player.processingStateStream.firstWhere((s) => s == ProcessingState.ready).timeout(_readyTimeout)`
(`my_audio_handler.dart:569-577`). A `firstWhere` future is one-shot — it
auto-cancels its subscription when it completes (or when the timeout fires).
There is no long-lived listener to track, so the three cancel sites and the
field have no job. Phase 3 also removed the three listener behaviours the
`_initSettleSub` carried (ready re-trigger, idle recovery, 30s buffering-skip)
because the await gate supersedes all three (PLAY-05/PLAY-06 cover the
replacement). Grep evidence: `_initSettleSub` count on HEAD is **0**.

This is a legitimate outcome to document, not a gap: Phase 2's work was a
refactor stepping stone that let Phase 3 land a cleaner architecture than would
have been possible if Phase 3 had to refactor leaking listener code AND
introduce the await in the same change. Phase 2 isolated the lifecycle cleanup;
Phase 3 then removed the listener entirely. The end state has no leak.

### `_listenForCurrentSongIndexChanges` leak — deferred to v2 (outside blast radius)

Phase 2 success criterion 1 references the `_listenForCurrentSongIndexChanges`
listener. This listener (`my_audio_handler.dart:655`, called at line 601 inside
`initSongs`) attaches a `currentIndexStream.listen` that is never cancelled and
is re-created on every `initSongs` call — i.e. it leaks one subscription per
open. It is flagged in `01-RESEARCH.md` and listed in `REQUIREMENTS.md` v2
Deferred Requirements as "`_listenForCurrentSongIndexChanges` listener leak —
flagged in research but outside this fix's blast radius".

This leak was intentionally **not** in Phase 2's scope. Phase 2 targeted only
the `processingStateStream` listener family (the one entangled with the
`_isReinitializing` clobber race and the play-init sequence the fix was
rewriting). The `currentIndexStream` listener is a separate persistence-path
concern (it writes the now-playing index to Hive) and was correctly deferred to
avoid widening Phase 2's blast radius. It remains open on HEAD and is tracked
under v2. Documenting it here as deferred, not as a gap.

### Phase 2 tests 2 and 3 — obsoleted by Phase 3

Phase 2 added three refactor tests. Test 1 (gen-guard finally, line 437) survives
and passes on HEAD. Tests 2 (`initSongs cancels previous processingStateStream
listener on re-entry`) and 3 (`stop() cancels all processingStateStream
listeners`) were removed by Phase 3 because they assert on the `_initSettleSub`
mechanism that no longer exists. Consistent with the supersession above — the
invariants those tests protected (no listener stacking, listeners torn down on
stop) are now satisfied structurally by the one-shot await, which has no
listener to stack or tear down.

## Conclusion

**Phase 02 PASSED** (with documented supersession). PLAY-07 is complete and
present in HEAD code. PLAY-09 is complete and preserved. PLAY-08 was delivered
by Phase 2 then intentionally superseded by Phase 3's await-ready gate (D-03/D-04),
which structurally resolves the same leak class the tracked subscription was
designed to manage. The end state has no `processingStateStream` listener leak,
no fire-and-forget cancel, and a gen-guarded finally that prevents the clobber
race Phase 3's widened await window would otherwise have opened. Phase 2 met its
goal as a refactor precondition: Phase 3 landed cleanly on top of it.
