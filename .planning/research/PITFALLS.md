# Pitfalls Research

**Domain:** just_audio / audio_service play-init race fixing in a Flutter audiobook player (forked just_audio, shared multi-source initSongs)
**Researched:** 2026-07-14
**Confidence:** HIGH (fork source code read directly from pub-cache; just_audio README state-model verified; codebase analysis from source)

## Critical Pitfalls

### Pitfall 1: Fixing the wrong race — assuming `play()` is dropped during buffering when the official design says it should work

**What goes wrong:**
The fixer reads PROJECT.md's diagnosis ("play() fired while loading/buffering → dropped") and writes a fix that awaits `ProcessingState.ready` before calling `play()`, or restructures the listener to re-fire `play()` on `ready`. But the official just_audio state model (verified in the upstream README and confirmed in the fork source at `just_audio.dart:1090`) says: `play()` sets `playing = true` immediately, and audio begins automatically when `processingState` reaches `ready`. The `playing` flag is the user's intent (orthogonal to `processingState`). Re-firing `play()` on `ready` is redundant — `if (playing) return;` at fork line 1092 makes the second call a no-op. If the real bug is elsewhere (fork-specific `play()`/`seek` interaction, `setAudioSources` throw, audio-session activation failure, or ExoPlayer probe timing), the fix addresses the wrong layer and Sound-Books still doesn't auto-play.

**Why it happens:**
PROJECT.md's root-cause analysis is a hypothesis, not a confirmed mechanism. The code analysis shows the listener at line 569 uses a `BehaviorSubject` (async, no `sync: true`) which replays the current value to new listeners — so the listener CANNOT miss the `ready` transition (it receives the current state on the next microtask, then subsequent transitions). The `play()` at line 565 sets `playing = true` synchronously. Per the official design, audio should start when `ready` is reached. The actual failure mechanism is uncertain and may be fork-specific.

