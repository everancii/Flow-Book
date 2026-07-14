# Phase 1: Diagnostic Verification + Test Infrastructure - Research

**Researched:** 2026-07-14
**Domain:** Flutter audiobook player — just_audio play-init race diagnosis + FakePlaybackEngine test-infrastructure extension (brownfield)
**Confidence:** HIGH (all findings from direct source code reading: `my_audio_handler.dart`, `playback_trust_test.dart`, fork source in pub-cache, project research docs)

## Summary

Phase 1 is a diagnostic + test-infrastructure phase. It does NOT fix the Sound-Books auto-play bug — it prepares the ground for Phase 3 by (a) extending `FakePlaybackEngine` to simulate the `loading → ready` transition so the race is reproducible in tests, (b) adding temporary diagnostic logs to `initSongs` so the actual failure mechanism can be confirmed on a real device, and (c) collecting probe-duration data across 3+ Sound-Books URLs to validate the 10s timeout default.

The `FakePlaybackEngine` (test/playback_trust_test.dart:350-499) currently defaults `processingState = ProcessingState.ready` and uses a plain broadcast `StreamController<ProcessingState>` that never emits unless test code manually calls `processingStates.add(...)`. No structural class changes are needed — the existing mutable `processingState` field + broadcast `processingStates` stream are sufficient for simulating `loading → ready` IF the Phase 3 fix checks the field synchronously before listening on the stream (ARCHITECTURE.md Pattern 2 approach). Tests configure the fake by setting `fake.processingState = ProcessingState.loading` before `initSongs`, then emitting `fake.processingStates.add(ProcessingState.ready)` after a delay. The "test that fails today and passes after the fix" asserts `fake.playCount == 0` before `ready` is emitted — this fails with the current code (play() fires at line 565 unconditionally) and passes after the fix (play() deferred until ready).

The fork source (`just_audio@a6f8db8`, read from pub-cache) reveals the exact `play()` mechanism: `play()` broadcasts `playing = true` synchronously (line 1097), then `await audioSession.setActive(true)` (line 1106). If `setActive` fails, `playing` reverts to `false` (line 1127) — no play request is sent. If `playing` was flipped to `false` by an intervening event during the `setActive` await, line 1107 returns without sending the play request. This is a more specific "play() dropped" mechanism than "dropped during buffering" — it's "dropped during the audioSession.setActive await window." The diagnostic logs must check `playing` after `play()` returns and after a short delay to detect this reversion.

**Primary recommendation:** Extend `FakePlaybackEngine` via test-code configuration (no class changes), add `[DIAG]`-tagged `AppLogger.debug` calls at 5 checkpoints in `initSongs`, and write the "fails today, passes after fix" test in `playback_trust_test.dart` alongside the existing test group.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-01 | `FakePlaybackEngine` is extended to simulate a `loading → ready` `ProcessingState` transition (precursor — the fix is untestable without it, since the fake currently always reports `ready`) | FakePlaybackEngine analysis (Q1), stream semantics analysis (Q2), test shape (Q3) — fake's existing mutable field + broadcast stream are sufficient; no class changes needed. Test configures `processingState = loading` + emits `ready` on stream. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| FakePlaybackEngine loading→ready simulation | Test layer | — | Test double owns state simulation; no production code change |
| Diagnostic logging in initSongs | Service layer (`MyAudioHandler`) | — | Logs added inside `initSongs` method — the site of the race |
| Probe-duration data collection | Service layer (`MyAudioHandler` logs) + manual device testing | — | Logs capture timing; developer reads logs on device |
| "Fails today, passes after fix" test | Test layer (`playback_trust_test.dart`) | — | New test case in existing test file, using existing fake |

## Standard Stack

No new packages. This phase uses only existing APIs and tools.

### Core (existing, no changes)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_test` | SDK | Test framework for `playback_trust_test.dart` | Already used — 9 test files, 520-line trust suite [VERIFIED: pubspec.yaml line 76] |
| `just_audio` | 0.10.5 (fork `sagarchaulagai/just_audio.git` @ `a6f8db8`) | `ProcessingState` enum, `processingStateStream` semantics | Fork source read from pub-cache — `BehaviorSubject<ProcessingState>.seeded(idle).stream.distinct()` [VERIFIED: fork source line 135-136, 487-488] |
| `rxdart` | ^0.28.0 | `BehaviorSubject` (available if fake upgrade needed) | Direct dependency in pubspec.yaml line 41 [VERIFIED: pubspec.yaml] |
| `AppLogger` | project util | Diagnostic logging — `AppLogger.debug(message, tag)` | Already used throughout `initSongs` (lines 563, 570, 573, 581, 593) [VERIFIED: my_audio_handler.dart] |

