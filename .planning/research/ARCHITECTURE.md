# Architecture Research

**Domain:** Flutter audiobook player — just_audio playback-init race fix (brownfield)
**Researched:** 2026-07-14
**Confidence:** HIGH (all findings sourced from project source code: `my_audio_handler.dart`, `audiobook_details.dart`, `playback_trust_test.dart`, `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/CONCERNS.md`)

## System Overview

The fix targets one method (`MyAudioHandler.initSongs`) inside an existing, shipped Flutter audiobook player. The architecture below shows the playback-init subsystem and the seams the fix operates within — not the whole app (already mapped in `.planning/codebase/ARCHITECTURE.md`).

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     Presentation Layer (UNCHANGED)                       │
│  lib/screens/audiobook_details/audiobook_details.dart                     │
│                                                                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────────┐    │
│  │ _playChapter │  │  _autoPlay   │  │  Big play button (onTap)     │    │
│  │  :67         │  │  :94         │  │  :513  ← INCONSISTENCY       │    │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┬───────────────┘    │
│         │                 │                          │                    │
│         │  initSongs() + play()  ←─ BOTH call sites │ initSongs() ONLY    │
│         │                                            │ (no play() after)   │
└─────────┼────────────────────────────────────────────┼───────────────────┘
          │                                            │
          ▼                                            ▼
┌──────────────────────────────────────────────────────────────────────────┐
│              Service Layer (FIX TARGET — MyAudioHandler)                  │
│  lib/resources/services/my_audio_handler.dart                             │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  MyAudioHandler.initSongs (:416)  ← RESTRUCTURE PLAY SEQUENCE      │  │
│  │                                                                    │  │
│  │  State guards:                                                     │  │
│  │    _isReinitializing (:214)   _initGen (:215)                      │  │
│  │    _canPersistProgress (:243) _activeAudiobookId (:244)            │  │
│  │                                                                    │  │
│  │  NEW field: StreamSubscription? _initSettleSub                     │  │
│  │  NEW field: Timer? _initSettleTimeout                              │  │
│  │                                                                    │  │
│  │  Play sequence (current → fixed):                                  │  │
│  │    CURRENT:  setAudioSources → play() → listen(ready→play)  RACE   │  │
│  │    FIXED:    setAudioSources → waitForReady → play()        SAFE   │  │
│  └────────────────────────────┬───────────────────────────────────────┘  │
│                               │                                           │
│                               ▼                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  PlaybackEngine (abstract, :40)  ← UNCHANGED (no new methods)      │  │
│  │    processingState getter · processingStateStream getter           │  │
│  │    setAudioSources · play · seek · stop                             │  │
│  └────────────────────────────┬───────────────────────────────────────┘  │
│                               │                                           │
│                               ▼                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  JustAudioPlaybackEngine (:79)  ← UNCHANGED                        │  │
│  │    wraps just_audio AudioPlayer                                    │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Data / External (UNCHANGED)                                             │
│  just_audio (forked) · audio_service · Hive boxes                        │
└──────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Fix Impact |
|-----------|----------------|------------|
| `MyAudioHandler.initSongs` | Build AudioSource queue, persist to Hive, set player sources, start playback | **RESTRUCTURE** — play sequence reordered: wait for ready before play() |
| `MyAudioHandler._waitForReadyOrTimeout` (NEW) | Await `ProcessingState.ready` with timeout + gen-aware early exit | **ADD** — internal helper, no interface change |
| `MyAudioHandler._initSettleSub` / `_initSettleTimeout` (NEW fields) | Tracked lifecycle for post-play runtime-recovery listener (buffering-stuck, idle recovery) | **ADD** — replaces fire-and-forget `Future.delayed(60s, sub.cancel())` at `:608` |
| `PlaybackEngine` (abstract, `:40`) | Testable seam over just_audio — exposes `processingState`, `processingStateStream`, `play()`, `setAudioSources()` | **UNCHANGED** — no new methods; existing getters sufficient |
| `JustAudioPlaybackEngine` (`:79`) | Concrete PlaybackEngine wrapping `AudioPlayer` | **UNCHANGED** |
| `AudiobookDetails._autoPlay` (`:94`) | Details-screen auto-play on first load — calls `initSongs` then `play()` | **UNCHANGED** (already correct) |
| `AudiobookDetails._playChapter` (`:67`) | Track-list tap — calls `initSongs` then `play()` | **UNCHANGED** (already correct) |
| `AudiobookDetails` big play button (`:513`) | Hero play button — calls `initSongs` but NOT `play()` | **MINOR FIX** — add `await play()` after `initSongs` for consistency (`:527`, `:538`) |
| `FakePlaybackEngine` (test, `:350`) | Test double for PlaybackEngine — defaults `processingState = ProcessingState.ready` | **UNCHANGED** — ready default means wait-for-ready returns immediately |
| `playback_trust_test.dart` | 520-line invariant suite — 3 tests touch initSongs via FakePlaybackEngine | **PRESERVE** — all 3 must keep passing; add new cases for ready-before-play ordering |

