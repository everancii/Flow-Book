# Project Research Summary

**Project:** Flow Book — Sound-Books auto-play race fix
**Domain:** Brownfield bug fix in a shipped Flutter audiobook player (just_audio / audio_service play-init race)
**Researched:** 2026-07-14
**Confidence:** HIGH (with one MEDIUM gap — root-cause mechanism not directly observed in a debugger)

## Executive Summary

Flow Book v1.2.0 is a shipped Flutter audiobook player supporting five sources (LibriVox, YouTube, knigavuhe, 4read, Sound-Books). Four auto-play on open; Sound-Books silently no-plays. The bug lives in one method — `MyAudioHandler.initSongs` (`my_audio_handler.dart:416`) — the shared play-init sequence called by three entry points (`_autoPlay`, `_playChapter`, big play button). The stack is pinned and correct: forked `just_audio` (`sagarchaulagai/just_audio@a6f8db8`) is upstream-equivalent for all play/load/`ProcessingState` APIs (verified by line-by-line source diff; only `setBalance` is added). No new dependencies. The fix uses existing APIs: `processingStateStream.firstWhere(ready).timeout(10s)` before `play()`, replacing the current fire-and-forget `play()` + redundant re-fire listener.

The recommended approach: reorder `initSongs` to await `ProcessingState.ready` (with a bounded timeout + error-state handling) BEFORE calling `_player.play()` fire-and-forget. For sources with known duration (LibriVox/YouTube/knigavuhe/4read/local), `setAudioSources` already resolves at `ready`, so the await short-circuits synchronously — zero added latency. For Sound-Books (`length: 0`, unknown duration), `setAudioSources` resolves at `buffering` and the await blocks until the duration probe completes and `ready` fires. Alongside the reorder, three subscription-lifecycle bugs (the 60s fire-and-forget cancel, the orphan logging listener, the `_listenForCurrentSongIndexChanges` leak) and one `_isReinitializing`-clobbered-by-finally bug must be fixed as preconditions — they widen the race window if left alone.

Key risks: (1) the PROJECT.md root-cause hypothesis ("play() dropped during buffering") is plausible but unverified on-device — Pitfall 1 warns the actual failure may be `setAudioSources` throwing, `audioSession.setActive` failing, or a fork load-interruption quirk; a diagnostic step must precede the fix. (2) `FakePlaybackEngine` defaults to `processingState = ready` and never emits the `loading → ready` transition, so the fix is untestable until the fake is extended — a precursor. (3) Awaiting `play()` (instead of fire-and-forget) blocks `initSongs` until the track ends — a code-review guard. (4) `AudioHandlerProvider` cold-start race (throwaway handler) is out of scope but the fix must not widen its window by deferring `play()` to a detached listener.

## Key Findings

### Recommended Stack

No stack changes. The fix uses only APIs already in the pinned `pubspec.yaml`. See STACK.md for full rationale and fork-diff verification.

