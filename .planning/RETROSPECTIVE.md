# Retrospective: Flow Book

Living document. Updated at each milestone completion.

## Milestone: v1.0 — Sound-Books Auto-Play Fix

**Shipped:** 2026-07-28
**Phases:** 4 | **Plans:** 5 | **Tasks:** 9
**Timeline:** 2026-07-14 → 2026-07-28 (14 days, with gaps)

### What Was Built

The core bug — **opening a Sound-Books book silently failed to auto-play** — is fixed. Tap any book from any of the 5 sources and it plays in one gesture.

- **Phase 1** confirmed the root cause on-device (`play()` fires during `loading`/`buffering`; the fork's `play()` drops the request when `audioSession.setActive(true)` fails on a non-ready player) and built the `FakePlaybackEngine` loading→ready simulation that made the race reproducible in tests.
- **Phase 2** was a pure-refactor stepping stone: added gen-guarded finally (PLAY-07), tracked StreamSubscription, and orphan-listener removal so Phase 3's await wouldn't widen existing races.
- **Phase 3** was THE fix: gate `_player.play()` behind `await processingStateStream.firstWhere(ready).timeout(10s)` — BehaviorSubject replays last value, so known-duration sources short-circuit synchronously (zero latency), while Sound-Books waits for readiness. Removed the `_initSettleSub` listener machinery (Phase 2's tracking infra became redundant). Made the big play button consistent with `_autoPlay`/`_playChapter`.
- **Phase 4** closed the regression surface: hardened the 4th user-facing call site (`history_section.dart` onTap), verified the suite stays 18/18, captured the PLAY-03 on-device smoke matrix as UAT.

### What Worked

- **Research-backed 4-phase dependency chain.** The order (diagnose → refactor preconditions → fix → verify) was deliberate. Phase 2's refactor-as-stepping-stone meant Phase 3 could land cleanly on a tidy foundation. Phase 3 then *superseded* Phase 2's `_initSettleSub` work — which is the correct outcome (a refactor that makes the real fix possible, then gets out of the way).
- **BehaviorSubject replay insight.** The zero-latency property for known-duration sources (`firstWhere(ready)` completes synchronously when already ready) was the key technical finding from Phase 1 research. It let the fix avoid adding delay to the 4 working sources while fixing the broken one.
- **Locked decisions in CONTEXT.md.** Each phase's discuss-phase produced D-01-through-D-N locked decisions that the planner and executor honored exactly. Zero scope creep across 4 phases.
- **Test suite as the contract.** `playback_trust_test.dart` (the 520-line invariant suite) was the source of truth throughout. "Don't break it" was a hard constraint in AGENTS.md, and every phase ran it as the post-merge gate. Final state: 18/18 green.
- **Retrospective verification at milestone close.** Phases 1 and 2 shipped without formal VERIFICATION.md files (verification debt flagged in `/gsd-progress`). Closing that debt before archiving — rather than overriding it — produced a clean `verified_closeout` and surfaced the PLAY-08 supersession story honestly.

### What Was Inefficient

- **Phase 3's production code shipped before its SUMMARY.** The executor found commits `a863c64` + `15899f1` already on `main` when it spawned — the code was written outside the GSD workflow. The executor correctly refused to rewrite published history, verified all 27 acceptance criteria against HEAD, and authored the missing planning artifacts. But this means the plan→execute loop wasn't the source of truth for Phase 3's code; the plan was a retroactive specification. Not a regression (the code matched the plan byte-for-byte), but it bypasses the value of the workflow.
- **Orphaned test files broke `flutter test` (full suite).** `resume_listening_service_test.dart` and `source_error_mapper_test.dart` reference files deleted in commit `e3e1d92` ("remove continue listening panel"). They predate this milestone but were never cleaned up. Every regression gate had to explain "these 2 failures are pre-existing, not regressions." A 1-line `chore: remove orphaned test files` commit outside any phase would have saved that noise.
- **STATE.md `current_phase` drifted to "01"** while ROADMAP analysis correctly tracked Phase 3 as the active work. The resume-incomplete-phase scan in `/gsd-progress` caught this, but it indicates STATE.md updates lagged reality during the mid-milestone gap (2026-07-15 → 2026-07-27).

### Patterns Established

- **Catch-block canonical pattern:** `AppLogger.debug(...) + if(!mounted) return + ScaffoldMessenger.of(context).showSnackBar("Unable to start playback. Please try again.")` — now uniform across all 4 user-facing play-init call sites. Any new call site that invokes `initSongs` should match it.
- **Race-aware Hive write ordering:** all Hive `put` calls complete synchronously BEFORE any `await` in play-init paths (documented at `audiobook_details.dart:69-71`). The `MiniAudioPlayer.didChangeDependencies` partial-box race is real and this pattern prevents it.
- **`FakePlaybackEngine` as the test seam:** configurable `processingState` + broadcast `processingStates` stream + `processingStateStream` getter — the shape for any future `MyAudioHandler` unit test.
- **Gen-guard on async init:** `if (myGen != _initGen) return;` after every `await` in `initSongs` — protects against stale-init clobbering when a newer init supersedes during the await window.

### Key Lessons

- **A refactor phase that gets superseded is still valuable.** Phase 2's `_initSettleSub` work was removed in Phase 3 — but Phase 2 isolated the lifecycle cleanup so Phase 3 could remove the listener entirely and land a cleaner architecture. Document supersession (don't hide it) in verification reports.
- **"Minimal scope" is a load-bearing constraint.** The user explicitly chose "just fix it" — no loading-feedback UI, no cross-source hardening, no details-screen redesign. This kept the milestone to 4 phases / 5 plans / 1 production file changed in Phase 4. Resisting scope creep (deferred-items.md, REQUIREMENTS.md v2 list) was essential.
- **Run the full test suite early, not just the target suite.** The orphaned-test-file noise was discoverable on day 1. Catching it then would have saved re-explaining it at every regression gate.
- **Verification debt compounds.** Two phases shipping without VERIFICATION.md was recoverable (retrospective verification worked), but it required a dedicated step at milestone close. Run `/gsd-execute-phase` through to verification completion, not just to SUMMARY.

### Cost Observations

- **Model mix:** builtin:zai-coding-plan/GLM-5.2 throughout (orchestrator + all subagents via `general-purpose` fallback — `gsd-executor`/`gsd-verifier`/`gsd-planner`/`gsd-plan-checker` not registered in this workspace).
- **Sessions:** 1 multi-turn session covering `/gsd-progress` → `/gsd-execute-phase 3` → `/gsd-discuss-phase 4` → `/gsd-plan-phase 4` → `/gsd-execute-phase 4` → `/gsd-complete-milestone`.
- **Notable:** Subagent dispatches used `general-purpose` with full workflow context loaded inline (since GSD agent types weren't installed). This worked because the plans were narrow and well-specified. A complex multi-plan phase might benefit from the dedicated agent types.

## Cross-Milestone Trends

*(First milestone — trends will populate as v1.1+ ships.)*

| Milestone | Phases | Plans | Days | Suite (final) | Verified Closeout |
|-----------|--------|-------|------|----------------|-------------------|
| v1.0 | 4 | 5 | 14 | 18/18 playback_trust (+51/53 full, 2 pre-existing orphans) | ✓ verified |

---

*Retrospective started: 2026-07-28 (v1.0)*