## Recommended Fix Structure

```
lib/resources/services/my_audio_handler.dart
├── abstract class PlaybackEngine          # UNCHANGED — no new methods
├── class JustAudioPlaybackEngine          # UNCHANGED
├── class MyAudioHandler
│   ├── Fields
│   │   ├── _isReinitializing              # UNCHANGED
│   │   ├── _initGen                       # UNCHANGED
│   │   ├── _initSettleSub                 # NEW — StreamSubscription<ProcessingState>?
│   │   └── _initSettleTimeout             # NEW — Timer?
│   ├── initSongs (:416)                   # RESTRUCTURE — play sequence
│   ├── _waitForReadyOrTimeout             # NEW — awaitable helper
│   ├── _waitForProcessingReady (:650)     # UNCHANGED (used for YT seek-after-ready)
│   ├── _waitForStartToSettle (:659)       # UNCHANGED
│   ├── stop (:902)                        # MINOR — cancel _initSettleSub + _initSettleTimeout
│   └── (no dispose method exists; stop() covers teardown)
│
lib/screens/audiobook_details/audiobook_details.dart
├── _playChapter (:67)                     # UNCHANGED
├── _autoPlay (:94)                        # UNCHANGED
└── build() big play button (:513)         # MINOR — add `await play()` after initSongs

test/playback_trust_test.dart
├── Existing 3 initSongs tests             # PRESERVE
└── NEW test cases                         # ADD — ready-before-play, gen-discard, timeout
```

### Structure Rationale

- **Fix stays inside `MyAudioHandler`**: The race is in the shared play-init logic. All three call sites (`_playChapter`, `_autoPlay`, big play button) route through `initSongs`, so fixing it once fixes all sources. Blast radius: one method + two new fields + one new private helper.
- **No `PlaybackEngine` interface change**: "Wait for ready" is orchestration logic (gen-discard, timeout, play ordering), not a just_audio primitive. The existing `processingState` getter + `processingStateStream` getter are sufficient. Adding `Future<void> waitForReady()` to the abstract class would push state-machine concerns into the Strategy seam and force `FakePlaybackEngine` to implement it — net negative for testability.
- **Big play button gets `play()` added**: 2-line change, resolves the inconsistency vs `_playChapter` and `_autoPlay`. With the initSongs fix, initSongs's internal `play()` becomes reliable, so this is belt-and-suspenders — but consistency matters for readability and for the case where a future refactor changes `playImmediately` defaulting.

## Architectural Patterns

### Pattern 1: Generation-Counter Discard at Every Await Point

**What:** `initSongs` increments `_initGen` at entry (`myGen = ++_initGen`) and checks `if (myGen != _initGen) return;` after every `await` that could yield to a newer `initSongs` call. A newer call means the current init is stale — its work (especially `_player.play()`) must be discarded.

**When to use:** Every async method in `MyAudioHandler` that touches shared player state and can be superseded by a re-entrant call.

**Trade-offs:**
- Pro: Prevents stale inits from calling `play()` on a queue that a newer init has already replaced.
- Con: Every await needs a manual checkpoint — easy to miss. No compile-time enforcement.

**Current checkpoints in `initSongs`:**
- `:526` — after building sources, before `addQueueItems`
- `:549` — after `setAudioSources`, before seek
- `:622` — after `_waitForStartToSettle`, before `_listenForCurrentSongIndexChanges`

**Fix adds one new checkpoint:**
- After `_waitForReadyOrTimeout` returns, before `_player.play()` — see Data Flow step `n` below.

```dart
// Pattern: gen-discard after every await
final myGen = ++_initGen;
// ...
await _player.setAudioSources(...);
if (myGen != _initGen) return;  // CHECKPOINT: superseded during setAudioSources
// ...
await _waitForReadyOrTimeout(myGen, const Duration(seconds: 10));
if (myGen != _initGen) return;  // CHECKPOINT: superseded during ready-wait (NEW)
_player.play();
```

### Pattern 2: Awaitable Ready-Gate with Timeout Fallback

**What:** A private helper that returns a `Future<void>` completing when the player reaches `ProcessingState.ready`, or when a timeout elapses (whichever first). The caller then checks gen-discard before proceeding to `play()`.

**When to use:** After `setAudioSources` resolves but before `play()`, when the source's duration may be unknown (forcing a network probe that leaves the player in `loading`).