### Installation

No installation changes. No new packages, no version bumps.

```bash
# No-op — all dependencies already in pubspec.yaml
flutter pub get  # already resolved
```

## Package Legitimacy Audit

> This phase installs NO external packages. No audit needed.

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
ENTRY: Phase 1 work items

┌─────────────────────────────────────────────────────────────────────┐
│  Item A: Extend FakePlaybackEngine (test-only, no class changes)    │
│  test/playback_trust_test.dart                                       │
│                                                                      │
│  Existing: processingState = ready (field default)                  │
│            processingStates = broadcast StreamController (empty)     │
│                                                                      │
│  Phase 1 adds: NEW TEST CASES that configure the fake:              │
│    1. Set fake.processingState = ProcessingState.loading             │
│    2. Call initSongs(playImmediately: true) — don't await            │
│    3. Pump event loop (Future.delayed 10ms)                          │
│    4. Assert fake.playCount == 0  ← FAILS today, PASSES after fix   │
│    5. Emit: fake.processingState = ready                             │
│             fake.processingStates.add(ProcessingState.ready)         │
│    6. Await initSongs completion                                     │
│    7. Assert fake.playCount == 1  ← PASSES both                      │
└──────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  Item B: Diagnostic logs in initSongs (temporary, [DIAG]-tagged)    │
│  lib/resources/services/my_audio_handler.dart                       │
│                                                                      │
│  CHECKPOINT 1: before setAudioSources                                │
│    → AppLogger.debug('[DIAG] initSongs[gen=N]: before setAudio...')  │
│  CHECKPOINT 2: after setAudioSources (try/catch wrapper)            │
│    → AppLogger.debug('[DIAG] initSongs[gen=N]: setAudioSources       │
│       resolved, state=X, threw=false')                               │
│    OR → AppLogger.debug('[DIAG] initSongs[gen=N]: setAudioSources    │
│       THREW: $e')                                                    │
│  CHECKPOINT 3: before play() (existing log at :563)                 │
│    → already logged: 'initSongs: calling _player.play(), state=X'   │
│  CHECKPOINT 4: after play() (immediate)                              │
│    → AppLogger.debug('[DIAG] initSongs[gen=N]: after play(),         │
│       state=X, playing=Y')                                           │
│  CHECKPOINT 5: delayed (500ms) — detect playing reversion           │
│    → AppLogger.debug('[DIAG] initSongs[gen=N]: 500ms after play(),   │
│       state=X, playing=Y (if false → audioSession.setActive failed)')│
└──────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  Item C: Probe-duration logs (device testing)                       │
│  Developer opens 3+ Sound-Books books on device                     │
│  Reads [DIAG] logs → notes setAudioSources duration                  │
│  Confirms 10s timeout is appropriate                                 │
└──────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
test/
├── playback_trust_test.dart    # EXTEND — add loading→ready test cases
│                                #   (FakePlaybackEngine stays in this file)
├── soundbooks_test.dart        # UNCHANGED
└── (other test files)          # UNCHANGED

lib/resources/services/
└── my_audio_handler.dart       # ADD diagnostic logs (temporary, [DIAG]-tagged)
```

### Pattern 1: FakePlaybackEngine Configuration for loading→ready

**What:** Configure the existing `FakePlaybackEngine` to simulate a `loading → ready` transition by (a) setting the `processingState` field to `loading` before calling `initSongs`, and (b) emitting `ready` on the `processingStates` stream after a delay.

**When to use:** Any test that needs to exercise the play-init race condition (play() called while state is loading/buffering, ready arrives later).

**Why no class changes are needed:**
- `processingState` is already a public mutable field (line 384) — tests can set it directly
- `processingStates` is already a broadcast `StreamController<ProcessingState>` (line 357) — tests can emit events via `processingStates.add(...)`
- `processingStateStream` getter (line 411) returns `processingStates.stream` — the fix's `_waitForReadyOrTimeout` helper listens on this

**Critical caveat — BehaviorSubject vs broadcast StreamController:**

| Property | Real just_audio | FakePlaybackEngine |
|----------|----------------|-------------------|
| Stream type | `BehaviorSubject.seeded(idle).stream.distinct()` | `StreamController.broadcast().stream` |
| Replays current state to new subscribers? | YES (BehaviorSubject) | NO (broadcast) |
| Impact on `firstWhere(ready)` | Completes immediately if already `ready` (replay) | HANGS FOREVER (no replay, no emission) |
| Impact on Pattern 2 (field-check-first) | Field check short-circuits; stream only for transition | Field check short-circuits; stream only for transition — WORKS |

**Implication:** If Phase 3 uses `processingStateStream.firstWhere(ready).timeout(10s)` directly (STACK.md recommendation), the fake MUST be upgraded to `BehaviorSubject` (rxdart available — `rxdart: ^0.28.0` in pubspec.yaml line 41). If Phase 3 uses ARCHITECTURE.md Pattern 2 (`if (processingState == ready) return;` then `Completer + listen`), the fake works as-is. **The planner must pick one approach and ensure the fake matches.**

[VERIFIED: fork source line 135-136, 487-488; test source line 357, 384, 411]

**Example — test with loading→ready (Pattern 2 compatible):**
```dart
// Source: test/playback_trust_test.dart (existing FakePlaybackEngine structure)
test('initSongs defers play() until ready when processingState starts loading', () async {
  final fake = FakePlaybackEngine();
  fake.processingState = ProcessingState.loading; // simulate Sound-Books probe
  final handler = MyAudioHandler(
    player: fake,
    configureAudioSession: false,
  );

  // Start initSongs — don't await yet
  final initFuture = handler.initSongs(
    _sampleFiles(), _sampleAudiobook(), 0, 0,
    playImmediately: true,
  );

  // Pump event loop so initSongs reaches the ready-wait
  await Future<void>.delayed(const Duration(milliseconds: 10));

  // BEFORE ready: play() should NOT have been called yet (after fix)
  // With current code, play() fires at line 565 unconditionally → playCount == 1
  expect(fake.playCount, 0); // FAILS today, PASSES after fix

  // Emit ready — simulate duration probe completing
  fake.processingState = ProcessingState.ready;
  fake.processingStates.add(ProcessingState.ready);

  await initFuture;

  // AFTER ready: play() was called
  expect(fake.playCount, 1);
});
```

### Pattern 2: Diagnostic Logging Protocol

**What:** Add temporary `AppLogger.debug` calls at 5 checkpoints in `initSongs`, tagged with `[DIAG]` prefix and `gen=$myGen` for generation tracking.

**When to use:** During Phase 1 device testing to confirm or refute the "play() dropped during buffering" hypothesis.

**Log format:**
```
[DIAG] initSongs[gen=2,active=true]: before setAudioSources, processingState=idle, playing=false
[DIAG] initSongs[gen=2,active=true]: setAudioSources resolved, processingState=buffering, threw=false
[DIAG] initSongs[gen=2,active=true]: after play(), processingState=buffering, playing=true
[DIAG] initSongs[gen=2,active=true]: 500ms after play(), processingState=ready, playing=true
```

**Key hypothesis to confirm/refute:**
- If `playing == false` at checkpoint 5 (500ms after play()), `audioSession.setActive(true)` failed (fork line 1106-1127) — `playing` was reverted to `false`, no play request sent.
- If `processingState == error` at checkpoint 2, `setAudioSources` failed (probe 404/corrupt MP3).
- If `processingState == ready` and `playing == true` at checkpoint 5 but no audio — the native (ExoPlayer) side dropped the play request during buffering (the original hypothesis).

[VERIFIED: fork source play() at line 1090-1130; AppLogger usage at my_audio_handler.dart lines 563, 570, 573]

**Example — diagnostic log insertion in initSongs:**
```dart
// Source: my_audio_handler.dart initSongs (lines 540-565), with [DIAG] additions

// CHECKPOINT 1: before setAudioSources
AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
    'before setAudioSources, processingState=${_player.processingState}, '
    'playing=${_player.playing}');

// Wrap setAudioSources in try/catch for diagnostic
try {
  await _player.setAudioSources(
    _audioSources!,
    initialIndex: sources.isEmpty ? 0 : safeIndex,
    initialPosition: currentIsYT
        ? Duration.zero
        : Duration(milliseconds: positionInMilliseconds),
    preload: playImmediately,
  );

  // CHECKPOINT 2: after setAudioSources (success)
  AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
      'setAudioSources resolved, processingState=${_player.processingState}, '
      'threw=false');
} catch (e) {
  // CHECKPOINT 2: after setAudioSources (threw)
  AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
      'setAudioSources THREW: $e, processingState=${_player.processingState}');
  rethrow; // preserve existing behavior
}

// ... existing seek logic ...

if (playImmediately) {
  // Existing log at :563 already covers checkpoint 3
  AppLogger.debug(
      'initSongs: calling _player.play(), state=${_player.processingState}');
  _player.play();

  // CHECKPOINT 4: after play() (immediate)
  AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
      'after play(), processingState=${_player.processingState}, '
      'playing=${_player.playing}');

  // CHECKPOINT 5: delayed — detect playing reversion (audioSession.setActive failure)
  Future.delayed(const Duration(milliseconds: 500), () {
    if (myGen != _initGen) return; // stale init — don't log
    AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
        '500ms after play(), processingState=${_player.processingState}, '
        'playing=${_player.playing}'
        '${_player.playing ? '' : ' ← audioSession.setActive may have failed'}');
  });
}
```

### Anti-Patterns to Avoid

- **Upgrading FakePlaybackEngine to BehaviorSubject unnecessarily:** If Phase 3 uses Pattern 2 (field-check-first), the broadcast StreamController is sufficient. Upgrading to BehaviorSubject adds an rxdart import to the test and changes the stream semantics — only do it if Phase 3 uses `firstWhere` directly. [VERIFIED: fork source line 135-136 vs test source line 357]
- **Gating diagnostic logs behind `kDebugMode`:** `AppLogger.debug` already gates `print` on `kDebugMode` (app_logger.dart:92-95), but file logging is always on. The diagnostic logs need to appear in the file log on a real device (release build) — that's the whole point. Don't add a `kDebugMode` gate. [VERIFIED: CONCERNS.md — AppLogger._writeToFile runs unconditionally]
- **Removing existing logs at 563, 570, 573:** Phase 1 adds diagnostic logs; it does NOT remove existing ones. The existing logs are part of the current play-init flow and will be cleaned up in Phase 2/3. [VERIFIED: my_audio_handler.dart lines 563-613]
- **Changing FakePlaybackEngine's class definition:** The existing structure (mutable field + broadcast stream) is sufficient. Adding a `simulateLoad` method or configurable delay is unnecessary complexity — test code can configure the fake directly. [VERIFIED: ARCHITECTURE.md "FakePlaybackEngine Enhancements Needed" section]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| loading→ready transition in fake | Custom state-machine class with delayed emission | Set `fake.processingState = loading` + `fake.processingStates.add(ready)` in test code | Existing mutable field + broadcast stream already support this pattern — no new abstraction needed |
| Diagnostic log framework | Custom log levels, conditional logging | `AppLogger.debug('[DIAG] ...')` | AppLogger is already used throughout initSongs; `[DIAG]` prefix makes logs greppable and removable |
| Test timing coordination | Complex `Completer`-based synchronization | `Future.delayed(10ms)` to pump event loop, then emit ready | Dart's event loop is deterministic enough for this; the fake's stream is synchronous on add |
| Generation tracking in logs | Custom gen-tracker class | `$myGen` interpolation in log string | `myGen` is already a local variable in `initSongs` (line 424) — just include it in the log format |

**Key insight:** This phase is the cheapest phase in the roadmap. It adds no new abstractions, no new dependencies, and no production behavior changes. The complexity is in understanding the existing fake's stream semantics and the fork's play() mechanism — both of which are now documented.

## Common Pitfalls

### Pitfall 1: FakePlaybackEngine's stream is NOT a BehaviorSubject — `firstWhere` hangs

**What goes wrong:** If Phase 3's fix uses `processingStateStream.firstWhere((s) => s == ProcessingState.ready).timeout(10s)` and the fake's `processingState` is set to `loading`, the `firstWhere` subscribes to the broadcast stream but never receives an event (broadcast streams don't replay). The `firstWhere` hangs until the 10s timeout — every test takes 10s.

**Why it happens:** The real just_audio's `processingStateStream` is backed by `BehaviorSubject<ProcessingState>.seeded(idle).stream.distinct()` (fork line 135-136, 487-488). BehaviorSubject replays the current state to new subscribers. The fake uses `StreamController<ProcessingState>.broadcast()` (test line 357) which does NOT replay.

**How to avoid:** Either (a) use ARCHITECTURE.md Pattern 2 (check `processingState` field first, then `Completer + listen` on stream) — the field check short-circuits for "already ready" and the stream listen works for "loading→ready", OR (b) upgrade the fake to `BehaviorSubject<ProcessingState>.seeded(ProcessingState.ready)` (requires `import 'package:rxdart/rxdart.dart';` in test — rxdart is in pubspec.yaml line 41).

**Warning signs:** Tests take 10s each (timeout firing); `firstWhere` never completes; test hangs.

### Pitfall 2: Diagnostic logs must NOT change production behavior

**What goes wrong:** Adding a `try/catch` around `setAudioSources` for diagnostic logging (checkpoint 2) could swallow exceptions that currently propagate to `_autoPlay`'s catch block — changing error-handling behavior.

**Why it happens:** The current `initSongs` does NOT have a try/catch around `setAudioSources` (line 540). Exceptions propagate to the caller (`_autoPlay` catch at audiobook_details.dart:133, `_playChapter` catch at :84). Adding a `try/catch` that logs and rethrows is safe, but one that logs and swallows changes behavior.

**How to avoid:** The diagnostic `try/catch` must `rethrow` after logging. The `catch` block is for logging only, not for recovery. [VERIFIED: current code has no try/catch around setAudioSources]

**Warning signs:** Sound-Books error handling changes; `_autoPlay` catch block stops receiving exceptions; behavior difference between Phase 1 and Phase 0 (pre-phase).

### Pitfall 3: Delayed diagnostic log (checkpoint 5) must gen-check

**What goes wrong:** The 500ms delayed log (checkpoint 5) fires after `initSongs` may have been superseded by a newer call. The log would show stale state, confusing the developer.

**Why it happens:** `Future.delayed(500ms, () { ... })` is fire-and-forget. If the user opens a second book within 500ms, `_initGen` has incremented. The delayed log from the first init fires and shows state from the second init's context.

**How to avoid:** Add `if (myGen != _initGen) return;` at the top of the delayed callback. Log includes `active=${myGen == _initGen}` so stale logs are clearly marked.

**Warning signs:** Logs show `gen=1,active=false` — this is a stale init's delayed log, not the active init's state.

### Pitfall 4: Test timing — emit ready AFTER initSongs reaches the ready-wait

**What goes wrong:** The test emits `processingStates.add(ready)` before `initSongs` has reached the `_waitForReadyOrTimeout` listener. The listener subscribes after the emission → misses it → hangs until timeout.

**Why it happens:** `initSongs` is async. After calling `handler.initSongs(...)`, the method hasn't necessarily reached the stream-listen point yet. If the test immediately emits `ready`, the listener hasn't subscribed.

**How to avoid:** Insert `await Future<void>.delayed(const Duration(milliseconds: 10))` between starting `initSongs` and emitting `ready`. This pumps the event loop enough for `initSongs` to reach the ready-wait. 10ms is sufficient because `initSongs`'s pre-ready-wait work (Hive writes, setAudioSources, seek) is fast in the fake (synchronous).

**Warning signs:** Test hangs for 10s (timeout); `playCount` never reaches 1.

### Pitfall 5: FakePlaybackEngine's `setAudioSources` does NOT change `processingState`

**What goes wrong:** A test expects `setAudioSources` to transition `processingState` from `loading` to `buffering` (as the real just_audio does for Sound-Books). The fake's `setAudioSources` (line 454-474) only records the call, sets `currentIndex`/`position`/`sequence`, and emits to `currentIndexes`/`positions` streams — it does NOT touch `processingState`.

**Why it happens:** The fake was designed for restore/persist/seek tests, not play-init race tests. It models a synchronous, always-ready player.

**How to avoid:** Tests must explicitly set `fake.processingState` before calling `initSongs`. The fake's `setAudioSources` not changing `processingState` is actually CORRECT for simulating Sound-Books: in the real player, `setAudioSources` resolves at `buffering` (not `ready`), so `processingState` is still not `ready` after `setAudioSources` returns. The fake just needs to start in `loading` and stay there until the test emits `ready`.

**Warning signs:** Test sets `processingState = loading` but `setAudioSources` "fixes" it to `ready` — this would be wrong (the fake doesn't do this, but a future modification might).

## Code Examples

### Example 1: The "Fails Today, Passes After Fix" Test

```dart
// Source: test/playback_trust_test.dart — new test in existing "MyAudioHandler with fake playback engine" group

