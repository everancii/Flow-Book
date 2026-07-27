# Phase 4: Call-Site Consistency + Cross-Source Verification - Context

**Gathered:** 2026-07-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Close the regression surface opened (and mostly closed) by the Phase 3 ready-before-play fix. The ROADMAP framed Phase 4 as three requirements (PLAY-03, TEST-02, TEST-03), but the Phase 3 execution landed more than expected — so the actual remaining scope is narrower and sharper.

**Reality check (from codebase scout at discussion time):**
- **TEST-02** (`playback_trust_test.dart` stays green): ✓ **Already done.** 18/18 tests pass, including the race detector (un-skipped) and the await-ready gate test. The 2 "pre-existing chapter-metadata failures" the Phase 3 plan flagged as acceptable were fixed by commit `15899f1`. No work remains here beyond verifying it stays green.
- **TEST-03** (6 invariant tests): **Partially landed.** Only 2 of the 6 named invariants exist as tests today (`gen-discard during await-ready` at line 474, `timeout fallback` at line 523). The Phase 3 SUMMARY's claim that all 6 landed is inaccurate — 4 are still missing. Whether to add them is a planner scope decision (see Deferred).
- **PLAY-03** (other 4 sources unchanged — manual smoke): On-device verification only. Cannot be automated. Requires the user.
- **Call-site consistency (the real remaining code work):** A scout of all `initSongs(` call sites found **two call sites outside Phase 3's blast radius** that the ROADMAP's "call-site consistency" success criterion covers:
  - `lib/screens/home/widgets/history_section.dart:170` — tap a book in the home history carousel. **Missed Phase 3's hardening.** This is the one real code change in Phase 4.
  - `lib/widgets/mini_audio_player.dart:97` — app-startup restore. **Already correct** (`playImmediately: false`, guarded by `_startupRestoreDone` + `isReinitializing`). No change needed.

**In scope:**
- Harden `history_section.dart:170` to match the `_autoPlay` pattern (async try/catch + mounted guard + SnackBar)
- Verify TEST-02 stays green after the history_section change
- Manual on-device PLAY-03 smoke across all 5 sources (user runs this; captured as UAT)

