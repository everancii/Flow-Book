# Roadmap: Flow Book

## Milestones

- ✅ **v1.0 Sound-Books Auto-Play Fix** — Phases 1-4 (shipped 2026-07-28) — [Full details](milestones/v1.0-ROADMAP.md)
- 🚧 **v1.1 Cold-Restore Progress Bar Fix** — Phase 5 (in progress)

## Phases

<details>
<summary>✅ v1.0 Sound-Books Auto-Play Fix (Phases 1-4) — SHIPPED 2026-07-28</summary>

- [x] **Phase 1: Diagnostic Verification + Test Infrastructure** (2/2 plans) — completed 2026-07-14
  - Confirm failure mechanism on-device; extend FakePlaybackEngine so the race is reproducible in tests
- [x] **Phase 2: Subscription Lifecycle + State-Guard Cleanup** (1/1 plan) — completed 2026-07-15
  - Pure refactors: tracked subscriptions, gen-guarded finally, orphan-listener removal (no behavior change)
- [x] **Phase 3: Ready-Before-Play Fix** (1/1 plan) — completed 2026-07-27
  - Restructure initSongs to await ready before play(); bounded timeout + error surfacing (THE fix)
- [x] **Phase 4: Call-Site Consistency + Cross-Source Verification** (1/1 plan) — completed 2026-07-28
  - History-tap hardening (call-site consistency) + manual smoke across all 5 sources + verify TEST-02/TEST-03

**Outcome:** Opening a Sound-Books book (and any book from any source) now auto-plays in one gesture. Root cause (`play()` dropped during `loading`/`buffering`) fixed via `await ProcessingState.ready` gate. All 4 user-facing play-init call sites share the canonical error-handling pattern. `playback_trust_test.dart` green at 18/18.

**Handoff:** PLAY-03 on-device manual smoke captured in `04-UAT.md` — run before release.

</details>

### 🚧 v1.1 Cold-Restore Progress Bar Fix (In Progress)

**Milestone Goal:** After quitting the app and returning to the last-played book, pressing play resumes at the saved position *and* the progress bar reflects that position correctly from the first frame.

#### Phase 5: Cold-Restore Position-Stream Bridge Fix
**Goal**: Fix the position-stream bridge between the forked just_audio's deferred-load path and the UI's `ProgressBarWidget` so the progress bar reflects the restored position immediately after cold-restore + play.
**Depends on**: Phase 4 (v1.0 complete; shared `initSongs` / `play()` / `getPositionStream()` code is stable)
**Requirements**: RESTORE-01
**Mode**: standard
**Success Criteria** (what must be TRUE):
  1. After quitting and returning to the last-played book, pressing play shows the progress bar at the saved position (not 0:00) within 1 second of playback starting — for every source whose audio already restores correctly today (LibriVox, YouTube, 4read, knigavuhe, Sound-Books, local/download).
  2. The total duration and remaining-time label render correct non-zero values after cold-restore + play.
  3. Dragging the progress bar to seek still works correctly after a cold-restore + play (no jump-back, no stuck thumb).
  4. `playback_trust_test.dart` stays green — including the `playImmediately: false` "NO seek before deferred load" invariant and the restore test.
**Plans**: 1 plan

Plans:
- [ ] 05-01: Diagnose deferred-load position-stream gap, fix the bridge, add regression test

## Progress

**Execution Order:**
Phases execute in numeric order. v1.0 (1-4) shipped; v1.1 continues at Phase 5.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Diagnostic Verification + Test Infrastructure | v1.0 | 2/2 | Complete | 2026-07-14 |
| 2. Subscription Lifecycle + State-Guard Cleanup | v1.0 | 1/1 | Complete | 2026-07-15 |
| 3. Ready-Before-Play Fix | v1.0 | 1/1 | Complete | 2026-07-27 |
| 4. Call-Site Consistency + Cross-Source Verification | v1.0 | 1/1 | Complete | 2026-07-28 |
| 5. Cold-Restore Position-Stream Bridge Fix | v1.1 | 0/1 | Not started | - |