**Trade-offs:**
- Pro: Deterministic ready-before-play ordering for all sources; no reliance on a post-play listener catching a missed `ready` transition.
- Pro: Timeout fallback ensures playback still attempts even if the probe hangs (current behavior degrades to "press play twice").
- Con: Adds up to `timeout` ms of latency to the play-init path for sources with unknown durations. For Sound-Books this is the network probe time (typically <2s); for sources with known durations, the awaitable returns synchronously (player already `ready`).

```dart
Future<void> _waitForReadyOrTimeout(int myGen, Duration timeout) async {
  if (_player.processingState == ProcessingState.ready) return;

  final completer = Completer<void>();
  late StreamSubscription<ProcessingState> sub;
  late Timer timer;

  sub = _player.processingStateStream.listen((state) {
    if (state == ProcessingState.ready && !completer.isCompleted) {
      completer.complete();
    }
  });
  timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete(); // give up; caller will play() anyway
  });

  try {
    await completer.future;
  } finally {
    timer.cancel();
    await sub.cancel();
  }
}
```

**Why the awaitable does NOT check gen internally:** The caller checks `myGen != _initGen` after the await returns. If a newer initSongs started during the wait, the newer call will have called `_player.stop()` + `setAudioSources` again, which fires a new `ready` event. The old listener completes the old completer, the old await returns, the old caller checks gen, sees it's stale, and returns without calling `play()`. The subscription is cancelled in `finally`. Clean — no play() on a superseded queue.

### Pattern 3: Tracked Subscription Lifecycle (replaces fire-and-forget cancel)

**What:** Store the post-play runtime-recovery `StreamSubscription` in a field (`_initSettleSub`) and its cleanup `Timer` in another (`_initSettleTimeout`). Cancel both at the top of the next `initSongs` and in `stop()`.

**When to use:** Any stream subscription attached during `initSongs` that outlives the method's await scope.

**Trade-offs:**
- Pro: No stacking of `Future.delayed` futures on re-entry (current bug at `:608`).
- Pro: Explicit teardown in `stop()` and next-init top — no reliance on GC.
- Con: Two new fields on a class that already has 6+ mutable state fields. Acceptable — the alternative (fire-and-forget) is worse.

```dart
// Top of initSongs, before any async work:
_initSettleSub?.cancel();
_initSettleTimeout?.cancel();
_initSettleSub = null;
_initSettleTimeout = null;

// After play(), attach tracked recovery listener:
if (playImmediately) {
  await _waitForReadyOrTimeout(myGen, const Duration(seconds: 10));
  if (myGen != _initGen) return;
  _player.play();

  _initSettleSub = _player.processingStateStream.listen((state) {
    // Runtime recovery only: buffering-stuck-30s-skip, idle-recovery
    // NO "re-fire play() on ready" — that's _waitForReadyOrTimeout's job now
    // ...
  });
  _initSettleTimeout = Timer(const Duration(seconds: 60), () {
    _initSettleSub?.cancel();
    _initSettleSub = null;
    _initSettleTimeout = null;
  });
}
```

**In `stop()` (`:902`), add:**
```dart
_initSettleSub?.cancel();
_initSettleTimeout?.cancel();
```

## Data Flow

### Corrected `initSongs` Sequence (Play-Immediately Path)

This is the exact call sequence the fixed `initSongs` should perform, with gen-discard checkpoints marked. Steps marked **NEW** or **CHANGED** differ from the current implementation; all others are unchanged.