**How to avoid:**
- Before writing the fix, VERIFY the actual failure mechanism: add temporary logging at `play()` entry/exit, `setAudioSources` return, `processingState` transitions, and `audioSession.setActive()` result. Test on a real device with a Sound-Books URL.
- Check whether `setAudioSources` throws `PlayerException` or `PlayerInterruptedException` for Sound-Books URLs (the fork's simultaneous-load fix at commit `bf26a62` changed 130 lines in the load path — this may interact with the stop-then-load sequence in `initSongs`).
- Check whether `audioSession.setActive(true)` fails (fork `play()` line 1106 — if it fails, `playing` is reverted to `false` at line 1127 and no play request is sent).
- Do not assume the fix is "await ready before play." The fix might be: ensure `setAudioSources` doesn't throw, ensure the audio session is activated before `play()`, or ensure `stop()` at line 442 doesn't race with the new `setAudioSources`.
- Design the fix to be robust to ALL timing scenarios (ready-before-play, ready-after-play, ready-during-seek, never-ready), not just one hypothesized race.

**Warning signs:**
- Fix is merged but Sound-Books still doesn't auto-play on real device
- Log shows `initSongs: calling _player.play(), state=ready` (state was already ready — play should have worked)
- Log shows `initSongs: player ready, ensuring play` from the listener (listener DID catch ready — but playback still didn't start)
- `PlayerException` or `PlayerInterruptedException` in logs during `setAudioSources`

**Phase to address:**
Implementation phase — but FIRST a diagnostic/verification step (add logging, test on device, confirm mechanism) should be a precursor sub-step. Do not write the fix until the mechanism is confirmed.

---

### Pitfall 2: `finally { _isReinitializing = false; }` clobbers a newer `initSongs` still in flight

**What goes wrong:**
`initSongs` sets `_isReinitializing = true` at line 423, increments `_initGen` at line 424, and unconditionally clears `_isReinitializing = false` in the `finally` block at line 640. If a newer `initSongs` starts while an older one is awaiting (e.g., user rapidly taps two books), the older one hits a gen check (`if (myGen != _initGen) return;` at lines 526, 549, or 622) and returns early. Its `finally` block runs and sets `_isReinitializing = false` — but the NEWER `initSongs` is still running and needs `_isReinitializing` to remain `true`. Now `_isReinitializing` is `false` while the newer init is mid-flight. Code that checks `_isReinitializing` (`_persistInstant` at line 266, `_restoreQueueFromBoxIfEmpty` at line 843, `_listenForCurrentSongIndexChanges` at line 685, the position timer at line 781) incorrectly believes reinit is done. Position writes hit Hive for the wrong audiobook. Restore-from-box can fire and call `initSongs` again, creating a third concurrent init.

**Why it happens:**
The `finally` block is unconditional. The gen guard checks protect the return path but not the `finally` side effect. This is an existing bug in the current code, but any fix that adds a new `await` inside `initSongs` (e.g., await-for-ready) WIDENS the race window — the longer the older init awaits, the more likely a newer init starts and the finally clobbers happens.

**How to avoid:**
- Guard the `finally` with a gen check:
  ```dart
  finally {
    if (myGen == _initGen) {
      _isReinitializing = false;
    }
  }
  ```
- Only the newest init (the one whose `myGen == _initGen`) should clear `_isReinitializing`. Older inits that return early via gen check must NOT clear it.
- Add a test: call `initSongs` twice in rapid succession (second call while first is still awaiting). Assert `_isReinitializing` is `true` after the first returns early and `false` only after the second completes.

**Warning signs:**
- `_persistInstant` writes position to Hive for audiobook A while audiobook B is loading
- `_restoreQueueFromBoxIfEmpty` fires during a reinit and starts a third `initSongs`
- Log shows `_isReinitializing` flipping to `false` then back to `true` (older finally ran, newer init re-set it — but the window in between allowed spurious restores/persists)
- `playback_trust_test.dart` passes (fake is synchronous, no race) but real device shows position corruption after rapid book switching

**Phase to address:**
Implementation phase — must be fixed as part of any `initSongs` restructuring. This is a precondition: if the fix adds an await inside `initSongs`, this bug MUST be fixed first or the race window widens.

---

### Pitfall 3: The 60s `Future.delayed` listener cancel creates orphaned subscriptions that re-fire `play()` on stale transitions

**What goes wrong:**
Line 608: `Future.delayed(const Duration(seconds: 60), () => sub.cancel())` is fire-and-forget. When `initSongs` re-enters (user opens a new book within 60s), a new `sub` is created at line 569, but the OLD `Future.delayed` is still pending — it will fire in ~60s and cancel the OLD `sub`. But the old `sub` was never explicitly cancelled when the new `initSongs` started. Between the new `initSongs` and the 60s expiry, the old `sub` is still listening to `processingStateStream`. When the new book's `setAudioSources` triggers state transitions (`loading` → `buffering` → `ready`), the old `sub` receives them and calls `_player.play()` — on the NEW book's player state. This is harmless if `playing` is already `true` (no-op), but if the old `sub`'s 30s-stuck-buffering skip fires (line 590-603), it calls `_player.seekToNext()` on the new book, skipping to the wrong track.

**Why it happens:**
The subscription `sub` is a local variable, not a field. There's no way for the next `initSongs` to cancel it. The `Future.delayed` is the only cancellation path, and it's detached from the `initSongs` lifecycle. Multiple `Future.delayed` futures stack across re-entries.

**How to avoid:**
- Track the subscription in a field: `StreamSubscription<ProcessingState>? _initSettleSub;`
- At the TOP of `initSongs` (before any async work), cancel the previous: `_initSettleSub?.cancel(); _initSettleSub = null;`
- Assign: `_initSettleSub = _player.processingStateStream.listen(...);`
- In `dispose()`: `_initSettleSub?.cancel();`
- Drop the `Future.delayed(60s, ...)` entirely. If a timeout is needed, use `.timeout()` on the stream or a `Timer` that is also tracked and cancelled.
- The gen guard does NOT protect the listener's `_player.play()` call — the listener calls `_player.play()` directly, not through a gen-checked path. Either add a gen check inside the listener callback, or cancel the sub before it can fire on stale state.

**Warning signs:**
- Log shows `initSongs: player ready, ensuring play` firing multiple times for a single `ready` transition (stacked listeners)
- Track skip happens unexpectedly (old listener's 30s-stuck-buffering skip fires on new book)
- `_player.seekToNext()` called when user didn't press skip
- Memory profiling shows N `StreamSubscription` objects after N book opens

**Phase to address:**
Implementation phase — replace the fire-and-forget cancel with a tracked field as part of the listener restructuring.

---

### Pitfall 4: The second orphan listener at line 611 leaks on every `initSongs` call

**What goes wrong:**
Line 611-613:
```dart
_player.processingStateStream.listen((state) {
  AppLogger.debug('initSongs: player processingState=$state');
});
```
This debug-only listener is NEVER cancelled. It has no variable reference, no `Future.delayed` cancel, no field tracking. Every `initSongs` call creates a new one. Over a session of 20 book opens, 20 listeners accumulate on `processingStateStream`. Each one fires on every state transition, calling `AppLogger.debug`. While the individual cost is low (a debug log), the cumulative effect is: 20 log lines per state transition, 20 active subscriptions holding references, and a slow memory leak that persists until the `MyAudioHandler` is disposed (which, per CONCERNS.md, never happens for the throwaway handler).

**Why it happens:**
The listener was likely added for debugging during the initial Sound-Books investigation and never cleaned up. It has no functional purpose — it only logs. It was probably copied along with the functional listener at 569 and forgotten.

**How to avoid:**
- DELETE lines 611-613 entirely. The functional listener at 569 already logs `processingState` (line 570: `AppLogger.debug('initSongs: processingState=$state')`). The orphan is pure duplication.
- If debug logging is needed, add it INSIDE the functional listener's callback (which is already tracked/cancelled).
- Add a lint rule or code review check: no bare `.listen()` calls without a variable assignment or `.cancel()` plan.

**Warning signs:**
- Log file grows rapidly with repeated `initSongs: player processingState=` lines (N× per transition after N book opens)
- Heap snapshot shows N `StreamSubscription` objects tied to `processingStateStream`

**Phase to address:**
Implementation phase — delete as part of the listener cleanup. Trivial fix, but must not be forgotten.

---

### Pitfall 5: `_listenForCurrentSongIndexChanges` leaks a `currentIndexStream` listener on every `initSongs` call

**What goes wrong:**
`_listenForCurrentSongIndexChanges()` (line 683) is called at the end of `initSongs` (line 624). It attaches a `_player.currentIndexStream.listen(...)` listener that writes to Hive (`playingAudiobookDetailsBox.put('index', index)` at line 693) and calls `_persistNow` (line 701). This listener is NEVER cancelled. Every `initSongs` call stacks another one. After 10 book opens, 10 listeners fire on every track change. Each one writes to Hive — 10× writes per index change. The `if (_isReinitializing) return;` guard at line 685 helps (skips during reinit), but after reinit completes, all 10 are active.

**Why it happens:**
The method creates a local listener with no field tracking, no cancellation. Like the orphan at 611, it was never designed for reuse across `initSongs` calls. The `_isReinitializing` guard prevents writes DURING reinit but not AFTER — the old listeners resume firing once the new `initSongs` completes.

**How to avoid:**
- Track in a field: `StreamSubscription<int?>? _indexChangeSub;`
- At the top of `initSongs`: `_indexChangeSub?.cancel();`
- In `_listenForCurrentSongIndexChanges`: `_indexChangeSub = _player.currentIndexStream.listen(...);`
- In `dispose()`: `_indexChangeSub?.cancel();`
- Alternatively, attach the listener ONCE in the constructor (or `_bindStatePipelines`) rather than per-`initSongs` call, since the listener already guards on `_isReinitializing` and `_activeAudiobookId`.

**Warning signs:**
- Hive box `playingAudiobookDetailsBox` receives N writes per track change (check via Hive box `watch`)
- Position/index corruption: old audiobook's index gets overwritten by new audiobook's track change (if old listener fires after new init)
- Test: call `initSongs` 3 times, skip a track, assert `playCount` of Hive writes is 1, not 3

**Phase to address:**
Implementation phase — fix as part of listener lifecycle cleanup. Must be done alongside the `_initSettleSub` fix (Pitfall 3) since both involve tracked subscriptions.

---

### Pitfall 6: `FakePlaybackEngine` does not simulate the loading→ready transition, making the fix untestable

**What goes wrong:**
`FakePlaybackEngine` (test/playback_trust_test.dart:350) initializes `processingState = ProcessingState.ready` (line 384). `setAudioSources` (line 454) does NOT change `processingState`. `processingStateStream` is a broadcast `StreamController` (line 357) that never emits unless test code manually calls `processingStates.add(...)`. So:
- Any fix that `await`s `processingState == ready` returns immediately (fake is already ready).
- Any fix that listens for `ready` on `processingStateStream` never fires (stream is empty).
- The race condition (play during loading/buffering, ready arrives later) is INVISIBLE in tests.
- Tests pass even if the fix is wrong — the fake can't distinguish "play worked because state was ready" from "play was correctly deferred until ready."

**Why it happens:**
The fake was designed to test restore/persist/seek invariants, not the play-init race. It models a synchronous, always-ready player — the happy path. The Sound-Books bug is specifically about the async loading→ready transition, which the fake doesn't model.

**How to avoid:**
- BEFORE touching `initSongs`, extend `FakePlaybackEngine` to simulate the loading→ready transition:
  - Add a configurable initial `processingState` (default `ready` for backward compat, but allow `loading` or `buffering`).
  - In `setAudioSources`, if a "simulateLoad" flag is set, set `processingState = loading`, then emit `ready` on `processingStates` after a configurable delay (e.g., `Future.delayed(Duration(milliseconds: 50), () { processingState = ProcessingState.ready; processingStates.add(ProcessingState.ready); })`).
  - Add a `simulateNetworkError` mode where `setAudioSources` throws or transitions to `error`.
 - Write a test that uses the extended fake: `initSongs` with `processingState` starting at `loading`, assert `play()` is called AFTER `ready` is emitted, not before.
- Without this extension, any fix to the play-init sequence is UNTESTABLE — you're testing against a fake that can't reproduce the bug.

**Warning signs:**
- Fix passes all tests but fails on real device
- Test coverage shows `initSongs` play-sequence branch is covered, but the `processingState == loading` path is never exercised
- No test asserts the ordering "ready before play" or "play deferred until ready"

**Phase to address:**
PRECURSOR phase — extend `FakePlaybackEngine` BEFORE the implementation phase. This is a blocking dependency: the implementation phase cannot be verified without it.

---

### Pitfall 7: Fork's `seek()` is a silent no-op during `ProcessingState.loading`

**What goes wrong:**
The fork's `seek()` method (just_audio.dart:1346-1375) has:
```dart
switch (processingState) {
  case ProcessingState.loading:
    return;  // SILENT NO-OP
  default:
    ...
```
If the fix calls `seek()` before `setAudioSources` completes (or if the state re-enters `loading` after a re-init), `seek()` returns immediately without seeking. The position and index are NOT set. The player starts at whatever position ExoPlayer defaults to (typically position 0 of the initial index). For a resumed audiobook (position 123456ms, index 2), the user hears the beginning of track 1 instead of the resumed position.

**Why it happens:**
The current code at line 558 calls `await _player.seek(...)` AFTER `await _player.setAudioSources(...)`. Since `setAudioSources` with `preload: true` awaits `processingStateStream.firstWhere((state) => state != loading)`, the state should NOT be `loading` when `seek` is called. But:
- If a newer `initSongs` interrupts (via `_pluginLoadRequest?.interrupted = true` at fork line 892), the state may re-enter `loading`.
- If the fix reorders operations (e.g., seeks before `setAudioSources` completes), `seek` hits the `loading` case.
- The fork's "Fix simultaneous load bug" (commit `bf26a62`) changed the load interruption logic — a new `setAudioSources` can interrupt an in-flight one, potentially leaving the state in `loading` transiently.

**How to avoid:**
- NEVER call `seek()` before `setAudioSources` has completed. The current order (setAudioSources → seek) is correct.
- After `await _player.seek(...)`, verify the seek took effect: check `_player.currentIndex == expectedIndex` and `_player.position ≈ expectedPosition`. If not, log a warning.
- If the fix adds an await-for-ready between `setAudioSources` and `seek`, ensure the state doesn't re-enter `loading` during the wait (gen check before seek).
- Do not assume `seek()` throws or returns an error on failure — it silently returns `void`.

**Warning signs:**
- User resumes a book at position 30:00 but playback starts at 0:00 of track 1
- Log shows `seek` called but `_player.position` remains 0
- `_waitForStartToSettle` (line 659) times out every time (position never reaches expected)

**Phase to address:**
Implementation phase — ensure the fix's operation ordering doesn't place `seek()` before `setAudioSources` completes. Add a post-seek verification log.

---

### Pitfall 8: Awaiting `ProcessingState.ready` can deadlock if the source never becomes ready (404, corrupt MP3, network error)

**What goes wrong:**
If the fix adds `await _waitForProcessingReady(timeout: ...)` or `await processingStateStream.firstWhere((s) => s == ProcessingState.ready)` inside `initSongs`, and the Sound-Books URL returns 404, the MP3 is corrupt, or the network drops, the state never reaches `ready`. It transitions to `error` (or stays in `buffering` forever on some ExoPlayer versions). The await blocks until its timeout. During this block:
- `_isReinitializing` remains `true` (if the finally bug isn't fixed, or even if it is, the current init is still in flight).
- The UI shows a loading state with no feedback (PROJECT.md explicitly defers loading feedback).
- The user can't start a different book — `initSongs` is blocked, and a new call would increment `_initGen` but the old call is still awaiting.
- If the timeout is too long (e.g., 60s), the user waits 60s with no playback and no way to cancel.
- If the timeout is too short (e.g., 3s), slow networks fail even for valid URLs.

**Why it happens:**
`ProcessingState.ready` is not guaranteed. The valid transitions are: `idle → loading → buffering → ready → completed` and `idle → loading → error`. The fix must handle `error` and `buffering` (stuck) states, not just `ready`.

**How to avoid:**
- Use a bounded timeout (10-15s for Sound-Books, which just needs a duration probe, not a full download). The existing `_waitForProcessingReady` (line 650) uses 5s for YouTube — Sound-Books should be similar.
- Check for `error` state explicitly: `if (_player.processingState == ProcessingState.error) { log and abort; }`
- After the timeout, check the state: if `buffering`, proceed with `play()` anyway (the `playing = true` flag means audio will start when buffering completes). If `error`, abort with a user-visible error. If `ready`, proceed normally.
- Do NOT use `processingStateStream.firstWhere((s) => s == ProcessingState.ready)` without a `.timeout()` — it will hang forever on error.
- The correct pattern:
  ```dart
  try {
    await _player.processingStateStream
        .firstWhere((s) => s == ProcessingState.ready || s == ProcessingState.error)
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    // timeout — proceed with play() anyway, playing flag is already set
  }
  if (myGen != _initGen) return;
  if (_player.processingState == ProcessingState.error) {
    AppLogger.error('initSongs: source entered error state');
    return; // or throw
  }
  _player.play();
  ```

**Warning signs:**
- App hangs for N seconds when opening a Sound-Books book with a dead URL
- `_isReinitializing` stays `true` for 60s (or whatever the timeout is)
- User can't open a different book while the first is stuck
- `ANR` (Application Not Responding) on Android if the await blocks the platform thread (shouldn't happen in Dart, but the UI freezes)

**Phase to address:**
Implementation phase — the await-for-ready logic must include error-state handling and a bounded timeout. This is a core part of the fix, not an edge case.

---

### Pitfall 9: Cross-source regression — awaiting ready slows down sources that are already ready synchronously

**What goes wrong:**
LibriVox, YouTube, knigavuhe, and 4read sources return durations in their API responses. Their `setAudioSources` with `preload: true` resolves to `ready` synchronously (or near-synchronously) because the duration is known and ExoPlayer doesn't need a network probe. If the fix adds `await _waitForProcessingReady(...)` inside the shared `initSongs` for ALL sources (not just Sound-Books), it adds a polling delay (50ms per iteration in the existing `_waitForProcessingReady` at line 655) even for sources that are already ready. The first iteration checks `_player.processingState == ProcessingState.ready` — if already ready, it returns immediately. But if there's even one microtask between `setAudioSources` returning and the check, the state might still be transitioning. The existing `_waitForStartToSettle` (line 659, 3s timeout) already adds latency — adding another wait compounds it.

**Why it happens:**
The fix lives in shared `initSongs` code. Sound-Books needs the wait; other sources don't. Without a conditional, the wait applies to all sources.

**How to avoid:**
- Check `processingState` FIRST: if already `ready`, skip the wait entirely.
  ```dart
  if (_player.processingState != ProcessingState.ready) {
    await _waitForProcessingReady(timeout: const Duration(seconds: 10));
  }
  ```
- The existing `_waitForProcessingReady` (line 650) already does this — its first iteration returns immediately if ready. But verify the fork's `setAudioSources` doesn't leave the state in `loading` for known-duration sources (it shouldn't, since `setAudioSources` awaits `firstWhere(state != loading)`).
- Run `playback_trust_test.dart` after the fix — the test calls `initSongs` with `FakePlaybackEngine` (always ready). If the fix adds a wait, the test should still pass instantly (fake is ready).
- Test on real device: open a LibriVox book, measure time from tap to audio start. Compare before/after fix. If latency increases by >100ms, the wait is not short-circuiting.

**Warning signs:**
- LibriVox/YouTube auto-play feels slower after the fix
- `playback_trust_test.dart` tests take longer to complete (fake is synchronous, but if the wait uses `Future.delayed`, pumps are needed)
- User reports "opening books feels laggy" after the fix

**Phase to address:**
Implementation phase — the wait must short-circuit on `ready`. Verify with before/after timing on real device for a known-duration source.

---

### Pitfall 10: `AudioHandlerProvider` cold-start race — deferring `play()` past the `AudioService.init` swap loses the play call on the real handler

**What goes wrong:**
`AudioHandlerProvider` (audio_handler_provider.dart:6) creates a throwaway `MyAudioHandler()` at field-init time. `initialize()` (called in `addPostFrameCallback`) replaces it with the real `AudioService.init` handler. Between `runApp()` and `initialize()` completion, `audioHandler` returns the throwaway. If the fix defers `play()` until after `ready` (e.g., via a listener callback that fires 200ms later), and `initialize()` completes in that window, the `play()` call lands on the throwaway handler. The throwaway's `AudioPlayer` starts playing, but it's NOT connected to `AudioService` — no media notification, no background playback, no lockscreen controls. The real handler (which replaced the throwaway) never receives the `play()` call. The user hears audio but has no notification controls.

**Why it happens:**
The throwaway handler is a separate `MyAudioHandler` instance with its own `AudioPlayer`. The real handler is a different instance. There's no bridge between them. A `play()` call on the throwaway is isolated — it doesn't propagate to the real handler. The throwaway is never disposed (CONCERNS.md: "The first instance is never disposed").

**How to avoid:**
- The fix should NOT defer `play()` to a callback that might fire after `AudioService.init` completes. If the fix uses a listener, the listener is on the throwaway's `_player.processingStateStream` — it fires on the throwaway, not the real handler.
- The correct approach: if the fix needs to defer `play()`, do it INSIDE `initSongs` (which is called on whatever handler the caller has — throwaway or real). If `initSongs` is called on the throwaway, the entire playback happens on the throwaway. The fix can't solve this — it's the cold-start race (CONCERNS.md). But the fix must not WORSEN it by widening the window.
- Minimize the time between `setAudioSources` and `play()`. If the fix adds a 10s await-for-ready, the window where the throwaway is active grows by 10s. If `initialize()` completes during that 10s, the play() is lost on the real handler.
- The safest fix: keep `play()` call synchronous (not deferred to a listener). If the fix must await ready, do it as a bounded await inside `initSongs` before `play()`, not as a listener callback. This keeps the entire play sequence on the same handler instance.
- NOTE: This cold-start race is an existing bug (CONCERNS.md). The fix should not try to solve it (out of scope per PROJECT.md). But the fix must not WORSEN it. Document the interaction in the plan.

**Warning signs:**
- Audio plays but no media notification appears
- Background playback doesn't work (audio stops when app is backgrounded)
- Lockscreen has no media controls
- Issue only occurs on cold start (first book open after app launch), not on subsequent opens

**Phase to address:**
Implementation phase — the fix must keep the play sequence on the same handler instance. Do not defer `play()` to a detached listener. Document the cold-start interaction as a known limitation (not fixed in this milestone).

---

### Pitfall 11: The 30s stuck-buffering skip fires spuriously if the listener lifecycle changes

**What goes wrong:**
The listener at line 569 has a 30s stuck-buffering detector (lines 590-603): if `processingState == buffering` for >30s, it calls `_player.seekToNext()` + `_player.play()`. If the fix keeps this listener alive longer (e.g., by increasing the 60s cancel timeout, or by replacing it with a permanent tracked subscription), the skip can fire on slow networks where buffering takes >30s but would eventually succeed. The user's book skips to track 2 even though track 1 was about to start playing. Worse: if old listeners are stacked (Pitfall 3), multiple skip calls fire — `seekToNext()` is called N times, jumping N tracks forward.

**Why it happens:**
The 30s threshold is arbitrary and was set for the original listener lifecycle (60s max). If the listener's lifetime changes, the threshold may be inappropriate. Sound-Books MP3s on a slow connection can take >30s to buffer the first chunk (especially if the server is slow or the file is large).

**How to avoid:**
- If the fix replaces the listener with a tracked subscription, reconsider the 30s threshold. 30s for a duration probe is too aggressive — ExoPlayer only needs to fetch the first few KB to determine duration, but on a very slow connection or a slow Sound-Books server, this can take >30s.
- Increase the threshold to 60s, or make it configurable, or remove the auto-skip entirely (per PROJECT.md minimal scope, auto-skip on stuck buffering is not the feature being fixed).
- Guard the skip with a gen check: `if (myGen != _initGen) return;` before calling `seekToNext()`. Currently the listener captures `myGen` in the closure? No — the listener at 569 does NOT capture `myGen`. It calls `_player.seekToNext()` unconditionally. This is a bug: a stale listener from a previous `initSongs` can skip tracks on the new book.
- Add a gen check inside the listener:
  ```dart
  final sub = _player.processingStateStream.listen((state) {
    if (myGen != _initGen) return; // stale listener, ignore
    ...
  });
  ```

**Warning signs:**
- Track skips to track 2 (or N) unexpectedly when opening a Sound-Books book on slow network
- Log shows `initSongs: stuck in buffering for 30s, attempting skip` followed by `seekToNext`
- Multiple `seekToNext` calls in rapid succession (stacked listeners)

**Phase to address:**
Implementation phase — add gen check inside listener callback. Reconsider or remove the 30s auto-skip threshold.

---

### Pitfall 12: `play()` returns a Future that completes on playback END, not start — awaiting it blocks `initSongs` until the track finishes

**What goes wrong:**
The fork's `play()` method (just_audio.dart:1090) ends with `await playCompleter.future;` (line 1129). The `playCompleter` completes when playback completes, is paused, or is stopped. If the fix changes `_player.play()` at line 565 from fire-and-forget to `await _player.play()`, `initSongs` will block until the entire track finishes playing (or is paused/stopped). The UI will hang in a loading state, `_isReinitializing` will stay `true`, and the user can't interact with the player.

**Why it happens:**
The just_audio README confirms: `player.play();` (no await) plays without waiting for completion; `await player.play();` plays while waiting for completion. The current code at line 565 correctly uses `_player.play();` (no await). A fixer who adds `await` to "ensure play() completes" will block indefinitely.

**How to avoid:**
- NEVER `await _player.play()` inside `initSongs`. Always fire-and-forget: `_player.play();`
- If the fix needs to verify play was sent, check `_player.playing == true` after the call (synchronous — `playing` is set at fork line 1097 before any await).
- The `play()` override at line 877 (`MyAudioHandler.play()`) DOES await `_player.play()` at line 882 — this is correct for the override (it's called by media controls which expect to wait), but `initSongs` should not await it.
- The `_autoPlay` call at audiobook_details.dart:131 (`await audioHandlerProvider.audioHandler.play()`) DOES await the override. This is fine — it awaits the override, which awaits `_player.play()`, which blocks until playback ends. But this runs AFTER `initSongs` completes, so it doesn't block `initSongs`. The issue would only arise if the fix moves this await inside `initSongs`.

**Warning signs:**
- `initSongs` never returns (hangs indefinitely after `play()`)
- `_isReinitializing` stays `true` forever
- UI stuck on loading screen
- Log shows `initSongs: calling _player.play()` but no subsequent log lines

**Phase to address:**
Implementation phase — ensure the fix does not add `await` before `_player.play()`. Code review check.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Fire-and-forget `Future.delayed(60s, cancel)` | No need to track subscription in a field | Orphaned subscriptions, stacked delayed futures, stale listeners re-fire `play()` on new book's state transitions | Never — always track subscriptions in a field |
| Bare `.listen()` without variable assignment | Quick debug logging, fewer lines | Unbounded listener leak, N subscriptions after N calls, memory growth | Never in production code — always assign to a field or local with cancel plan |
| `_isReinitializing = false` in unconditional `finally` | Simple cleanup, no gen check needed | Clobbers newer initSongs's flag, allows spurious restores/persists during reinit | Never — must guard with `if (myGen == _initGen)` |
| Polling `processingState` with `Future.delayed(50ms)` loop | No stream subscription to manage | Busy-wait, 50ms latency floor, misses fast transitions between polls | Acceptable for short bounded waits (<5s) with a clear timeout; prefer `firstWhere` on stream for longer waits |
| 30s stuck-buffering auto-skip | User doesn't wait forever on dead sources | Skips valid tracks on slow networks, fires spuriously from stale listeners | Only with gen guard + configurable threshold; remove if not needed for this milestone |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Forked `just_audio` `setAudioSources` | Assuming upstream 0.10.5 semantics | Fork at `a6f8db8` includes "Fix simultaneous load bug" (bf26a62, 130 lines changed). `setAudioSources` immediately marks existing load as interrupted (`_pluginLoadRequest?.interrupted = true`). Read the fork source, not upstream docs. |
| Forked `just_audio` `seek()` | Assuming seek throws or waits during loading | Fork's `seek()` returns silently if `processingState == loading` (line 1350-1351). No error, no warning. Always verify seek took effect. |
| Forked `just_audio` `play()` | Awaiting `play()` to know playback started | `play()` Future completes on playback END, not start. Use fire-and-forget; check `_player.playing` for immediate confirmation. |
| Forked `just_audio` `processingStateStream` | Assuming broadcast stream misses events | BehaviorSubject (async, no `sync:true`) replays current value to new listeners. Listener cannot miss `ready` transition — it receives current state on next microtask, then transitions. |
| `audio_service` `BaseAudioHandler` override | Calling `_restoreQueueFromBoxIfEmpty()` in `play()` without expecting `_isReinitializing` guard | The guard at line 843 silently returns if reinit is in progress. The `play()` from `_autoPlay` (line 131) may no-op if `initSongs` is still running. |
| `AudioHandlerProvider` cold-start | Assuming `audioHandler` always returns the real handler | Throwaway handler returned between `runApp()` and `initialize()` completion. No AudioService integration on throwaway. Don't defer `play()` past the swap. |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| N stacked `currentIndexStream` listeners after N book opens | N Hive writes per track change, app slows down over session | Track `_indexChangeSub` in field, cancel at top of `initSongs` | 10+ book opens in a session |
| N stacked `processingStateStream` debug listeners | N log lines per state transition, log file grows rapidly | Delete orphan at line 611, log inside functional listener only | 20+ book opens, verbose logging enabled |
| Polling `processingState` with 50ms delay | 50ms latency floor per check, CPU busy-wait | Use `processingStateStream.firstWhere(...)` with timeout instead | Always — but acceptable for <5s bounded waits |
| `setAudioSources` with `preload: true` for unknown-duration sources | Network probe blocks `initSongs` for duration of probe | This is expected for Sound-Books; use bounded timeout and handle error state | Slow Sound-Books server, >10s probe time |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| (Not applicable — this is a play-init race fix, no security surface) | — | — |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Fix adds 10s await-for-ready with no timeout feedback | User taps Sound-Books book, sees loading screen for 10s, no progress indicator | PROJECT.md defers loading feedback. But if the fix adds >3s latency, a simple "Loading…" text is better than silence. Keep within minimal scope if possible. |
| 30s auto-skip fires on slow network | User's book skips from track 1 to track 2 without user action | Remove or increase threshold; add gen guard so stale listeners don't skip |
| `seek()` no-op during loading causes resume at wrong position | User resumes at 30:00 but hears 0:00 of track 1 | Verify seek took effect; if state is `loading`, wait for non-loading before seeking |

## "Looks Done But Isn't" Checklist

- [ ] **Play-init fix:** Fix is merged, Sound-Books auto-plays on fast network — but verify on SLOW network (>5s probe time). Does `play()` still fire after `ready`? Does the 30s skip fire spuriously?
- [ ] **Listener cleanup:** Old `Future.delayed(60s)` replaced with tracked field — but verify the orphan at line 611 is also deleted. Run `flutter run` with verbose logging, open 5 books, check log for N× `processingState=` lines per transition.
- [ ] **Gen guard in finally:** `finally` guarded with `if (myGen == _initGen)` — but verify with a test: call `initSongs` twice rapidly, assert `_isReinitializing` is correct throughout.
- [ ] **Cross-source regression:** LibriVox/YouTube auto-play still works — but verify on REAL device, not just tests. Measure tap-to-audio latency before/after.
- [ ] **`FakePlaybackEngine` extended:** Fake simulates loading→ready — but verify the test actually exercises the async path (use `await tester.pumpAndSettle()` or `Future.delayed` to let the transition fire).
- [ ] **`_listenForCurrentSongIndexChanges` tracked:** Subscription in field, cancelled at top of `initSongs` — but verify only ONE listener fires per track change (add a counter in the test).
- [ ] **`play()` not awaited:** `_player.play()` is fire-and-forget in `initSongs` — but verify no `await` was accidentally added. `initSongs` should return within seconds, not block until track finishes.
- [ ] **Cold-start interaction:** Throwaway handler not worsened — but verify by cold-starting the app and immediately opening a Sound-Books book. Does the media notification appear?

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Fix addressed wrong race mechanism (Pitfall 1) | HIGH | Revert fix, add diagnostic logging, test on real device with Sound-Books URL, identify actual failure point, re-plan fix |
| `_isReinitializing` clobbered by finally (Pitfall 2) | LOW | Add gen guard to finally — 1-line fix. But may reveal existing position corruption that needs manual recovery. |
| Orphaned subscriptions from 60s delayed cancel (Pitfall 3) | MEDIUM | Replace with tracked field, cancel at top of `initSongs` and in `dispose`. Existing orphans clear on app restart. |
| Orphan listener at line 611 (Pitfall 4) | LOW | Delete 3 lines. No recovery needed — orphans clear on restart. |
| `_listenForCurrentSongIndexChanges` leak (Pitfall 5) | MEDIUM | Track in field, cancel at top of `initSongs`. Existing stacked listeners clear on restart. |
| FakePlaybackEngine can't test the fix (Pitfall 6) | MEDIUM | Extend fake with loading→ready simulation, write new test, THEN fix `initSongs`. This is a precursor step. |
| `seek()` no-op during loading (Pitfall 7) | LOW | Ensure operation ordering (setAudioSources before seek). Add post-seek verification log. |
| Await-for-ready deadlock on error (Pitfall 8) | MEDIUM | Add error-state check + bounded timeout. If already shipped, users experience hangs on dead URLs. |
| Cross-source latency regression (Pitfall 9) | LOW | Short-circuit wait on `ready` check. Measure before/after. |
| Cold-start play lost on throwaway (Pitfall 10) | HIGH | Can't recover without fixing AudioHandlerProvider (out of scope). User must restart app. Document as known limitation. |
| 30s auto-skip fires spuriously (Pitfall 11) | LOW | Add gen guard inside listener, increase/remove threshold. |
| `play()` awaited, initSongs hangs (Pitfall 12) | HIGH | Remove `await` before `_player.play()`. If shipped, app hangs on every book open. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Pitfall 1: Wrong race mechanism | Precursor: diagnostic logging + device test | Log confirms actual failure point before fix is written |
| Pitfall 2: `_isReinitializing` clobbered by finally | Implementation phase (precondition) | Test: rapid double `initSongs`, assert `_isReinitializing` correct |
| Pitfall 3: 60s delayed cancel orphans | Implementation phase | Test: open 3 books rapidly, assert 1 active subscription, not 3 |
| Pitfall 4: Orphan listener at line 611 | Implementation phase | Code review: line 611-613 deleted. Log: 1 log line per transition, not N |
| Pitfall 5: `_listenForCurrentSongIndexChanges` leak | Implementation phase | Test: open 3 books, skip track, assert 1 Hive write, not 3 |
| Pitfall 6: FakePlaybackEngine can't test fix | **Precursor phase** (before implementation) | Test: `initSongs` with fake in `loading` state, assert `play()` called after `ready` emitted |
| Pitfall 7: `seek()` no-op during loading | Implementation phase | Log: after `seek`, verify `_player.currentIndex` and `_player.position` match expected |
| Pitfall 8: Await-for-ready deadlock | Implementation phase | Test: fake enters `error` state, assert `initSongs` returns within timeout, not hang |
| Pitfall 9: Cross-source latency regression | Implementation phase | Device test: measure tap-to-audio for LibriVox before/after, assert <100ms increase |
| Pitfall 10: Cold-start play lost | Implementation phase (document, don't fix) | Device test: cold start + immediate Sound-Books open, check media notification appears |
| Pitfall 11: 30s auto-skip spurious | Implementation phase | Test: fake stays in `buffering` for 35s, assert no `seekToNext` (or gen-guarded skip) |
| Pitfall 12: `play()` awaited | Implementation phase (code review) | Code review: no `await` before `_player.play()` in `initSongs`. Test: `initSongs` returns <5s |

## Sources

- Fork source code (read directly from pub-cache): `~/.pub-cache/git/just_audio-a6f8db8ded43bdff0e39766fbbdbab8f22cadc2c/just_audio/lib/just_audio.dart` — `play()` at line 1090, `seek()` at line 1346, `setAudioSources` at line 885, `_load` at line 995, `processingStateStream` at line 487, `_processingStateSubject` at line 136. **Confidence: HIGH** (direct source code reading)
- just_audio official README (fetched from raw.githubusercontent.com/ryanheise/just_audio/master/just_audio/README.md) — state model section confirms `playing` and `processingState` are orthogonal; "even when playing == true, no sound will actually be audible unless processingState == ready"; "play() sets playing state immediately, audio begins when buffers filled." **Confidence: HIGH** (official documentation, matches fork source)
- Fork git log: commits `bf26a62` ("Fix bug on simultaneous loads"), `4fb8dfe` ("Fix simultaneous load bug on iOS/macOS"), `a6f8db8` ("added stereo balance for android" — fork HEAD). **Confidence: HIGH** (git log read directly)
- FlowBook codebase: `lib/resources/services/my_audio_handler.dart` (1054 lines), `lib/resources/services/audio_handler_provider.dart` (21 lines), `test/playback_trust_test.dart` (520 lines), `lib/screens/audiobook_details/audiobook_details.dart` (_autoPlay at line 94, call at line 397). **Confidence: HIGH** (direct source reading)
- `.planning/codebase/CONCERNS.md` — cold-start race, fire-and-forget cancel, state machine fragility, 22 silent catch blocks. **Confidence: HIGH** (project audit document)
- GitHub issue #263 (just_audio) — historical `PlatformException` on second `setAudioSource`, confirms `setAudioSource` has had race conditions with platform player lifecycle. **Confidence: MEDIUM** (historical, may not apply to fork)

---
*Pitfalls research for: just_audio play-init race fixing in FlowBook (forked just_audio, shared multi-source initSongs)*
*Researched: 2026-07-14*
