# Roadmap: Flow Book — Sound-Books Auto-Play Fix

## Overview

Fix the one source (Sound-Books) whose books don't auto-play on open. The bug lives in a single shared method (`MyAudioHandler.initSongs`) called by three entry points. The fix path: confirm the actual failure mechanism on-device and make the race reproducible in tests (Phase 1) → eliminate existing subscription leaks and state-guard clobber that the fix would otherwise widen (Phase 2) → restructure `initSongs` to await `ProcessingState.ready` before `play()` with bounded timeout and error surfacing (Phase 3) → verify no regressions across all 5 sources and lock the fix's invariants into automated tests (Phase 4).

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Diagnostic Verification + Test Infrastructure** - Confirm failure mechanism on-device; extend FakePlaybackEngine so the race is reproducible in tests
- [ ] **Phase 2: Subscription Lifecycle + State-Guard Cleanup** - Pure refactors: tracked subscriptions, gen-guarded finally, orphan-listener removal (no behavior change)
- [ ] **Phase 3: Ready-Before-Play Fix** - Restructure initSongs to await ready before play(); bounded timeout + error surfacing (THE fix)
- [ ] **Phase 4: Call-Site Consistency + Cross-Source Verification** - Big play button 2-line fix + manual smoke across all 5 sources + lock invariants in tests

## Phase Details

### Phase 1: Diagnostic Verification + Test Infrastructure
**Goal**: Confirm the actual failure mechanism on a real device and make the loading→ready race reproducible in the test suite — so the Phase 3 fix targets the right layer and is verifiable.
**Mode**: mvp
**Depends on**: Nothing (first phase)
**Requirements**: TEST-01
**Success Criteria** (what must be TRUE):
  1. A developer running `flutter test` can configure `FakePlaybackEngine` to emit a `loading → ready` `ProcessingState` transition, and observe the race condition in test output (a test that fails today and passes after the fix can be written).
  2. A developer opening a Sound-Books book on a real device with temporary diagnostic logs sees the exact `processingState` path, whether `setAudioSources` threw, and whether `audioSession.setActive(true)` succeeded — confirming or refuting the "play() dropped during buffering" hypothesis before the fix is written.
  3. Probe-duration logs across 3+ Sound-Books URLs confirm whether the 10s timeout default is appropriate (neither too short for slow networks nor too long for dead URLs).
**Plans**: TBD

Plans:
- [ ] 01-01: TBD

### Phase 2: Subscription Lifecycle + State-Guard Cleanup
**Goal**: Eliminate the existing subscription leaks and `_isReinitializing`-clobber race as pure refactors (no user-visible behavior change) so the Phase 3 await doesn't widen existing races.
**Mode**: mvp
**Depends on**: Phase 1
**Requirements**: PLAY-07, PLAY-08, PLAY-09
**Success Criteria** (what must be TRUE):
  1. Repeatedly opening books in one session (10+ opens) does not stack listeners — a track change after N opens triggers exactly one Hive write per change, not N (the `_listenForCurrentSongIndexChanges` leak and the 60s fire-and-forget cancel are gone).
  2. Rapidly switching book A → book B mid-load leaves `_isReinitializing` correctly set for the active init (book B), not clobbered by book A's stale `finally` block — opening book C immediately after behaves correctly.
  3. Opening any source's book plays exactly as before — users observe zero behavior change (the refactors are invisible); `playback_trust_test.dart` continues to pass.
**Plans**: TBD

Plans:
- [ ] 02-01: TBD

### Phase 3: Ready-Before-Play Fix
**Goal**: Opening a Sound-Books book starts playback automatically — the actual bug fix. Restructure `initSongs` to await `ProcessingState.ready` (with bounded timeout + error-state handling) before fire-and-forget `play()`.
**Mode**: mvp
**Depends on**: Phase 1, Phase 2
**Requirements**: PLAY-01, PLAY-02, PLAY-04, PLAY-05, PLAY-06, ERR-01, ERR-02
**Success Criteria** (what must be TRUE):
  1. Tapping a Sound-Books book in the browse or search list opens the details screen and playback begins automatically within ~10 seconds with zero extra taps — matching LibriVox/YouTube/knigavuhe/4read behavior.
  2. Tapping a Sound-Books book already in history (resume) opens the details screen and playback resumes at the saved position automatically — zero extra taps.
  3. Tapping the big circle play button on the Sound-Books details screen starts playback reliably on the first tap (no longer requires pressing twice).
  4. When a Sound-Books URL fails (404, corrupt MP3, network drop), the user sees a visible error message (SnackBar) instead of a silent no-op.
  5. Backing out of the details screen during the Sound-Books duration probe does not crash the app — `mounted` guards prevent `context` use after dispose.
**Plans**: TBD
**UI hint**: yes

Plans:
- [ ] 03-01: TBD

### Phase 4: Call-Site Consistency + Cross-Source Verification
**Goal**: Close the regression surface — make the big play button consistent with `_autoPlay`/`_playChapter`, run manual smoke across all 5 sources, and lock the fix's invariants into automated tests.
**Mode**: mvp
**Depends on**: Phase 3
**Requirements**: PLAY-03, TEST-02, TEST-03
**Success Criteria** (what must be TRUE):
  1. Opening a LibriVox, YouTube, knigavuhe, or 4read book auto-plays exactly as before the fix — no regression; tap-to-audio latency increase is under 100ms (await short-circuits synchronously for known-duration sources).
  2. The full `playback_trust_test.dart` suite (520 lines) passes — every pre-existing invariant preserved.
  3. New automated tests cover and pass: ready-before-play ordering, loading-state wait, gen-discard during wait, timeout fallback, tracked-subscription cancellation, and no orphan listeners.
  4. Manual smoke on a real device across all 5 sources confirms: Sound-Books auto-play on open, Sound-Books resume from history, Sound-Books big play button, Sound-Books chapter-list tap, and the other 4 sources' auto-play unchanged.
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Diagnostic Verification + Test Infrastructure | 0/1 | Not started | - |
| 2. Subscription Lifecycle + State-Guard Cleanup | 0/1 | Not started | - |
| 3. Ready-Before-Play Fix | 0/1 | Not started | - |
| 4. Call-Site Consistency + Cross-Source Verification | 0/1 | Not started | - |