```
ENTRY: initSongs(files, audiobook, initialIndex, positionMs, {playImmediately: true})

 1. _isReinitializing = true
 2. myGen = ++_initGen
 3. NEW: _initSettleSub?.cancel(); _initSettleTimeout?.cancel()
    (teardown any previous settle listener + timeout — prevents stacking)

 4. try {
 5.   await _ensureAudioSession()
 6.   _canPersistProgress = false
 7.   _activeAudiobookId = audiobook.id
 8.   await box.put('audiobook', audiobook.toMap())
 9.   await box.put('audiobookFiles', files.map(toMap))
10.   await box.put('index', initialIndex)
11.   await box.put('position', positionMs)
12.   await _player.stop()
13.   queue.add([]); mediaItem.add(null)
14.   _positionUpdateTimer?.cancel()
15.   playbackState.add(idle, playing: false, controls: [])

16.   -- build mediaItems + sources (sync loop over files) --
       YouTube → YouTubeAudioSource
       clipped → ClippingAudioSource
       other  → AudioSource.uri (with sanitizePlayerUrl)

17.   CHECKPOINT 1: if (myGen != _initGen) return   ← existing (:526)

18.   safeIndex = initialIndex.clamp(0, sources.length - 1)
19.   addQueueItems(mediaItems)
20.   mediaItem.add(mediaItems[safeIndex])
21.   _audioSources = sources
22.   currentIsYT = _isIndexYouTube(safeIndex)

23.   await _player.setAudioSources(sources,
         initialIndex: safeIndex,
         initialPosition: currentIsYT ? Duration.zero : positionMs,
         preload: playImmediately)

24.   CHECKPOINT 2: if (myGen != _initGen) return   ← existing (:549)

25.   if (currentIsYT && positionMs > 0):
        if (playImmediately): await _waitForProcessingReady(5s)   ← existing
        await _player.seek(positionMs, index: safeIndex)
      else:
        await _player.seek(positionMs, index: safeIndex)

26.   CHECKPOINT 3: if (myGen != _initGen) return   ← existing (:622, moved)

27.   if (playImmediately):
28.     NEW: await _waitForReadyOrTimeout(myGen, Duration(seconds: 10))
            ↳ if processingState == ready: return immediately (sources with known duration)
            ↳ else: listen for ready, complete on ready OR timeout
            ↳ finally: cancel listener + timer

29.     CHECKPOINT 4: if (myGen != _initGen) return   ← NEW (after ready-wait)

30.     _player.play()   ← CHANGED: moved AFTER ready-wait (was :565, before any wait)

31.     NEW: _initSettleSub = _player.processingStateStream.listen(...)
            ↳ Runtime recovery ONLY:
              - buffering > 30s → skip to next track (existing logic, :590)
              - idle while playing → recovery retry (existing logic, :579)
            ↳ NO "re-fire play() on ready" branch (handled by step 28)
            ↳ NO orphan logging listener (removed — was :611)

32.     NEW: _initSettleTimeout = Timer(60s, () { _initSettleSub?.cancel(); ... })

33.   await _waitForStartToSettle(safeIndex, positionMs, isYouTube: currentIsYT, timeout: 3s)
        ← existing (:615), still runs for both playImmediately paths

34.   CHECKPOINT 5: if (myGen != _initGen) return   ← existing

35.   _listenForCurrentSongIndexChanges()
36.   historyOfAudiobook.addToHistory(audiobook, files, safeIndex, positionMs)
37.   _startPositionUpdateTimer(audiobook.id)
38.   _canPersistProgress = true
39.   _lastPersistAt = now - _persistInterval
40.   _broadcastState(_player.playbackEvent)

41. } finally {
42.   _isReinitializing = false
43. }
```

### Source-Specific Behavior

| Source | Duration known? | `setAudioSources` resolves to | Step 28 behavior | Step 30 `play()` |
|--------|-----------------|-------------------------------|------------------|-------------------|
| LibriVox/Archive.org | Yes (API response) | `ready` synchronously | Returns immediately | Fires immediately — no change from current |
| YouTube | N/A (streaming) | `ready` (YouTubeAudioSource) | Returns immediately | Fires immediately — no change |
| knigavuhe | Yes (scraped) | `ready` synchronously | Returns immediately | Fires immediately — no change |
| 4read | Probed in BLoC | `ready` (probe done before initSongs) | Returns immediately | Fires immediately — no change |
| Sound-Books | **No** (m3u `length: 0`) | `loading` → network probe → `ready` | **Waits for ready** (or 10s timeout) | **Fires after ready** — RACE FIXED |
| Local/downloaded | Yes (metadata) | `ready` synchronously | Returns immediately | Fires immediately — no change |

### Gen-Discard Interaction at Every Await Point

| Step | Await | What can supersede during await | Stale-init behavior |
|------|-------|---------------------------------|---------------------|
| 5 | `_ensureAudioSession` | Another `initSongs` call | CHECKPOINT 1 catches it |
| 8-11 | Hive `box.put` × 4 | Another `initSongs` call | CHECKPOINT 1 catches it |
| 12 | `_player.stop()` | Another `initSongs` call | CHECKPOINT 1 catches it |
| 23 | `_player.setAudioSources` | Another `initSongs` call | CHECKPOINT 2 catches it |
| 25 | `_waitForProcessingReady` (YT) / `_player.seek` | Another `initSongs` call | CHECKPOINT 3 catches it |
| **28** | **`_waitForReadyOrTimeout` (NEW)** | Another `initSongs` call (triggers stop + new setAudioSources → new ready event → old completer completes) | **CHECKPOINT 4 catches it — old init returns without play()** |
| 33 | `_waitForStartToSettle` | Another `initSongs` call | CHECKPOINT 5 catches it |

**Critical composition detail:** If a newer `initSongs` starts during step 28's wait, the newer call's `_player.stop()` + `setAudioSources` will emit a new `ProcessingState.ready` event on the broadcast `processingStateStream`. The old step-28 listener catches it, completes the old completer, the old await returns. The old initSongs then hits CHECKPOINT 4 (`myGen != _initGen`), returns. The old listener is cancelled in `_waitForReadyOrTimeout`'s `finally`. No stale `play()` fires. The newer initSongs proceeds independently with its own gen.

