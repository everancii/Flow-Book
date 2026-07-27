# Roadmap: Flow Book

## Milestones

- ✅ **v1.0 Sound-Books Auto-Play Fix** — Phases 1-4 (shipped 2026-07-28) — [Full details](milestones/v1.0-ROADMAP.md)

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

### 🚧 Next Milestone

(Not yet planned — run `/gsd-new-milestone` to start questioning → research → requirements → roadmap.)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Diagnostic Verification + Test Infrastructure | v1.0 | 2/2 | Complete | 2026-07-14 |
| 2. Subscription Lifecycle + State-Guard Cleanup | v1.0 | 1/1 | Complete | 2026-07-15 |
| 3. Ready-Before-Play Fix | v1.0 | 1/1 | Complete | 2026-07-27 |
| 4. Call-Site Consistency + Cross-Source Verification | v1.0 | 1/1 | Complete | 2026-07-28 |