test('initSongs defers play() until ready when processingState starts loading', () async {
  final fake = FakePlaybackEngine();
  fake.processingState = ProcessingState.loading; // simulate Sound-Books probe in-flight
  final handler = MyAudioHandler(
    player: fake,
    configureAudioSession: false,
  );

  // Start initSongs without awaiting
  final initFuture = handler.initSongs(
    _sampleFiles(),
    _sampleAudiobook(),
    0,
    0,
    playImmediately: true,
  );

  // Pump event loop so initSongs reaches the play() call (current code)
  // or the ready-wait (fixed code)
  await Future<void>.delayed(const Duration(milliseconds: 10));

  // ASSERTION THAT FAILS TODAY, PASSES AFTER FIX:
  // Current code: _player.play() fires at line 565 unconditionally → playCount == 1
  // Fixed code:   play() deferred until ready → playCount == 0 here
  expect(fake.playCount, 0,
      reason: 'play() must not fire before processingState reaches ready');

  // Simulate duration probe completing
  fake.processingState = ProcessingState.ready;
  fake.processingStates.add(ProcessingState.ready);

  await initFuture;

  // After ready: play() was called
  expect(fake.playCount, 1,
      reason: 'play() must fire after ready is emitted');
});
```

### Example 2: Already-Ready Short-Circuit Test (passes with both current + fixed code)

```dart
// Source: test/playback_trust_test.dart — verifies zero-latency for known-duration sources