## Anti-Patterns

### Anti-Pattern 1: Play Before Ready (CURRENT BUG)

**What people do:** Call `_player.play()` immediately after `setAudioSources` resolves, then attach a `processingStateStream.listen` to re-fire `play()` when `ready` is reached. (`:565`, `:569`)
**Why it's wrong:** If `setAudioSources` resolves while the player is still `loading` (Sound-Books: duration unknown → network probe in flight), the first `play()` is dropped by just_audio (player not ready). The listener is attached AFTER the initial `play()` call, so if the `loading → ready` transition fires between `setAudioSources` resolving and the listener being attached, the listener misses it. Result: auto-play silently no-ops.
**Do this instead:** Await `ProcessingState.ready` (with timeout) BEFORE calling `play()`. The awaitable subscribes to the stream BEFORE awaiting, so it cannot miss the transition. If the player is already `ready` (sources with known durations), the awaitable returns synchronously — zero added latency for non-Sound-Books sources.

### Anti-Pattern 2: Fire-and-Forget Subscription Cancellation (CURRENT BUG)

**What people do:** `Future.delayed(const Duration(seconds: 60), () => sub.cancel());` (`:608`) — a detached future that cancels a stream subscription 60 seconds later.
**Why it's wrong:** If `initSongs` re-enters before 60s (rapid track-skip, re-pressing play on a new book), the previous `Future.delayed` is still pending. Multiple delayed-futures stack. The previous `sub` is already orphaned (a new `initSongs` has replaced the queue), but the old `Future.delayed` will still fire and call `sub.cancel()` on a subscription whose parent `initSongs` has long returned. The subscription object lingers until the delayed future fires. If the app dies before 60s, the sub leaks entirely. (Flagged in `CONCERNS.md:89-95`.)
**Do this instead:** Track the subscription in a field (`_initSettleSub`) and its cleanup timer in another (`_initSettleTimeout`). Cancel both at the top of the next `initSongs` and in `stop()`. Drop the `Future.delayed` entirely — use a `Timer` that's tracked and cancelled explicitly.

### Anti-Pattern 3: Orphan Logging Listener (CURRENT BUG)

**What people do:** `_player.processingStateStream.listen((state) { AppLogger.debug(...); });` (`:611`) — a bare `listen` with no subscription stored, never cancelled.
**Why it's wrong:** Every `initSongs` call adds a permanent listener to the broadcast `processingStateStream`. These listeners are never removed. After 50 `initSongs` calls (50 track-skips), 50 logging listeners are attached, each firing on every processing-state change. Memory leak + log spam. This is debug code that was never cleaned up.
**Do this instead:** Remove it. If debug logging of processing-state changes is needed, add it to `_broadcastState` (which is already called on every `playbackEventStream` event via `_bindStatePipelines` at `:325`) or gate it behind `kDebugMode`. Never attach an untracked listener in a method that can be called repeatedly.

### Anti-Pattern 4: Inconsistent Call-Site Play Invocation (CURRENT INCONSISTENCY)

**What people do:** `_playChapter` (`:82`) and `_autoPlay` (`:131`) call `await audioHandler.play()` after `initSongs`. The big play button (`:513`) calls `initSongs` but does NOT call `play()` afterward.
**Why it's wrong:** The big play button relies entirely on `initSongs`'s internal `_player.play()` (`:565`). With the current race, that internal play() can be dropped for Sound-Books — so the big play button is MORE affected by the race than the other two call sites (which have the redundant explicit `play()` as backup). Even with the fix, the inconsistency is a readability hazard and a latent bug if `playImmediately`'s default ever changes.
**Do this instead:** Add `await audioHandlerProvider.audioHandler.play();` after both `initSongs` calls in the big play button `onTap` (after `:532` and after `:543`). 2-line change. Matches `_playChapter` and `_autoPlay` pattern exactly.

## Integration Points

### Internal Boundaries