**Core APIs (already in place):**
- `AudioPlayer.setAudioSources(sources, preload: true, initialIndex, initialPosition)` — loads playlist, resolves when `processingState` leaves `loading` (for Sound-Books, that's `buffering`, not `ready`)
- `AudioPlayer.processingStateStream.firstWhere((s) => s == ProcessingState.ready)` — the key gate. Backed by `BehaviorSubject.seeded(idle)` so it replays current state to new subscribers → never misses the `ready` transition; returns synchronously if already `ready`
- `.timeout(Duration(seconds: 10))` on the ready-wait — prevents indefinite hang on dead URL / stall; falls through to `play()` with the 30s buffering-skip backstop retained
- `AudioPlayer.play()` fire-and-forget — sets `playing = true` synchronously, sends platform play request. Future completes on playback END, not start — must NOT be awaited for readiness
- `dart:async` `TimeoutException` — only new import (already at `my_audio_handler.dart:2`)

**What NOT to do:** no new packages, no `play()` await, no post-play re-fire listener, no 50ms polling loop, no fix in the details screen or `play()` override.

### Expected Features

This is a fix-scope feature landscape, not greenfield. See FEATURES.md for the full table-stakes / differentiator / anti-feature breakdown and 10 edge cases.

**Must have (table stakes — fix counts as done only if all hold):**
- TS-1: Sound-Books book auto-plays on open — zero extra taps (the bug)
- TS-2: Playback begins within reasonable time (comparable to other sources)
- TS-3: Resume case preserved for Sound-Books (history → seek to saved position → play)
- TS-4: Other 4 sources' auto-play unchanged (regression smoke per source)
- TS-5: Big play button still works for Sound-Books
- TS-6: Chapter-list tap still works for Sound-Books
- TS-7: Probe failure shows visible error (not silent no-op — currently `_autoPlay` catch only logs)
- TS-8: `playback_trust_test.dart` (520 lines) passes unchanged

**Edge cases that must be handled (P1):**
- EC-1: Back-navigation during probe doesn't crash (`mounted` / dispose guards)
- EC-2: `initSongs` re-entry gen-discard (listener + cancel timer must be gen-guarded)
- EC-5: 60s listener-cancel bug fixed (tracked subscription lifecycle, not fire-and-forget)
- EC-8: `_autoPlay` double `play()` consolidated to single initiation point

**Defer (explicitly out per PROJECT.md "just fix it"):**
- Loading spinner / buffering % for non-YouTube sources
- Cross-source play-init hardening (verification scope stays Sound-Books)
- Auto-play user preference toggle
- Predictive duration probe in details service
- Details-screen redesign

### Architecture Approach

The fix is localized to `MyAudioHandler.initSongs` plus two new private fields and one new private helper. No interface changes to `PlaybackEngine` (the testable seam over just_audio) — adding `waitForReady()` there would push state-machine concerns into the Strategy layer and force `FakePlaybackEngine` to implement it. All three call sites (`_playChapter`, `_autoPlay`, big play button) route through `initSongs`, so fixing it once fixes all sources. See ARCHITECTURE.md for the full 6-step build order and corrected 43-step data-flow sequence.

**Major components:**
1. `MyAudioHandler.initSongs` — RESTRUCTURE play sequence: `setAudioSources → seek → waitForReadyOrTimeout → play() → tracked settle listener` (replaces `setAudioSources → play() → listen(ready→play)` race)
2. `MyAudioHandler._waitForReadyOrTimeout` (NEW) — awaitable helper: returns immediately if already `ready`, else listens for `ready`/`error` with a bounded timeout; caller gen-checks after await
3. `MyAudioHandler._initSettleSub` / `_initSettleTimeout` (NEW fields) — tracked lifecycle for post-play runtime-recovery listener (buffering-stuck-30s-skip, idle recovery); replaces fire-and-forget `Future.delayed(60s, sub.cancel())`
4. `AudiobookDetails` big play button — MINOR: add `await play()` after `initSongs` for consistency with `_playChapter`/`_autoPlay` (2-line change, belt-and-suspenders)
5. `FakePlaybackEngine` (test) — EXTEND: support configurable initial `processingState` + emit `ready` on `processingStates` stream after a delay (no class-definition change needed; existing mutable field + stream controller sufficient)
6. `PlaybackEngine` / `JustAudioPlaybackEngine` — UNCHANGED

**Patterns to follow:**
- Generation-counter discard at every await point (existing; fix adds one new checkpoint after the ready-wait)
- Awaitable ready-gate with timeout fallback (new — `_waitForReadyOrTimeout`)
- Tracked subscription lifecycle (new — `_initSettleSub`/`_initSettleTimeout` cancelled at top of next `initSongs` and in `stop()`)
- Gen-guarded `finally` (new — `if (myGen == _initGen) _isReinitializing = false;`)

### Critical Pitfalls

Top pitfalls from PITFALLS.md (12 total). The first three are preconditions — the fix is unsafe without them.

1. **Wrong race mechanism (Pitfall 1)** — PROJECT.md's "play() dropped during buffering" is a hypothesis, not confirmed. The official just_audio design says `play()` during `buffering` should work (sets `playing=true`, audio starts at `ready`). Actual cause may be `setAudioSources` throwing, `audioSession.setActive` failing, or a fork load-interruption quirk. **Avoid:** add diagnostic logging at `play()` entry/exit, `setAudioSources` return, `processingState` transitions, `audioSession.setActive()` result; test on real device with a Sound-Books URL BEFORE writing the fix.

2. **`_isReinitializing` clobbered by unconditional `finally` (Pitfall 2)** — `finally { _isReinitializing = false; }` at `:640` runs even when the current init hit a gen check and returned early. A newer `initSongs` still in flight loses its flag → spurious restores/persists for the wrong audiobook. The fix's new await WIDENS this race window. **Avoid:** guard with `if (myGen == _initGen) _isReinitializing = false;`. Must be fixed as a precondition.

3. **`FakePlaybackEngine` can't test the fix (Pitfall 6)** — defaults `processingState = ready`, never emits `loading → ready`. The race is invisible in tests; the fix is untestable as-is. **Avoid:** extend the fake to support configurable initial `processingState` + emit `ready` after a delay BEFORE the implementation phase. Blocking precursor.

4. **Await-for-ready deadlock on error (Pitfall 8)** — `firstWhere(ready)` hangs forever on 404 / corrupt MP3 / network drop (state goes to `error`, not `ready`). **Avoid:** listen for `ready || error`, wrap in `.timeout(10s)`, check `_player.processingState == error` after await and abort with user-visible error.

5. **`play()` awaited blocks `initSongs` until track ends (Pitfall 12)** — `play()`'s Future completes on playback END, not start. **Avoid:** always fire-and-forget `_player.play();` — never `await _player.play()` inside `initSongs`. Code-review guard.

6. **60s `Future.delayed` listener cancel creates orphaned subscriptions (Pitfall 3)** — fire-and-forget, stacks on re-entry, stale listeners re-fire `play()` / `seekToNext()` on the new book. **Avoid:** tracked `_initSettleSub` field, cancelled at top of next `initSongs` and in `stop()`.

7. **Orphan logging listener at `:611` leaks per `initSongs` call (Pitfall 4)** — bare `.listen()` never cancelled, N listeners after N opens. **Avoid:** delete lines 611-613 entirely (the functional listener at 569 already logs).

8. **`_listenForCurrentSongIndexChanges` leaks a `currentIndexStream` listener per `initSongs` (Pitfall 5)** — N Hive writes per track change after N opens. **Avoid:** track in `_indexChangeSub` field, cancel at top of `initSongs`.

9. **`seek()` is a silent no-op during `ProcessingState.loading` (Pitfall 7)** — fork's `seek()` returns immediately if state is `loading`; resume position lost. **Avoid:** never seek before `setAudioSources` completes; verify seek took effect after.

10. **30s stuck-buffering skip fires spuriously on slow networks / stale listeners (Pitfall 11)** — listener at 569 doesn't gen-check before `seekToNext()`. **Avoid:** add `if (myGen != _initGen) return;` inside listener callback; reconsider the 30s threshold.

## Implications for Roadmap

Based on the combined research, the fix has clear internal dependencies that dictate phase ordering. The ARCHITECTURE.md 6-step build order plus the PITFALLS.md precondition/precursor flags map to four phases.

### Phase 1: Diagnostic Verification + Test Infrastructure

**Rationale:** Pitfall 1 (root cause unverified) and Pitfall 6 (fake can't test the fix) are both blocking — the implementation phase cannot safely proceed without them. This is the cheapest phase and de-risks everything after it.
**Delivers:** (a) Device-confirmed failure mechanism via temporary logging at `play()`/`setAudioSources`/`processingState`/`audioSession.setActive()` for a real Sound-Books URL. (b) Extended `FakePlaybackEngine` supporting configurable initial `processingState` + `loading → ready` emission. (c) New test cases for ready-before-play ordering, gen-discard, timeout, and `playImmediately: false` paths (written but potentially failing until Phase 3).
**Addresses:** TS-8 (test infrastructure), Pitfall 1, Pitfall 6
**Avoids:** writing a fix for the wrong mechanism; shipping an untestable fix

### Phase 2: Subscription Lifecycle + State-Guard Cleanup

**Rationale:** Three subscription leaks (Pitfalls 3, 4, 5) and the `_isReinitializing` clobber (Pitfall 2) are existing bugs that the Phase 3 await widens. Fixing them first as pure refactors (no behavior change) isolates risk — if something breaks, it's subscription management, not play logic. ARCHITECTURE.md steps 1-2.
**Delivers:** (a) `_initSettleSub` / `_initSettleTimeout` fields with top-of-`initSongs` + `stop()` teardown, replacing `Future.delayed(60s)`. (b) Deletion of orphan logging listener at `:611`. (c) `_indexChangeSub` tracked field for `_listenForCurrentSongIndexChanges`. (d) Gen-guarded `finally { if (myGen == _initGen) _isReinitializing = false; }`. (e) Gen check inside the 30s-skip listener callback (Pitfall 11). (f) All existing `playback_trust_test.dart` tests still pass.
**Addresses:** EC-2, EC-5, Pitfalls 2, 3, 4, 5, 11 (partial)
**Avoids:** race window widening; stacked listeners re-firing on the wrong book

### Phase 3: Ready-Before-Play Fix (Core)

**Rationale:** This is the actual bug fix. Depends on Phase 1 (test infra) and Phase 2 (lifecycle cleanup). ARCHITECTURE.md steps 3-5.
**Delivers:** (a) `_waitForReadyOrTimeout(myGen, 10s)` helper that listens for `ready || error` with timeout. (b) Restructured `initSongs` play sequence: `setAudioSources → seek → waitForReadyOrTimeout → gen-check → play() fire-and-forget → tracked settle listener (runtime recovery only, no ready→play re-fire)`. (c) Error-state handling: on `ProcessingState.error` after await, abort with user-visible error (TS-7). (d) `try/catch` around `setAudioSources` surfacing `PlayerException` as a SnackBar (TS-7). (e) `mounted` / dispose guards in `_autoPlay` for back-navigation during probe (EC-1). (f) Consolidated single play-initiation point (EC-8 — `initSongs` returns after `ready` so external `play()` is a no-op). (g) New tests pass: ready-before-play ordering, gen-discard, timeout, error-state, `playImmediately: false`.
**Uses:** `processingStateStream.firstWhere` + `.timeout` + `TimeoutException` (dart:async, already imported)
**Implements:** `MyAudioHandler.initSongs` restructure, `_waitForReadyOrTimeout` helper
**Addresses:** TS-1, TS-2, TS-3, TS-7, EC-1, EC-2, EC-4, EC-8, Pitfalls 7, 8, 9, 12
**Avoids:** cross-source latency regression (short-circuit on `ready`); awaiting `play()`; deadlock on error; seek no-op during loading

### Phase 4: Call-Site Consistency + Cross-Source Verification

**Rationale:** The big play button inconsistency (ARCHITECTURE.md step 6) is independent and cosmetic now that `initSongs`'s internal `play()` is reliable. Cross-source + history-entry verification closes the regression surface. Can run partly in parallel with Phase 3's tail.
**Delivers:** (a) `await audioHandlerProvider.audioHandler.play();` added after both `initSongs` calls in big play button `onTap` (`:532`, `:543`). (b) Manual smoke: Sound-Books auto-play on open (TS-1), resume (TS-3), play button (TS-5), chapter tap (TS-6), history-section tap (EC-10). (c) Manual smoke: LibriVox/YouTube/knigavuhe/4read auto-play unchanged + tap-to-audio latency before/after <100ms increase (Pitfall 9). (d) Cold-start test: launch app, immediately open Sound-Books book, verify media notification appears (Pitfall 10 — document, don't fix). (e) Slow-network test: throttle to 56k, open long Sound-Books book, verify playback starts after probe (EC-5 regression check). (f) Rapid double-open test: book A then book B within 1s, verify B plays, no stale `play()` (EC-2).
**Addresses:** TS-4, TS-5, TS-6, EC-1, EC-10, Pitfalls 9, 10 (document), 11 (verify)
**Avoids:** cross-source regression; cold-start play loss (documented limitation)

### Phase Ordering Rationale

- **Phase 1 before Phase 3:** Pitfall 1 says the root-cause mechanism is unverified; writing the fix without confirming it risks fixing the wrong layer. Pitfall 6 says the fake can't reproduce the bug; the fix is untestable until the fake is extended. Both are cheap precursors that de-risk the expensive phase.
- **Phase 2 before Phase 3:** The `_isReinitializing` clobber (Pitfall 2) and the stacked-subscription bugs (Pitfalls 3, 5) are existing races that the Phase 3 await WIDENS. Fixing them first as no-behavior-change refactors isolates blame if something breaks. ARCHITECTURE.md explicitly orders tracked-subs (step 1) and orphan removal (step 2) before the play restructure (step 4).
- **Phase 3 is the core:** Single method restructure + one helper + error handling. Everything before prepares the ground; everything after verifies.
- **Phase 4 after Phase 3:** Call-site consistency is independent of the play restructure but logically last (belt-and-suspenders once `initSongs` is reliable). Verification requires the fix to be in place.
- **Grouping by architecture pattern:** Phases 1-2 are infrastructure (no behavior change). Phase 3 is behavior change. Phase 4 is consistency + verification. This grouping keeps each phase's blast radius small and each commit revertable in isolation.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** needs a `/gsd-plan-phase --research-phase 1` — the diagnostic logging format, the exact Sound-Books URL(s) to test, and the `FakePlaybackEngine` extension shape (configurable state + delayed `ready` emission) are not yet specified. Pitfall 1's verification protocol needs concrete steps.
- **Phase 3:** may benefit from a light research pass — the exact `_waitForReadyOrTimeout` implementation (completer + listener + timer vs. `firstWhere` + `.timeout`) is sketched two ways across STACK.md and ARCHITECTURE.md; planning should pick one and justify it. Error-state surfacing (`PlayerException` → SnackBar) needs the `_playChapter` pattern at `:87` referenced as the template.

Phases with standard patterns (skip research-phase):
- **Phase 2:** pure refactors of subscription lifecycle and gen-guard additions — patterns are fully specified in ARCHITECTURE.md (Pattern 3) and PITFALLS.md (Pitfalls 2-5). No external research needed.
- **Phase 4:** 2-line call-site change + manual verification checklist — patterns documented in ARCHITECTURE.md step 6 and PITFALLS.md "Looks Done But Isn't" checklist. No research needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | API facts verified against official just_audio source + fork source (line-by-line diff). Fork is upstream-equivalent for play/load/ProcessingState. Only `dart:async` `TimeoutException` is newly referenced (already imported). |
| Features | HIGH (codebase) / MEDIUM (competitor UI) | Table stakes and edge cases grounded in PROJECT.md + direct source reading of `my_audio_handler.dart`, `audiobook_details.dart`, `playback_trust_test.dart`. Competitor UI behavior is LOW (issue trackers, not app testing) but irrelevant to this fix. |
| Architecture | HIGH | All findings from project source code + `.planning/codebase/ARCHITECTURE.md` + `CONCERNS.md`. Build order and data-flow sequence are concrete and step-indexed. |
| Pitfalls | HIGH | Fork source read directly from pub-cache. just_audio README state-model verified. 12 pitfalls grounded in source line numbers. |

**Overall confidence:** HIGH

### Gaps to Address

- **Root-cause mechanism (MEDIUM):** STACK.md and PITFALLS.md both flag that the "play() dropped during buffering" hypothesis is inferred from symptoms + source, not directly observed in a debugger. Phase 1's diagnostic step must confirm: (a) does `setAudioSources` throw for Sound-Books? (b) does `audioSession.setActive(true)` fail? (c) does the fork's `bf26a62` load-interruption change interact with the stop-then-load sequence? If the mechanism is different than hypothesized, the Phase 3 fix shape changes.
- **Sound-Books probe latency distribution (LOW):** the 10s timeout is a reasonable default but unvalidated. Phase 1 should log probe durations across a few Sound-Books URLs to confirm 10s is neither too short (slow networks) nor too long (dead URLs). Pitfall 8.
- **30s stuck-buffering skip threshold (MEDIUM):** Pitfall 11 flags this as possibly too aggressive for Sound-Books on slow networks. Phase 2 adds the gen guard; Phase 4 slow-network verification should confirm whether the threshold needs adjustment. May surface as a Phase 3 adjustment.
- **`AudioHandlerProvider` cold-start race (HIGH understanding, out of scope):** Pitfall 10 — throwaway handler returned between `runApp()` and `initialize()`. Documented in `CONCERNS.md`. Not fixed this milestone. Phase 4 verifies the fix doesn't worsen it (no detached-listener `play()` deferral). If cold-start Sound-Books play loses media notification, it's a known limitation, not a regression.
- **`_listenForCurrentSongIndexChanges` leak (Pitfall 5):** flagged in PITFALLS.md but not in ARCHITECTURE.md's build order. Phase 2 should include it alongside the `_initSettleSub` fix since both are tracked-subscription refactors. Planning must not drop it.

## Sources

### Primary (HIGH confidence)
- Official just_audio source code (`raw.githubusercontent.com/ryanheise/just_audio/minor/just_audio/lib/just_audio.dart`) — `play()`, `setAudioSources()`, `_load()`, `_processingStateSubject`, `processingStateStream`, `stop()`, `pause()` implementations
- Fork source code (`raw.githubusercontent.com/sagarchaulagai/just_audio/a6f8db8.../just_audio/lib/just_audio.dart` + pub-cache read) — line-by-line diff vs upstream; `play()`/`seek()`/`setAudioSources` semantics; `bf26a62` load-interruption change
- Official just_audio README (`pub.dev/packages/just_audio`) — state model, `playing`/`processingState` orthogonality, `play()` Future completion semantics, `PlayerException` on load failure
- Official just_audio API docs (`pub.dev/documentation/just_audio/latest/just_audio/AudioPlayer-class.html`) — `play()`, `setAudioSource`, `ProcessingState` enum
- Official audio_service README (`pub.dev/packages/audio_service`) — `BaseAudioHandler` canonical `play()` delegation contract
- `.planning/PROJECT.md` — bug statement, scope constraints, out-of-scope list
- `.planning/codebase/ARCHITECTURE.md` + `CONCERNS.md` — existing architecture, PlaybackEngine abstraction, cold-start race, fire-and-forget cancel, state-machine fragility
- `lib/resources/services/my_audio_handler.dart` — `initSongs` (`:416-642`), `PlaybackEngine` (`:40`), `JustAudioPlaybackEngine` (`:79`), `play()` override (`:877`), `_restoreQueueFromBoxIfEmpty` (`:841`)
- `lib/screens/audiobook_details/audiobook_details.dart` — `_playChapter` (`:67`), `_autoPlay` (`:94`), big play button (`:513`), `_autoPlayTriggered` (`:65`)
- `test/playback_trust_test.dart` — `FakePlaybackEngine` (`:350`), 3 `initSongs` tests (`:211`, `:244`, `:267`)
- `lib/resources/services/soundbooks/soundbooks_detail_service.dart` — `_parseM3uPlaylist` (`:194`), confirms `length: 0`
- `test/soundbooks_test.dart` — `'length': 0.0` fixture (`:148`)

### Secondary (MEDIUM confidence)
- just_audio GitHub issue #294 — large playlist load times, `useLazyPreparation` (2021, still open; not relevant to single-book race)
- just_audio GitHub issue #263 — historical `PlatformException` on second `setAudioSource` (confirms load-path race history; may not apply to fork)
- Root-cause inference (ExoPlayer/Android native quirk with unknown-duration MP3s) — inferred from gap between verified Dart contract and user-confirmed symptom (Sound-Books only fails; only source with `length: 0`); not directly observed in debugger

### Tertiary (LOW confidence)
- AntennaPod GitHub issues #7259, #7643, #7712 — auto-play toggle exists, resume-on-open is expected but racy even in mature apps (issue trackers, not UI testing)
- BookPlayer, Smart Audiobook Player, Libby — not directly researched (closed-source or repo moved); behavior inferred from user's reference set in PROJECT.md

---
*Research completed: 2026-07-14*
*Ready for roadmap: yes*