test('initSongs with playImmediately=true and ready state calls play() immediately', () async {
  final fake = FakePlaybackEngine();
  // processingState defaults to ProcessingState.ready (line 384)
  final handler = MyAudioHandler(
    player: fake,
    configureAudioSession: false,
  );

  await handler.initSongs(
    _sampleFiles(),
    _sampleAudiobook(),
    0,
    0,
    playImmediately: true,
  );

  expect(fake.playCount, 1);
  expect(fake.setAudioSourcesCalls, hasLength(1));
});
```

### Example 3: playImmediately=false Does NOT Call play()

```dart
// Source: test/playback_trust_test.dart — explicit test for the restore path

test('initSongs with playImmediately=false does NOT call play()', () async {
  final fake = FakePlaybackEngine();
  final handler = MyAudioHandler(
    player: fake,
    configureAudioSession: false,
  );

  await handler.initSongs(
    _sampleFiles(),
    _sampleAudiobook(),
    0,
    0,
    playImmediately: false,
  );

  expect(fake.playCount, 0);
  expect(fake.setAudioSourcesCalls, hasLength(1));
});
```

### Example 4: Diagnostic Log Insertion (minimal, [DIAG]-tagged)

```dart
// Source: my_audio_handler.dart initSongs — diagnostic checkpoints
// NOTE: These are TEMPORARY. Remove in Phase 3 after the fix is verified.