| Boundary | Communication | Fix Impact |
|----------|---------------|------------|
| `AudiobookDetails` ↔ `MyAudioHandler` | Direct method call via `AudioHandlerProvider.audioHandler.initSongs(...)` + `.play()` | Big play button adds `.play()` call — 2 lines. No interface change. |
| `MyAudioHandler` ↔ `PlaybackEngine` | Method calls (`setAudioSources`, `play`, `seek`, `stop`) + stream reads (`processingStateStream`, `processingState` getter) | **No new methods on PlaybackEngine.** Fix uses only existing getters. `FakePlaybackEngine` unchanged. |
| `MyAudioHandler.initSongs` ↔ `_initGen` guard | Generation counter + checkpoint checks after every await | One new checkpoint added (after ready-wait, before play). Pattern unchanged. |
| `MyAudioHandler.initSongs` ↔ `_isReinitializing` flag | Set true at entry, false in `finally` | Unchanged. Still gates `_persistInstant`, `_restoreQueueFromBoxIfEmpty`, `_listenForCurrentSongIndexChanges`. |
| `MyAudioHandler.initSongs` ↔ `_canPersistProgress` flag | Set false early, true after settle | Unchanged. Still gates position persistence. |
| `MyAudioHandler` ↔ Hive `playing_audiobook_details_box` | `box.put(...)` for audiobook, files, index, position | Unchanged. Writes still happen before `_player.stop()` (write-barrier pattern preserved). |

### What the Fix Does NOT Touch

| Component | Why Untouched |
|-----------|---------------|
| `PlaybackEngine` abstract class (`:40`) | Existing `processingState` + `processingStateStream` sufficient. Adding `waitForReady()` would push state-machine concerns into the Strategy seam. |
| `JustAudioPlaybackEngine` (`:79`) | Thin wrapper, no logic to change. |
| `FakePlaybackEngine` (test `:350`) | Defaults `processingState = ProcessingState.ready` — the awaitable returns immediately. No new methods to implement. |
| `_broadcastState` (`:718`) | Maps just_audio state → audio_service state. Unchanged. |
| `_bindStatePipelines` (`:318`) | Permanent listeners for `playbackEventStream`, `playerStateStream`, `playingStream`, `bufferedPositionStream`. Unchanged. The fix's `_initSettleSub` is a separate, init-scoped listener for runtime recovery only. |
| `restoreIfNeeded` / `_restoreQueueFromBoxIfEmpty` (`:278`, `:841`) | Calls `initSongs(playImmediately: false)`. The fix's ready-wait is gated on `playImmediately` — when false, step 28 is skipped entirely. No change to restore behavior. |
| `play()` override (`:877`) | Calls `_restoreQueueFromBoxIfEmpty` then `_player.play()`. Unchanged. The explicit `play()` from call sites is belt-and-suspenders; with the fix, initSongs's internal play() is reliable, but the explicit call remains harmless. |
| `_waitForProcessingReady` (`:650`) | Used only for YouTube seek-after-ready (`:553`). Unchanged. Distinct from the new `_waitForReadyOrTimeout` (which gates play, not seek). |
| `_waitForStartToSettle` (`:659`) | Polls `currentIndex` + `position` to confirm seek landed. Unchanged. Still runs after play() in the fixed sequence. |
| Position persistence flow (`:705`, `:778`) | Gated by `_canPersistProgress` + `_isReinitializing`. Unchanged. |
| Sleep timer, equalizer, bookmarks | Unrelated to play-init sequence. |

## Test Strategy

### Existing Tests — Must Keep Passing

| Test | File:Line | What it asserts | Why the fix preserves it |
|------|-----------|-----------------|--------------------------|
| `restores queue from Hive without starting real playback` | `playback_trust_test.dart:211` | `restoreIfNeeded()` → `fake.setAudioSourcesCalls` has 1 call, `fake.playCount == 0`, queue has 3 items, mediaItem is 'Middle' (index 1) | Restore calls `initSongs(playImmediately: false)`. The fix's ready-wait (step 28) is gated on `playImmediately` — skipped when false. `playCount` stays 0. `FakePlaybackEngine.processingState` defaults to `ready`, so even if the wait ran, it would return immediately. |
| `skipToQueueItem seeks to chapter start and resumes playback` | `:244` | `initSongs(playImmediately: false)` then `skipToQueueItem(2)` → `seekCalls.last.index == 2`, `playCount == 1` | The `playCount == 1` comes from `skipToQueueItem` → `play()` override → `_player.play()`, NOT from `initSongs`. Since `playImmediately: false`, initSongs's internal play path (steps 27-32) is skipped. Unchanged. |
| `seek writes latest position to now-playing box and history` | `:267` | `initSongs(playImmediately: false)` then `seek(42s)` → box has index 1, position 42000, history matches | `playImmediately: false` skips the play path. Seek + persistence unaffected. |
| `playback restore payload` round-trip | `:48` | Hive box round-trips audiobook, files, index, position | Pure Hive test, no PlaybackEngine. Unchanged. |
| `position history` updates | `:77` | `HistoryOfAudiobook` position update + recency | No PlaybackEngine. Unchanged. |
| `bookmarks` sort + proximity | `:97`, `:121` | BookmarkService ordering + tolerance | No PlaybackEngine. Unchanged. |
| `sleep timer` countdown + cancel | `:132`, `:155` | OptimizedTimer expiry + cancel | No PlaybackEngine. Unchanged. |
| `chapter switching metadata` | `:177`, `:188` | `effectiveTrackLength` + `formatTrackDuration` | Pure function test. Unchanged. |

