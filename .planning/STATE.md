---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Cold-Restore Progress Bar Fix
status: planning
last_updated: "2026-08-03T10:32:17.891Z"
last_activity: 2026-08-03
progress:
  total_phases: 1
  completed_phases: 0
  total_plans: 1
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-03)

**Core value:** Tap a book from any source and it plays — discover to playback in one gesture.
**Current focus:** Phase 05 — cold-restore-position-stream-bridge-fix

## Current Position

Phase: 5 (Cold-Restore Position-Stream Bridge Fix)
Plan: 05-01 (not started)
Status: Roadmap approved — ready to plan
Last activity: 2026-08-03 — Milestone v1.1 roadmap created (Phase 5, 1 plan)

## Performance Metrics

**Velocity:**

- Total plans completed: 2
- Average duration: 3 min
- Total execution time: 0.05 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 03 | 1 | - | - |
| 04 | 1 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 01 P01 | 3 min | 2 tasks | 2 files |
| Phase 01 P02 | 12 | - tasks | - files |

## Accumulated Context

### Decisions

Decisions logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Fix lives in `MyAudioHandler.initSongs` play sequence, not the details screen
- [Roadmap]: 4-phase order — test infra + diagnostic → lifecycle cleanup → core fix → verification (research-backed dependency chain)
- [Roadmap]: Phase 2 preconditions before Phase 3 — existing races would widen under the new await
- [Phase 01]: Used skip: parameter instead of @Skip annotation before test() — @Skip is invalid Dart before a call expression; preserved literal @Skip string in comment for acceptance grep — 01-01: @Skip annotation invalid before test() call — used skip: parameter, kept literal in comment
- [Phase 01]: Did NOT fix 2 pre-existing chapter-switching-metadata test failures — verified pre-existing via git stash on clean baseline; out of scope per deviation rule; logged to deferred-items.md — 01-01: pre-existing failures out of scope — would mask future regressions but unrelated to Sound-Books race
- [Phase ?]: macOS diagnostic: race confirmed (play during buffering 4/5 books), audio plays on macOS, audioSession.setActive reversion unconfirmed (Android-specific)
- [Phase ?]: Phase 3 fix layer: ready-before-play await correct — eliminates race on all platforms
- [Phase 03]: D-01 through D-12 implemented exactly as locked — await processingStateStream.firstWhere(ready).timeout(10s) before play(); BehaviorSubject replay gives zero-latency for known-duration sources; Sound-Books waits until ready or 10s
- [Phase 03]: Phase 2 _initSettleSub listener machinery superseded and removed — the one-shot firstWhere replaces the tracked subscription; cancel sites + bufferingStarted local deleted
- [Phase 03]: Big play button made explicit (playImmediately:false + await play()) rather than relying on internal mechanism — clearer intent, testable
- [Phase 03]: All three call sites (_playChapter, _autoPlay, big button) now share the canonical caller-catches + mounted guard + SnackBar pattern
- [Phase 04]: D-01 through D-07 implemented exactly as locked — history_section.dart onTap hardened to the canonical _autoPlay pattern (async try/catch + await + mounted guard + SnackBar); all 4 Hive writes relocated before the await (D-03 race avoidance); all four user-facing play-init call sites now consistent; mini_audio_player.dart left untouched (D-05)
- [Phase 04]: TEST-02 stays 18/18; TEST-03 satisfied (2 landed invariant tests pass + 4 N/A confirmed via _initSettleSub grep=0); PLAY-03 captured as 04-UAT.md manual smoke (8-row matrix, <100ms pass bar, dead-URL error-path check) — pending user sign-off on real device

### Pending Todos

None yet.

### Blockers/Concerns

- Pitfall 1: root-cause mechanism ("play() dropped during buffering") is a hypothesis, not debugger-confirmed. Phase 1 diagnostic step must verify before Phase 3 fix is written.
- Pitfall 10: `AudioHandlerProvider` cold-start race (throwaway handler between `runApp` and `initialize()`) — explicitly out of scope; Phase 4 verifies the fix doesn't worsen it.

## Deferred Items

Items acknowledged and carried forward (v2 / out-of-scope):

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2 | Loading spinner / buffering feedback for non-YouTube sources | Deferred | 2026-07-14 |
| v2 | Cross-source play-init hardening | Deferred | 2026-07-14 |
| v2 | Skip details screen → straight to player | Deferred | 2026-07-14 |
| v2 | Unify `_waitForProcessingReady` (poll) with `_waitForReadyOrTimeout` (stream) | Deferred | 2026-07-14 |
| v2 | True `dispose()` for `MyAudioHandler` | Deferred | 2026-07-14 |
| v2 | `_listenForCurrentSongIndexChanges` listener leak (line 683) — outside fix blast radius | Deferred | 2026-07-14 |
| OOS | `AudioHandlerProvider` cold-start race | Document, don't worsen | 2026-07-14 |
| OOS | 4 active OpenSpec changes | Tracked separately | 2026-07-14 |

## Session Continuity

Last session: 2026-08-03
Stopped at: Milestone v1.1 initialized — Phase 5 roadmap approved, ready to plan
Resume file: .planning/ROADMAP.md

## Operator Next Steps

- Plan Phase 5 with `/gsd:plan-phase 5`
- Or discuss context first with `/gsd:discuss-phase 5`