// CHECKPOINT 1 — before setAudioSources (line ~539)
AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
    'before setAudioSources, processingState=${_player.processingState}, '
    'playing=${_player.playing}');

// CHECKPOINT 2 — after setAudioSources (wrap existing call)
Duration? _diagDuration;
try {
  _diagDuration = await _player.setAudioSources(
    _audioSources!,
    initialIndex: sources.isEmpty ? 0 : safeIndex,
    initialPosition: currentIsYT
        ? Duration.zero
        : Duration(milliseconds: positionInMilliseconds),
    preload: playImmediately,
  );
  AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
      'setAudioSources OK, duration=${_diagDuration?.inMilliseconds}ms, '
      'processingState=${_player.processingState}');
} catch (e) {
  AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
      'setAudioSources THREW: $e, processingState=${_player.processingState}');
  rethrow;
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| FakePlaybackEngine always `ready` | Test-code configures `loading` + emits `ready` | Phase 1 (this phase) | Race condition becomes testable |
| No diagnostic logging in `initSongs` | 5 checkpoint logs with `[DIAG]` + `gen` tags | Phase 1 (this phase) | Failure mechanism verifiable on device |
| `firstWhere(ready)` on stream assumed safe | Must verify fake's stream is BehaviorSubject or use field-check-first | This research | Prevents test hangs |