### New Test Cases — Must Add

| Test name | What it asserts | FakePlaybackEngine setup |
|-----------|-----------------|--------------------------|
| `initSongs with playImmediately=true calls play() after ready` | `playCount == 1`, and play() is called AFTER `setAudioSources` resolves. Verify ordering: `setAudioSourcesCalls.last` is set before `playCount` increments. | Default (`processingState = ready`). Should return immediately from ready-wait. |
| `initSongs waits for ready when processingState starts loading` | Start with `processingState = loading`. Emit `ready` on `processingStates` stream after 50ms. Assert `playCount == 1` and that `play()` was called only AFTER the `ready` emission (not before). | Override `processingState` to `loading` initially; add `processingStates.add(ProcessingState.ready)` after a delay. |
| `initSongs gen-discard: newer initSongs supersedes before ready` | Start first `initSongs` with a fake that hangs in `loading` (never emits ready). Start a second `initSongs` partway through. Assert: first init's `play()` is NOT called (gen-discard), second init's `play()` IS called. | First fake: `processingState = loading`, no ready emission. Second fake (or reset): `processingState = ready`. Or use a single fake with controllable state. |
| `initSongs timeout: calls play() after timeout when ready never fires` | Fake that stays in `loading` forever. Assert `playCount == 1` after the timeout duration elapses (use a short timeout like 200ms in the test). | `processingState = loading`, never emit `ready`. |
| `initSongs tracked subscription is cancelled on re-entry` | Call `initSongs` twice rapidly. After both complete, assert `FakePlaybackEngine.processingStates` stream has no listeners (check `processingStates.hasListener` is false, or that the subscription was cancelled). | Default ready state. Verify the `_initSettleSub` is cancelled by the second init's top-of-method teardown. |
| `initSongs with playImmediately=false does NOT call play()` | Explicit test for the `playImmediately: false` path (currently implicit in the restore test). Assert `playCount == 0` even when `processingState = ready`. | Default ready state. |
| `initSongs does not attach orphan logging listeners` | Call `initSongs` N times. Assert `processingStates` stream listener count does not grow unboundedly (should be 0 or 1 after each call completes, not N). | Default ready state. Verify removal of the `:611` orphan listener. |

### FakePlaybackEngine Enhancements Needed

The existing `FakePlaybackEngine` (`playback_trust_test.dart:350`) defaults `processingState = ProcessingState.ready` and has a `processingStates` broadcast `StreamController`. To support the new tests:

1. **Make `processingState` settable after construction** — it already is a public mutable field (`:384`). Tests can set `fake.processingState = ProcessingState.loading` before calling `initSongs`.
2. **No new methods needed** — the `processingStateStream` getter already returns `processingStates.stream`. Tests can `fake.processingStates.add(ProcessingState.ready)` to simulate the ready transition.
3. **Optional: add `processingStates.hasListener` check** — already available on `StreamController`. Tests can assert no leaked listeners.

No changes to `FakePlaybackEngine`'s class definition are required for the new tests. The existing stream controllers + mutable `processingState` field are sufficient.

## Build Order

The fix has internal dependencies that dictate implementation order:

### Step 1: Add tracked-subscription fields + teardown (no behavior change)

**What:** Add `StreamSubscription<ProcessingState>? _initSettleSub` and `Timer? _initSettleTimeout` fields. Add `_initSettleSub?.cancel(); _initSettleTimeout?.cancel();` at the top of `initSongs` (before any async work) and in `stop()`. Replace the `Future.delayed(60s, sub.cancel())` at `:608` with the tracked `Timer`.

**Why first:** This is a pure refactor of the subscription lifecycle — no change to play ordering. It can be verified independently (existing tests still pass, no new behavior). If something breaks, it's isolated to subscription management, not play logic.

**Verify:** Run existing `playback_trust_test.dart` — all 3 initSongs tests pass. Manually verify no `Future.delayed` stacking by calling `initSongs` twice rapidly (unit test: `initSongs tracked subscription is cancelled on re-entry`).

### Step 2: Remove orphan logging listener (no behavior change)

**What:** Delete the `_player.processingStateStream.listen((state) { AppLogger.debug(...); });` at `:611`.

**Why second:** Trivial removal of debug code. Independent of play-logic changes. Prevents the new tests from failing on "listener count grows" assertions.

**Verify:** Run existing tests — all pass. Run new test: `initSongs does not attach orphan logging listeners`.

### Step 3: Add `_waitForReadyOrTimeout` helper (no behavior change yet)

