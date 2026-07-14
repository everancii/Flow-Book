# Phase 2: Subscription Lifecycle + State-Guard Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-15
**Phase:** 2-Subscription Lifecycle + State-Guard Cleanup
**Areas discussed:** Gen-guard on finally, Tracked subscription design, Buffering-recovery + orphan listener fate, Test strategy for refactors

---

## Gen-Guard on Finally

**Q1: How should the finally block be protected against stale-init clobber?**

| Option | Description | Selected |
|--------|-------------|----------|
| Guard the finally | `finally { if (myGen == _initGen) { _isReinitializing = false; } }` — only active gen clears the flag | ✓ |
| Clear at each exit point | Clear `_isReinitializing = false` at each non-stale exit point instead of in finally | |
| Remove _isReinitializing entirely | Replace with gen-based checks at all 5 read sites | |

**User's choice:** Guard the finally
**Notes:** Minimal blast radius, single point of change, works with Phase 3's new return points.

**Q2: Should the early-return points (lines 526, 566, 656) also change, or just the finally?**

| Option | Description | Selected |
|--------|-------------|----------|
| No change to returns | Early-return points already guard correctly; only the finally changes | ✓ |
| Log when stale finally skips | Add a debug log when the finally detects a stale gen | |

**User's choice:** No change to returns
**Notes:** Existing `if (myGen != _initGen) return;` guards + guarded finally = correct behavior. Stale init returns → finally sees stale gen → skips clear.

---

## Tracked Subscription Design

**Q1: How should the subscriptions be tracked and cancelled?**

| Option | Description | Selected |
|--------|-------------|----------|
| Single _initSettleSub field | One tracked field replaces the 60s fire-and-forget timer | ✓ |
| Two separate fields | Keep buffering-recovery and debug-log listeners as separate tracked fields | |
| Replace listener with firstWhere | Switch to stream-transformer approach now | |

**User's choice:** Single _initSettleSub field
**Notes:** Minimal new state. One field, one listener, deterministic cancellation.

**Q2: Where should _initSettleSub be cancelled?**

| Option | Description | Selected |
|--------|-------------|----------|
| Top of next initSongs | Prevents stacking on re-entry | ✓ |
| In stop() | Full teardown when playback stops | ✓ |
| In the finally block | Normal completion path inside initSongs | ✓ |

**User's choice:** All three sites
**Notes:** Triple safety. The requirement text (PLAY-08) specifies the first two; the third is an additional safety net for the normal-completion path.

---

## Buffering-Recovery + Orphan Listener Fate

**Q1: What happens to the three behaviors inside the listener and the orphan at line 645?**

| Option | Description | Selected |
|--------|-------------|----------|
| Fold all three, remove orphan | All 3 behaviors go into _initSettleSub; orphan at 645 removed (redundant log) | ✓ |
| Keep orphan as separate tracked field | Two fields: buffering-recovery + debug-log | |
| Strip to Phase 3, defer skip | Remove 30s buffering-skip now, let Phase 3 handle it | |

**User's choice:** Fold all three, remove orphan
**Notes:** The orphan at line 645 logs only; line 604 already logs every state change inside the tracked listener. Orphan is redundant and leaks a subscription per call. Folding preserves exact behavior.

**Q2: Keep or remove [DIAG] diagnostic logs from Phase 1?**

| Option | Description | Selected |
|--------|-------------|----------|
| Keep [DIAG] logs in place | Still valuable for on-device debugging through Phase 2/3 | ✓ |
| Remove [DIAG] logs | Phase 1 verification complete, remove for cleaner code | |

**User's choice:** Keep [DIAG] logs in place
**Notes:** Phase 3 may remove them after the fix is verified on-device, but for now they stay.

---

## Test Strategy for Refactors

**Q1: Should Phase 2 add new tests for the refactors, or defer testing to Phase 4?**

| Option | Description | Selected |
|--------|-------------|----------|
| Add refactor tests now | Focused tests for gen-guard, tracked-sub, orphan removal — verify "no behavior change" immediately | ✓ |
| Defer all tests to Phase 4 | Trust the refactors; let TEST-03 cover everything | |
| Add tests + fix pre-existing failures | Also fix the 2 chapter-metadata failures while in the file | |

**User's choice:** Add refactor tests now
**Notes:** Catches regressions immediately. Separate from Phase 4's TEST-03 (complete fix tests). The 2 pre-existing failures stay deferred — unrelated to subscription lifecycle.

**Q2: Where should the Phase 2 refactor tests live?**

| Option | Description | Selected |
|--------|-------------|----------|
| Same file, same group | Inside existing 'MyAudioHandler with fake playback engine' group in playback_trust_test.dart | ✓ |
| New dedicated test file | Create test/subscription_lifecycle_test.dart | |

**User's choice:** Same file, same group
**Notes:** Group is already green. Reuses _sampleFiles(), _sampleAudiobook(), FakePlaybackEngine. No boilerplate duplication.

---

## Claude's Discretion

- Exact test assertion mechanisms (expose new FakePlaybackEngine getter for listener count vs use `processingStates.hasListener`) — pick cleanest approach.
- Whether to add a brief inline comment at the `_initSettleSub` field declaration explaining the three cancel sites.

## Deferred Ideas

None — discussion stayed within phase scope. The 2 pre-existing `chapter switching metadata` test failures were discussed but explicitly deferred per `deferred-items.md`.