**Deprecated/outdated:**
- None — this is the first phase, no prior approach to deprecate.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 10ms `Future.delayed` is sufficient for `initSongs` to reach the ready-wait point in the fake | Code Examples (Example 1) | Test may hang if initSongs hasn't subscribed to stream yet — increase to 50ms |
| A2 | `AppLogger.debug` file logging works on Android release builds (not just debug) | Architecture Patterns (Pattern 2) | Diagnostic logs invisible on device — use `AppLogger.warning` or increase log level |
| A3 | Sound-Books probe URLs are stable enough for 3+ device tests during Phase 1 | Open Questions | URLs may change or go offline — developer should collect fresh URLs at test time |
| A4 | The fake's broadcast `StreamController` (not BehaviorSubject) is sufficient for Phase 3's fix if Pattern 2 is used | Common Pitfalls (Pitfall 1) | If Phase 3 uses `firstWhere` directly, tests hang — must upgrade fake to BehaviorSubject |

## Open Questions

1. **Which ready-wait approach will Phase 3 use?**
   - What we know: ARCHITECTURE.md Pattern 2 (field-check-first + Completer/listen) works with the existing fake. STACK.md recommends `firstWhere(ready).timeout(10s)` which requires BehaviorSubject.
   - What's unclear: The planner hasn't picked one yet.
   - Recommendation: Phase 1 should write tests that work with BOTH approaches — use field-check-first in the test's assertions (check `playCount` at specific timing points, not stream semantics). If Phase 3 picks `firstWhere`, upgrade the fake to BehaviorSubject at that time.