**What:** Add the private `Future<void> _waitForReadyOrTimeout(int myGen, Duration timeout)` method. Do NOT call it from `initSongs` yet.

**Why third:** The helper exists in isolation. Can be unit-tested independently if desired. No risk to existing play flow.

**Verify:** Compile. Optionally add a direct unit test for the helper using `FakePlaybackEngine` (ready immediately, ready after delay, timeout).

### Step 4: Restructure play sequence — ready-before-play (THE FIX)

**What:** In `initSongs`, after the `seek` block (step 25 in the data flow) and the CHECKPOINT 3, insert:
```dart
if (playImmediately) {
  await _waitForReadyOrTimeout(myGen, const Duration(seconds: 10));
  if (myGen != _initGen) return;  // CHECKPOINT 4 (NEW)
  _player.play();
  // ... attach _initSettleSub (runtime recovery only, no ready→play branch) ...
}
```
Move the existing `_player.play()` from `:565` to after the ready-wait. Remove the "re-fire play() on ready" branch from the listener (the `if (state == ProcessingState.ready) { _player.play(); }` block at `:572-575`). Keep the buffering-stuck-30s-skip and idle-recovery branches.

**Why fourth:** This is the core behavior change. Steps 1-3 have prepared the ground (tracked subs, no orphan listener, helper exists). This step depends on all three.

**Verify:** Run all existing tests — must pass. Run new tests:
- `initSongs with playImmediately=true calls play() after ready`
- `initSongs waits for ready when processingState starts loading`
- `initSongs timeout: calls play() after timeout when ready never fires`
- `initSongs with playImmediately=false does NOT call play()`

### Step 5: Add gen-discard test (validates the race fix's race-safety)

**What:** Add `initSongs gen-discard: newer initSongs supersedes before ready` test.

**Why last:** Requires the full restructured play sequence to be in place. Tests the interaction between `_waitForReadyOrTimeout` and the gen guard — the most subtle part of the fix.

**Verify:** Test passes. Manually test on device: open a Sound-Books book → auto-play starts without pressing play. Open a LibriVox book → auto-play still works (no latency added). Rapidly tap different books → no stale play() calls, no listener leaks.

### Step 6: Fix big play button call-site consistency (minor)

**What:** In `audiobook_details.dart` big play button `onTap` (`:513`), add `await audioHandlerProvider.audioHandler.play();` after both `initSongs` calls (`:532` and `:543`).

**Why last:** Cosmetic consistency. With step 4's fix, `initSongs`'s internal `play()` is reliable, so this is belt-and-suspenders. But it matches `_playChapter` and `_autoPlay` patterns and removes the inconsistency.

**Verify:** Manual test: tap big play button on a Sound-Books book → playback starts. Tap on LibriVox → playback starts. No double-play issues (the `play()` override's `_restoreQueueFromBoxIfEmpty` is a no-op when queue is populated).

### Dependency Graph

```
Step 1 (tracked subs) ──┐
Step 2 (remove orphan) ─┤
Step 3 (helper) ─────────┼──→ Step 4 (restructure play) ──→ Step 5 (gen-discard test)
                         │                                      │
                         │                                      ▼
                         │                              Step 6 (call-site fix) ← independent
                         │
                         ▼
                    Existing tests pass at every step
```

Steps 1, 2, 3 are independent of each other and can be done in parallel or any order. Step 4 depends on all three. Step 5 depends on 4. Step 6 is independent of 4-5 but logically last.

## Sources

- `.planning/PROJECT.md` — bug description, scope constraints, key decisions (2026-07-14)
- `.planning/codebase/ARCHITECTURE.md` — existing architecture, PlaybackEngine abstraction, component map (2026-07-13)
- `.planning/codebase/CONCERNS.md` — known tech debt: AudioHandlerProvider cold-start race (`:81`), 60s Future.delayed fire-and-forget (`:89`), MyAudioHandler 1054-line state machine (`:217`) (2026-07-13)
- `lib/resources/services/my_audio_handler.dart` — full `initSongs` flow (`:416-642`), `PlaybackEngine` abstract (`:40-77`), `JustAudioPlaybackEngine` (`:79-189`), `_broadcastState` (`:718`), `play()` override (`:877`), `_restoreQueueFromBoxIfEmpty` (`:841`)
- `lib/screens/audiobook_details/audiobook_details.dart` — `_playChapter` (`:67`), `_autoPlay` (`:94`), big play button `onTap` (`:513`)
- `test/playback_trust_test.dart` — `FakePlaybackEngine` (`:350-499`), 3 `initSongs` tests (`:211`, `:244`, `:267`), `SetAudioSourcesCall` / `SeekCall` recording helpers

---
*Architecture research for: Flow Book just_audio playback-init race fix*
*Researched: 2026-07-14*
