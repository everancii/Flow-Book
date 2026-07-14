# Requirements: Flow Book — Sound-Books Auto-Play Fix

**Defined:** 2026-07-14
**Core Value:** Tap a book from any source and it plays — discover to playback in one gesture.

## v1 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Auto-Play Reliability

- [ ] **PLAY-01**: Opening a Sound-Books book from browse or search starts playback automatically — zero extra taps, matching LibriVox/YouTube/knigavuhe/4read behavior
- [ ] **PLAY-02**: Opening a Sound-Books book already in history (resume) auto-plays at the saved position
- [ ] **PLAY-03**: LibriVox, YouTube, knigavuhe, and 4read auto-play continue to work unchanged (no regression)
- [ ] **PLAY-04**: The big circle play button on the details screen calls `play()` after `initSongs` (matches `_playChapter` and `_autoPlay` — currently inconsistent)

### Play-Init Sequence

- [ ] **PLAY-05**: `MyAudioHandler.initSongs` awaits `ProcessingState.ready` (via `processingStateStream.firstWhere` — BehaviorSubject replays current state, so known-duration sources short-circuit synchronously with zero added latency) before calling `_player.play()`
- [ ] **PLAY-06**: The await has a bounded timeout (10s); on timeout, emits error state instead of hanging forever
- [ ] **PLAY-07**: The `finally { _isReinitializing = false; }` block is guarded with `if (myGen == _initGen)` so a stale init doesn't clobber a newer init's flag (precondition — the new await widens the clobber window)
- [ ] **PLAY-08**: The 60-second fire-and-forget `Future.delayed` listener-cancel (`my_audio_handler.dart:608`) is replaced with a tracked `StreamSubscription` cancelled at the top of the next `initSongs` and in `stop()` (precondition — current code stacks on re-entry)
- [ ] **PLAY-09**: The orphan `processingStateStream.listen` at `my_audio_handler.dart:611` (logs only, never cancelled) is removed (precondition — leaks a subscription per `initSongs` call)

### Error Surfacing

- [ ] **ERR-01**: `setAudioSources` is wrapped in try/catch; `PlayerException` from a failed duration probe (404, corrupt MP3, network error) surfaces a user-visible error instead of a silent no-op
- [ ] **ERR-02**: `_autoPlay` and `_playChapter` in the details screen guard `context` use after `await` with `if (!mounted) return`

### Testability

- [x] **TEST-01**: `FakePlaybackEngine` is extended to simulate a `loading → ready` `ProcessingState` transition (precursor — the fix is untestable without it, since the fake currently always reports `ready`)
- [ ] **TEST-02**: `playback_trust_test.dart` (520 lines) stays green — all existing assertions preserved
- [ ] **TEST-03**: New test cases cover: ready-before-play ordering, loading-state wait, gen-discard during wait, timeout fallback, tracked-sub cancellation, no orphan listeners

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

- Loading spinner / buffering feedback for non-YouTube sources
- Cross-source play-init hardening
- Skip details screen → straight to player
- Unifying `_waitForProcessingReady` (poll) with `_waitForReadyOrTimeout` (stream-listener)
- True `dispose()` for `MyAudioHandler`
- `_listenForCurrentSongIndexChanges` listener leak (line 683) — flagged in research but outside this fix's blast radius

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Details-screen redesign | User wants to keep opening the details screen; just wants auto-play |
| Cross-source refactor (boolean source flags → enum) | Explicitly deferred — minimal scope |
| Hive repository facade | Explicitly deferred — not related to play-init |
| `AudioHandlerProvider` cold-start race fix | Explicitly deferred — document, don't worsen |
| Crash reporting integration | Explicitly deferred — separate milestone |
| Other 4 active OpenSpec changes | Tracked separately under openspec/ |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PLAY-01 | Phase 3 | Pending |
| PLAY-02 | Phase 3 | Pending |
| PLAY-03 | Phase 4 | Pending |
| PLAY-04 | Phase 3 | Pending |
| PLAY-05 | Phase 3 | Pending |
| PLAY-06 | Phase 3 | Pending |
| PLAY-07 | Phase 2 | Pending |
| PLAY-08 | Phase 2 | Pending |
| PLAY-09 | Phase 2 | Pending |
| ERR-01 | Phase 3 | Pending |
| ERR-02 | Phase 3 | Pending |
| TEST-01 | Phase 1 | Complete |
| TEST-02 | Phase 4 | Pending |
| TEST-03 | Phase 4 | Pending |

**Coverage:**

- v1 requirements: 14 total
- Mapped to phases: 14 ✓
- Unmapped: 0

---
*Requirements defined: 2026-07-14*
*Last updated: 2026-07-14 after initial definition*