2. **Sound-Books probe-duration distribution**
   - What we know: Sound-Books m3u files return `length: 0` (soundbooks_detail_service.dart:253), forcing just_audio to network-probe the MP3 for duration. The 10s timeout is a reasonable default.
   - What's unclear: Actual probe durations on real networks (WiFi, cellular, slow CDN).
   - Recommendation: Phase 1 device testing collects 3+ probe-duration data points from `[DIAG]` logs. If all probes complete <2s, 10s is generous. If any probe takes >5s, consider increasing to 15s.

3. **Does `audioSession.setActive(true)` actually fail for Sound-Books?**
   - What we know: Fork `play()` at line 1106 awaits `audioSession.setActive(true)`. If it fails, `playing` reverts to `false` (line 1127). No play request sent.
   - What's unclear: Whether this is the actual failure mechanism or just a theoretical possibility.
   - Recommendation: Checkpoint 5 (500ms delayed log) checks `playing`. If `playing == false` at 500ms, `setActive` failed — this refutes the "dropped during buffering" hypothesis and points to audio-session activation failure.

4. **No CONTEXT.md exists for this phase — should discuss-phase have been run?**
   - What we know: No CONTEXT.md in `.planning/phases/01-diagnostic-verification-test-infrastructure/`. The phase was created from the roadmap directly.
   - What's unclear: Whether the user intended to skip discuss-phase or it was omitted.
   - Recommendation: Proceed with research — the phase description + success criteria are clear enough. The planner has sufficient context from the project-level research docs.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | Test execution, compilation | ✓ | 3.44.1 (stable) | — |
| Dart SDK | Test execution | ✓ | ^3.5.4 (via Flutter) | — |
| rxdart | BehaviorSubject (if fake upgrade needed) | ✓ | ^0.28.0 (pubspec line 41) | Use broadcast StreamController with field-check-first |
| Android device | Diagnostic logging on real device | — | — | No fallback — device testing is required for success criterion 2 |
| Sound-Books URLs | Probe-duration testing (criterion 3) | — | — | Developer must collect by browsing app |

