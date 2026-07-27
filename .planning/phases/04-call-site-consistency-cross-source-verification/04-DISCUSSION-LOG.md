# Phase 4: Call-Site Consistency + Cross-Source Verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-27
**Phase:** 4-Call-Site Consistency + Cross-Source Verification
**Areas discussed:** Scope-reality check, Newly-found call sites (history_section.dart), Snack placement, Hive write order

---

## Scope-reality check (which gray areas to discuss)

The ROADMAP framed Phase 4 as three requirements (PLAY-03, TEST-02, TEST-03), but a codebase scout at discussion time revealed most of the work already landed in Phase 3's commits:

| Area | Option | Selected |
|--------|-------------|----------|
| Newly-found call sites | history_section.dart:170 + mini_audio_player.dart:97 missed Phase 3's blast radius — harden or defer? | ✓ |
| Orphaned test files | resume_listening_service_test.dart + source_error_mapper_test.dart break `flutter test` (reference deleted files) | |
| TEST-03 gap coverage | Only 2 of 6 named invariant tests exist; add the missing 4? | |
| PLAY-03 manual smoke scope | On-device verification across 5 sources — structure, pass bar | |

**User's choice:** Newly-found call sites only.
**Notes:** User confirmed the other three areas are either already done (TEST-02), out of scope (orphaned files predate the milestone), or verification-only (PLAY-03 smoke, TEST-03 gap). Focusing on the one real code-change decision keeps Phase 4 narrow per the project's "minimal scope" constraint.

---

## Newly-found call sites (history_section.dart:170)

| Option | Description | Selected |
|--------|-------------|----------|
| Harden history_section now | Wrap onTap in async try/catch matching _autoPlay pattern. Catches D-05 timeout rethrow + D-10 setAudioSources rethrow. mini_audio_player left as-is (already correct). | ✓ |
| Defer to v2 | Leave fire-and-forget; document the uncaught-rethrow edge case. Smaller Phase 4 blast radius. | |
| Harden both call sites | Also wrap mini_audio_player.dart:97's restore path defensively (even though playImmediately:false is correct). Broader consistency pass. | |

**User's choice:** Harden history_section now.
**Notes:** The gap is real and narrow: after Phase 3, history-tap auto-plays correctly, but a timeout or setAudioSources failure now throws uncaught in the async gap (silent failure, no SnackBar). The fix is a mechanical copy of the `_autoPlay` pattern Phase 3 already established. `mini_audio_player.dart:97` was explicitly left alone — it's correct by intent (`playImmediately: false` on startup restore), not by oversight.

---

## Snack placement (SnackBar message text)

| Option | Description | Selected |
|--------|-------------|----------|
| Generic message | "Unable to start playback. Please try again." — matches _autoPlay / _playChapter / big button. Consistent across all 4 call sites. | ✓ |
| Source-specific message | "Unable to resume this book. Please try again." — user knows it was the history-tap path that failed. More debuggable from user reports. | |

**User's choice:** Generic message.
**Notes:** Consistency won. The user can't act differently on a source-specific message anyway (the action is always "retry"), and `AppLogger.debug` carries the source-specific context for log-file debugging.

---

## Hive write order (race-aware ordering)

| Option | Description | Selected |
|--------|-------------|----------|
| Preserve current Hive order | Leave writes where they are, but move the AFTER writes (index, position) to BEFORE the await. Matches Phase 3's documented race-avoidance pattern. | ✓ |
| Mirror _autoPlay exactly | Reorganize to exactly match _autoPlay's structure. More consistency, but risks the race if any write strays after the await. | |

**User's choice:** Preserve current Hive order (with the index/position move).
**Notes:** The current code splits Hive writes around `initSongs` (audiobook+audiobookFiles before, index+position after). That's safe today because there's no `await`. Adding `await initSongs(...)` introduces the race Phase 3's CONTEXT.md documented (MiniAudioPlayer.didChangeDependencies can read a partially-updated box). The planner must move all 4 writes before the await — not reorganize the method to mirror _autoPlay, just fix the ordering.

---

## Claude's Discretion

- Whether to pull the 4 missing TEST-03 invariant tests into Phase 4 scope — **recommend NOT pulling in.** Two of the four ("tracked-subscription cancellation", "no orphan listeners") test `_initSettleSub` infrastructure that Phase 3 removed; they're likely N/A. Planner should verify.
- Exact line layout of the hardened onTap — pattern is fixed (D-01 through D-04), minor reordering for readability is fine.
- Whether to add a widget test for history_section onTap — **recommend deferring.** The underlying initSongs behavior is covered by playback_trust_test.dart; widget-testing a StatefulWidget with Hive + Provider + WeSlideController deps is high-effort.

## Deferred Ideas

- 4 missing TEST-03 invariant tests → v1.1 polish phase (2 of 4 likely N/A after Phase 3 removed _initSettleSub)
- Orphaned test files (resume_listening_service_test, source_error_mapper_test) → separate cleanup commit or v1.1 phase; predate this milestone
- Widget test for history_section onTap → defer unless explicitly requested
- Loading spinner / buffering feedback → v2 (REQUIREMENTS.md)
- Cross-source play-init hardening → v2 (REQUIREMENTS.md)