**Not in scope:**
- Adding the 4 missing TEST-03 invariant tests (see Deferred — planner may pull in if scope allows, but not required for phase completion)
- Deleting the 2 orphaned test files breaking `flutter test` full-suite (see Deferred — unrelated to Phase 4's requirements)
- Any change to `mini_audio_player.dart:97` (already correct)
- Loading-spinner UI, cross-source hardening, details-screen redesign (v2 deferred per REQUIREMENTS.md)

</domain>

<decisions>
## Implementation Decisions

### History-Section Tap Hardening (PLAY-04 consistency, ERR-02)
- **D-01:** Wrap the `onTap` body in `history_section.dart` (lines 155-179) in an `async` closure with `try/catch`, matching the `_autoPlay` pattern from `audiobook_details.dart:93-138`. The `initSongs(...)` call at line 170 gets `await` added.
- **D-02:** Catch block matches `_autoPlay` / `_playChapter` / big play button exactly:
  ```dart
  } catch (e) {
    AppLogger.debug('Error resuming audiobook from history: $e');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Unable to start playback. Please try again.')),
    );
  }
  ```
  - **Generic SnackBar message** ("Unable to start playback. Please try again.") — same as the other 3 call sites. Consistency over source-specificity; user can't act differently on a source-specific message anyway.
  - `HistorySection` is a `StatefulWidget` (`_HistorySectionState extends State<HistorySection>`) — so `mounted`, `context`, `ScaffoldMessenger.of(context)`, and `_weSlideController` are all available. The pattern is a near-mechanical copy.
- **D-03:** **Preserve the current Hive write order.** The existing code writes Hive values in two places around `initSongs`:
  - BEFORE (lines 162-166): `playingAudiobookDetailsBox.put('audiobook', ...)` + `put('audiobookFiles', ...)`
  - AFTER (lines 176-177): `put('index', hist.index)` + `put('position', hist.position)`
  
  Adding `await` to the `initSongs` call introduces the race that Phase 3's CONTEXT.md documented (comment at `audiobook_details.dart:69-71`): `MiniAudioPlayer.didChangeDependencies` can read a partially-updated box if writes straddle an await. **The planner must move the AFTER writes (index, position) to BEFORE the await**, so all four Hive writes complete synchronously before any `await`. The `_weSlideController.show()` call moves inside the try block AFTER the await (where it already is).
- **D-04:** `initSongs` keeps default `playImmediately: true` (same as `_autoPlay` and `_playChapter`). The user tapped a book — they want it to play. initSongs handles the ready-await + play internally per Phase 3 D-01.

### mini_audio_player.dart:97 — No Change
- **D-05 [informational]:** `mini_audio_player.dart:97` (app-startup restore) is **already correct and intentionally fire-and-forget**:
  - Uses `playImmediately: false` (user just opened the app, didn't tap anything — no auto-play desired)
  - Guarded by `_startupRestoreDone` static flag + `isReinitializing` check + `handlerIsEmpty` check (comment at lines 62-66 explains the re-fire race avoidance)
  - Runs inside `addPostFrameCallback` to avoid blocking startup
  - The silent error swallow on timeout/setAudioSources failure is **acceptable here** — a SnackBar on app startup would be obnoxious, and restore failure just means the user taps play manually
- **Do NOT add try/catch, mounted guard, or SnackBar to this call site.** It is not inconsistent — it has a different, correct intent.

### Manual Smoke (PLAY-03)
- **D-06:** PLAY-03 manual smoke is captured as a UAT artifact (`04-UAT.md`), not automated. The user runs it on a real device. Mandatory sources per ROADMAP Success Criterion 4:
  - Sound-Books: auto-play on open, resume from history, big play button, chapter-list tap
  - LibriVox, YouTube, knigavuhe, 4read: auto-play on open (unchanged)
- **D-07:** Pass bar for PLAY-03: zero regressions in the 4 non-Sound-Books sources; Sound-Books works across all 4 entry points. Tap-to-audio latency under 100ms for known-duration sources (await short-circuits synchronously per Phase 3 D-01).

### Claude's Discretion
- Whether to pull the 4 missing TEST-03 invariant tests into Phase 4 scope (see Deferred) — planner decides based on estimated effort vs. the single-code-change scope. Recommend NOT pulling them in; keep Phase 4 narrow.
- Exact line layout of the hardened history_section onTap — the pattern is fixed (D-01 through D-04), but minor reordering for readability is fine.
- Whether to add a regression test for the history_section onTap itself. The widget is a `StatefulWidget` with Hive + Provider dependencies — widget-testing it would require significant setup. **Recommend deferring** (see Deferred). The behavior is covered indirectly by the existing `playback_trust_test.dart` initSongs tests.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 3 Context (the fix this phase closes out)
- `.planning/phases/03-ready-before-play-fix/03-CONTEXT.md` — LOCKED decisions D-01 through D-12 for the ready-before-play fix. D-05 (timeout rethrow), D-07/D-08/D-11 (call-site consistency pattern), and D-10 (setAudioSources rethrows) are why history_section.dart now needs a catch block.
- `.planning/phases/03-ready-before-play-fix/03-01-SUMMARY.md` — documents the 3 call sites Phase 3 hardened (`_autoPlay`, `_playChapter`, big play button) and the race comment at `audiobook_details.dart:69-71`.

### Phase 3 Verification
- `.planning/phases/03-ready-before-play-fix/03-VERIFICATION.md` — 12/12 must-haves passed. Confirms the fix is in place; Phase 4 verifies it doesn't regress and closes the call-site gap.

### Requirements
- `.planning/REQUIREMENTS.md` §Auto-Play Reliability — PLAY-03 (other 4 sources unchanged), PLAY-04 (big play button — already done, this phase extends consistency to history_section). §Testability — TEST-02 (suite green), TEST-03 (invariant tests).

### Codebase Concerns
- `.planning/codebase/CONCERNS.md` §`MyAudioHandler` state machine — fragile-area note: read `playback_trust_test.dart` to understand invariants before any initSongs-adjacent change.
- `.planning/codebase/CONCERNS.md` §`AudiobookFile` model layer imports service layer — anti-pattern note, relevant if the planner considers touching the model.

### Source Code (file being modified)
- `lib/screens/home/widgets/history_section.dart` lines 140-180 (`_buildHistoryItem` → `onTap` — the hardening target). `HistorySection` is a `StatefulWidget`; `_HistorySectionState extends State<HistorySection>` has `mounted`, `context`, `_weSlideController`, `audioHandlerProvider` available.
- `lib/screens/audiobook_details/audiobook_details.dart` lines 93-138 (`_autoPlay` — the canonical pattern to copy). Lines 67-91 (`_playChapter`) and 520-565 (big play button) are the other two hardened call sites for reference.

### Source Code (file explicitly NOT modified)
- `lib/widgets/mini_audio_player.dart` lines 55-100 (`_restoreFromHive` / startup restore) — already correct (`playImmediately: false`, guarded). Do not modify.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_autoPlay` catch pattern** (`audiobook_details.dart:132-138`): the canonical `AppLogger.debug + if(!mounted) return + ScaffoldMessenger SnackBar` block. Phase 4 copies this verbatim into history_section.dart.
- **Race-aware Hive write ordering** (`audiobook_details.dart:69-71` comment + `_autoPlay` body): all Hive `put` calls happen synchronously BEFORE the first `await`. Phase 4 must replicate this in history_section.dart — the current code splits writes around `initSongs`, which is safe today (no await) but breaks once `await` is added.

### Established Patterns
- **All `initSongs` call sites in the app** (scout results):
  - `my_audio_handler.dart:834` — internal (skipToQueueItem / chapter seek) — already correct
  - `audiobook_details.dart:81` (`_playChapter`), `:113`/`:122` (`_autoPlay`), `:534`/`:544` (big button) — all hardened in Phase 3
  - `history_section.dart:170` — **the one remaining gap** (Phase 4 target)
  - `mini_audio_player.dart:97` — startup restore, intentionally `playImmediately: false`, no hardening needed
- **Gen-guard + race-comment pattern**: established in Phase 2/3 — any new `await initSongs(...)` site must ensure Hive writes complete before the await.

### Integration Points
- **`history_section.dart` onTap** → `audioHandlerProvider.audioHandler.initSongs(...)` → Phase 3's await-ready gate → `_player.play()`. The catch block catches anything D-05 (timeout) or D-10 (setAudioSources rethrow) propagates.
- **`_weSlideController.show()`** (line 179): moves inside the try block after the await — only show the player panel if init succeeded. On error, the panel stays hidden and the SnackBar explains why.

</code_context>

<specifics>
## Specific Ideas

- The user wants Phase 4 to be **narrow** — "minimal scope" is a recurring project constraint (AGENTS.md). The single code change (history_section hardening) is the entire implementation work. Everything else is verification.
- The generic SnackBar message was chosen over a source-specific one explicitly — consistency across all 4 play-init call sites matters more than debuggability from user reports. The `AppLogger.debug` line carries the source-specific context for log-file debugging.
- The user confirmed the Hive-write-ordering concern is real and must be handled (not just documented) — the planner cannot leave the index/position writes after the await.

</specifics>

<deferred>
## Deferred Ideas

- **The 4 missing TEST-03 invariant tests** — `playback_trust_test.dart` currently has 2 of the 6 invariants TEST-03 names (`gen-discard`, `timeout fallback`). Missing: ready-before-play ordering (partially covered by the existing race-detector test), loading-state wait (covered by the existing await-ready gate test), tracked-subscription cancellation, no orphan listeners. **Recommend deferring to a v1.1 polish phase** — Phase 3's await-ready gate made `_initSettleSub` (and thus "tracked-subscription cancellation" / "no orphan listeners") **obsolete** — those two invariants test infrastructure that no longer exists. The planner should verify this claim; if confirmed, those 2 invariants are N/A and TEST-03 is closer to complete than it appears.
- **Orphaned test files** — `test/resume_listening_service_test.dart` and `test/source_error_mapper_test.dart` reference files deleted in commit `e3e1d92` ("remove continue listening panel"). They break `flutter test` (full suite) with compile errors. **Not in Phase 4 scope** — they predate this milestone's bug fix entirely. Recommend a separate cleanup commit (`chore: remove orphaned test files referencing deleted services`) outside any phase, or a v1.1 cleanup phase.
- **Widget test for history_section onTap** — testing a `StatefulWidget` with Hive + Provider + WeSlideController dependencies is high-effort. The underlying `initSongs` behavior is already covered by `playback_trust_test.dart`. Defer unless the user explicitly wants widget-level coverage.
- **Loading spinner / buffering feedback** — v2 deferred per REQUIREMENTS.md.
- **Cross-source play-init hardening** — v2 deferred per REQUIREMENTS.md.

</deferred>

---

*Phase: 4-Call-Site Consistency + Cross-Source Verification*
*Context gathered: 2026-07-27*