**Missing dependencies with no fallback:**
- Android device with FlowBook installed — required for on-device diagnostic logging (success criterion 2). Cannot be substituted with emulator (emulator network conditions don't reflect real Sound-Books CDN behavior).

**Missing dependencies with fallback:**
- None — all code/test dependencies are available.

## Security Domain

> Phase 1 adds diagnostic logs and test cases. No external input handling, no auth, no crypto, no new API endpoints. Security surface is minimal.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — (no auth changes) |
| V3 Session Management | no | — (no session changes) |
| V4 Access Control | no | — (no access control changes) |
| V5 Input Validation | no | — (no new input paths; diagnostic logs are developer-authored strings, not user input) |
| V6 Cryptography | no | — (no crypto changes) |
| V7 Error Handling & Logging | yes | AppLogger is the existing logging facility; diagnostic logs use `AppLogger.debug` with `[DIAG]` prefix. No sensitive data logged (no credentials, no PII — logs contain `processingState` enum values and `playing` boolean only). Existing CONCERNS.md flag about AppLogger writing to external storage applies but is not changed by this phase. |
| V9 Communications | no | — (no new network calls) |
| V10 Malicious Code | no | — (no new dependencies) |

### Known Threat Patterns for Diagnostic Logging

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Log injection (if diagnostic logs include user-controlled data) | Tampering | Diagnostic logs only include `processingState` enum values, `playing` boolean, `myGen` int, and exception `toString()`. No user input flows into log strings. [VERIFIED: initSongs parameters are audiobook files + IDs, not user input] |
| Information disclosure via log file | Information Disclosure | AppLogger writes to external storage (`log/applogs.txt`). CONCERNS.md flags this as a known issue. Phase 1 diagnostic logs add `processingState` + `playing` — no sensitive data. Existing risk unchanged. [CITED: CONCERNS.md] |

## Project Constraints (from AGENTS.md)

- **Flutter 3.44.1 / Dart ^3.5.4** — no version changes [VERIFIED: flutter --version]
- **Forked `just_audio`** (`sagarchaulagai/just_audio.git @ a6f8db8`) — `ProcessingState` / `setAudioSources` semantics pinned to fork; don't assume upstream behavior [VERIFIED: pub-cache source read]
- **No new dependencies** — Phase 1 uses only existing packages (`flutter_test`, `just_audio`, `rxdart` available, `AppLogger`) [VERIFIED: pubspec.yaml]
- **Don't break `playback_trust_test.dart`** — existing 520-line test suite must stay green; Phase 1 ADDS tests, doesn't modify existing ones [VERIFIED: test source read]
- **Minimal scope** — diagnostic logs + test infrastructure only; no loading-feedback UI, no cross-source hardening, no details-screen redesign [VERIFIED: PROJECT.md Out-of-Scope]
- **Caveman communication mode** — active; code/commits written normal [VERIFIED: AGENTS.md]

## Sources

### Primary (HIGH confidence)
- `test/playback_trust_test.dart` — `FakePlaybackEngine` (lines 350-499), `StreamController<ProcessingState>.broadcast()` (line 357), `processingState = ProcessingState.ready` (line 384), `processingStateStream` getter (line 411), `setAudioSources` (lines 454-474), `play()` (lines 421-425), 3 initSongs tests (lines 211, 244, 267)
- `lib/resources/services/my_audio_handler.dart` — `PlaybackEngine` abstract (lines 40-77), `JustAudioPlaybackEngine` (lines 79-189), `initSongs` (lines 416-642), `_isReinitializing` (line 214), `_initGen` (line 215), `_player.play()` fire-and-forget (line 565), `processingStateStream.listen` re-fire (line 569), `Future.delayed(60s, sub.cancel())` (line 608), orphan logging listener (lines 611-613), `_waitForProcessingReady` poll (lines 650-657), unconditional `finally { _isReinitializing = false; }` (line 640), `play()` override (lines 877-885)
- Fork source: `~/.pub-cache/git/just_audio-a6f8db8ded43bdff0e39766fbbdbab8f22cadc2c/just_audio/lib/just_audio.dart` — `_processingStateSubject = BehaviorSubject<ProcessingState>.seeded(ProcessingState.idle)` (line 135-136), `processingStateStream` getter (line 487-488), `setAudioSources` (lines 885-911), `_load` with `firstWhere(state != loading)` (lines 995-1042, specifically line 1034-1035), `play()` with `audioSession.setActive` gate (lines 1090-1130, specifically line 1097 synchronous broadcast, line 1106 await setActive, line 1107 `if (!playing) return`, line 1127 revert playing), `seek()` silent no-op during loading (lines 1346-1375, specifically line 1350-1351)
- `lib/resources/services/soundbooks/soundbooks_detail_service.dart` — `_parseM3uPlaylist` (lines 194-261), `'length': 0` (line 253), `'durationMs': null` (line 258) — confirms Sound-Books files come back with no duration metadata
- `lib/screens/audiobook_details/audiobook_details.dart` — `_playChapter` (lines 67-92), `_autoPlay` (lines 94-136), big play button `onTap` (lines 513-557), `_autoPlayTriggered` (line 65), auto-play fires on first `AudiobookDetailsLoaded` (lines 397-401)
- `.planning/research/STACK.md` — fork diff verification, canonical play-init sequence, `processingStateStream` BehaviorSubject semantics
- `.planning/research/ARCHITECTURE.md` — Pattern 2 `_waitForReadyOrTimeout` helper, FakePlaybackEngine enhancement analysis, data flow sequence
- `.planning/research/PITFALLS.md` — Pitfall 1 (wrong race mechanism), Pitfall 6 (FakePlaybackEngine can't test fix), Pitfall 7 (seek no-op during loading)
- `.planning/research/FEATURES.md` — fork play() stickiness flag, test coverage gaps
- `.planning/codebase/CONCERNS.md` — 60s Future.delayed fire-and-forget (line 89), AppLogger external storage logging
- `.planning/config.json` — `nyquist_validation: false` (skip Validation Architecture), `security_enforcement: true` with `security_asvs_level: 1`
- `pubspec.yaml` — `rxdart: ^0.28.0` (line 41), `flutter_test` (line 76)
- `analysis_options.yaml` — `flutter_lints/flutter.yaml` ruleset, `scratch/**` excluded

### Secondary (MEDIUM confidence)
- None — all findings are from direct source code reading

### Tertiary (LOW confidence)
- None — no web search or training-data-based claims

## Metadata

**Confidence breakdown:**
- FakePlaybackEngine analysis: HIGH — direct source code reading, line-by-line
- Fork play() mechanism: HIGH — direct pub-cache source reading, line-by-line
- Diagnostic logging protocol: HIGH — based on existing AppLogger usage + fork play() source
- Test shape (fails today, passes after fix): HIGH — derived from current initSongs behavior (line 565 unconditional play) vs fix behavior (deferred play)
- Stream semantics (BehaviorSubject vs broadcast): HIGH — verified in fork source (line 135-136) and test source (line 357)

**Research date:** 2026-07-14
**Valid until:** 2026-08-14 (30 days — stable codebase, no external API dependencies)
