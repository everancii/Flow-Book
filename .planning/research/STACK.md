# Stack Research

**Domain:** Flutter audiobook player — just_audio / audio_service playback-init race fix
**Researched:** 2026-07-14
**Confidence:** HIGH (API facts verified against official source code; root-cause inference MEDIUM)

> **Scope note:** This is a *stack-level approach* research for a single bug fix on an existing shipped stack (Flow Book v1.2.0). The tech choices are already made — `just_audio` (forked), `audio_service`, `rxdart` are all in `pubspec.yaml` and stay. This document prescribes **which existing APIs to use, which to stop using, and the canonical play-init sequence** the fix should adopt. It does NOT recommend new dependencies.

## Recommended Stack (APIs to use for the fix)

### Core APIs

| API | Package / Version | Purpose | Why Recommended |
|-----|--------------------|---------|-----------------|
| `AudioPlayer.setAudioSources(sources, preload: true, initialIndex, initialPosition)` | `just_audio` 0.10.5 (fork `sagarchaulagai/just_audio.git` @ `a6f8db8`) | Load the playlist and block until `processingState` leaves `loading` | Already used at `my_audio_handler.dart:540`. Its Future resolves once `processingState != loading` (verified in `_load()` source: `await processingStateStream.firstWhere((state) => state != ProcessingState.loading)`). For sources with unknown duration (Sound-Books MP3, `length: 0`) it resolves with `duration: null` while state is still `buffering`; for sources with known duration it resolves at `ready`. **Keep using it; keep `preload: true` for auto-play.** |
| `AudioPlayer.processingStateStream.firstWhere((s) => s == ProcessingState.ready)` | `just_audio` 0.10.5 (fork) | Block until the decoder is actually ready to play, before requesting play | **THE key API for the fix.** `processingStateStream` is backed by `_processingStateSubject = BehaviorSubject<ProcessingState>.seeded(ProcessingState.idle)` (rxdart), so it **replays the current state to every new subscriber**. This means `firstWhere(ready)` completes *immediately* if the player is already `ready` (LibriVox/YouTube/knigavuhe/4read — no extra latency) and *waits for the transition* if the player is still `buffering` (Sound-Books). There is no risk of "missing" a ready transition that already happened. **Use this instead of the current 50ms polling loop (`_waitForProcessingReady`) and instead of the post-play `processingStateStream.listen` re-fire listener.** |
| `.timeout(Duration(seconds: 10))` on the `firstWhere` future | `dart:async` | Prevent indefinite hang if the source never reaches ready (network stall, dead URL) | `firstWhere(ready)` will hang forever if the source errors or stalls in buffering. Wrap it in `.timeout(...)` and on `TimeoutException` log + fall through (the existing 30s buffering-skip logic can remain as a backstop). **Required for robustness.** |
| `AudioPlayer.play()` | `just_audio` 0.10.5 (fork) | Set `playing = true` and send the play request to the native decoder | Call this **once, after** the ready-await guard. Per source: `if (playing) return;` (idempotent no-op), then sets `playing = true` synchronously, sends `platform.play(PlayRequest())`. The native side (ExoPlayer) starts sound when `processingState == ready`. `play()`'s Future completes on playback *end* (complete/pause/stop), **not** on playback *start* — so awaiting it does **not** wait for ready and is not the right gate. **Call fire-and-forget; do NOT rely on awaiting it for readiness.** |
| `ProcessingState` enum (`idle` / `loading` / `buffering` / `ready` / `completed`) | `just_audio` 0.10.5 (fork) | Gate play on the correct state | `ready` = "enough audio buffered and is able to play" (official enum doc). `playing` and `processingState` are orthogonal: sound is audible only when `playing == true && processingState == ready`. The fix must ensure the play request lands when (or after) `ready` is reached. |
| `BaseAudioHandler.play()` override | `audio_service` 0.18.18 | System-media callback entry point | Already overridden at `my_audio_handler.dart:877`. `BaseAudioHandler` does **not** queue or drop play requests and does **not** mediate ready state — the app's override owns all play logic (audio_service README: `Future<void> play() => _player.play();`). The override currently calls `_restoreQueueFromBoxIfEmpty()` then `await _player.play()`. **Keep this shape; the fix lives in `initSongs`, not in `play()`.** |

### Supporting APIs (already in the stack, use correctly)

| API | Package | Purpose | When to Use |
|-----|---------|---------|-------------|
| `AudioPlayer.processingStateStream` (as a `Stream`) | `just_audio` | Reactive ready/buffering/completed handling | Use with `firstWhere` for the one-shot ready-await. **Do NOT** use it as a long-lived "re-fire play() on ready" listener — that listener is redundant because `play()` is idempotent (`if (playing) return;`) and the native side already has the play request. |
| `AudioPlayer.playerStateStream` | `just_audio` | Combined `PlayerState(playing, processingState)` for UI | For UI widgets (loading spinner, play/pause button). Not needed for the play-init logic itself — `processingStateStream` is the sharper tool. |
| `BehaviorSubject` replay semantics | `rxdart` 0.28.0 | Guarantees `firstWhere` on `processingStateStream` never misses a transition | All just_audio `*Stream` getters are `BehaviorSubject.stream.distinct()`. This is what makes the `firstWhere(ready)` pattern safe. No explicit `rxdart` import needed in the fix — the guarantee is internal to just_audio. |
| `Stream.firstWhere` + `.timeout` | `dart:async` | Idiomatic one-shot stream wait with a deadline | The Dart-idiomatic replacement for the current `while + Future.delayed(50ms)` polling in `_waitForProcessingReady`. |

### Development / Verification Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `test/playback_trust_test.dart` (520 lines, `FakePlaybackEngine`) | Regression gate | Any change to `initSongs` play sequence must keep this passing. The `FakePlaybackEngine` must be able to simulate the `buffering → ready` transition so the fix's `firstWhere(ready)` is testable; if the fake jumps straight to `ready`, add a controllable delay/transition to cover the Sound-Books path. |
| `git diff` of the fork | Confirm fork-vs-upstream parity | Already done in this research (see *Fork Diff* below). The fork's `play()`/`setAudioSources()`/`_load()`/`ProcessingState` paths are identical to upstream `0.10.6`; only `setBalance` is added. No further fork investigation needed for this fix. |

## Recommended Canonical Play-Init Sequence

This is the concrete sequence `MyAudioHandler.initSongs` should adopt (replacing lines `540–613` of `my_audio_handler.dart`). It is fork-agnostic and native-quirk-agnostic: it guarantees the play request lands only when the decoder will honor it.

```dart
// 1. Load. setAudioSources(preload:true) resolves when processingState
//    LEAVES loading. For Sound-Books (length:0, no duration metadata) the
//    duration probe is still in flight, so state is `buffering` here — NOT
//    ready. For every other source, state is already `ready`.
await _player.setAudioSources(
  _audioSources!,
  initialIndex: sources.isEmpty ? 0 : safeIndex,
  initialPosition: currentIsYT
      ? Duration.zero
      : Duration(milliseconds: positionInMilliseconds),
  preload: playImmediately,
);
if (myGen != _initGen) return;

// 2. Seek to the resume position (valid in any processing state; queues).
await _player.seek(
  Duration(milliseconds: positionInMilliseconds),
  index: safeIndex,
);

// 3. If auto-playing, wait for `ready` BEFORE requesting play.
//    processingStateStream is a BehaviorSubject (replays current state):
//    - already ready (LibriVox/etc.) → firstWhere completes instantly, zero added latency.
//    - still buffering (Sound-Books)  → waits for the ready transition.
if (playImmediately) {
  if (_player.processingState != ProcessingState.ready) {
    try {
      await _player.processingStateStream
          .firstWhere((s) => s == ProcessingState.ready)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      AppLogger.warning(
        'initSongs: timed out waiting for ready, '
        'state=${_player.processingState}');
      // Fall through; the 30s buffering-skip backstop (kept) handles stalls.
    }
  }
  if (myGen != _initGen) return;

  // 4. Request play. play() sets playing=true and sends the platform play
  //    request; native starts sound immediately because state is `ready`.
  //    Do NOT await this for readiness — its Future resolves on playback END.
  _player.play();
}
```

**What this replaces in the current code (`my_audio_handler.dart:562–613`):**
- **DELETE** the fire-and-forget `_player.play()` at line `565` that fires while state may be `buffering`.
- **DELETE** the `processingStateStream.listen((state) { if (state == ready) _player.play(); ... })` block (lines `569–605`) — redundant: `play()` is a no-op when `playing` is already true, and the native side already holds the play request.
- **DELETE** the `Future.delayed(60s, () => sub.cancel())` (line `608`) — the listener it cancels is gone.
- **DELETE** the second leaked `processingStateStream.listen` at lines `611–613` (logging-only, never cancelled — a subscription leak).
- **KEEP** the 30s buffering-skip backstop logic, but relocate it to a single long-lived listener attached once in the constructor (not re-attached per `initSongs` call), so it survives across tracks without leaking subscriptions.
- The `_waitForProcessingReady` polling helper (lines `650–657`) can be replaced by the `firstWhere(ready).timeout(...)` pattern; it is currently only called for the YouTube-with-position branch (line `553`) and the new sequence subsumes that case too (the `firstWhere` covers YouTube as well, since YouTube also goes through `buffering → ready`).

## Fork Diff (sagarchaulagai/just_audio.git @ a6f8db8 vs upstream)

**Verdict: the fork does NOT change the APIs relevant to this fix.** Confidence: HIGH (fetched the fork's `just_audio/lib/just_audio.dart` at the pinned ref and line-by-line compared the play/load/ProcessingState paths against upstream `ryanheise/just_audio` branch `minor` / published `0.10.6`).

| Path | Fork vs upstream | Impact on fix |
|------|------------------|----------------|
| `play()` | **Identical** — same `if (playing) return;` guard, same `playing = true` broadcast, same `_sendPlayRequest` / `_setPlatformActive(true)` logic | None — upstream contract holds |
| `setAudioSources()` / `load()` / `_load()` | **Identical** — same `firstWhere((state) => state != ProcessingState.loading)` gate before resolving | None — `setAudioSources` resolves at the same point (state left `loading`) |
| `_processingStateSubject` / `processingStateStream` | **Identical** — `BehaviorSubject<ProcessingState>.seeded(ProcessingState.idle)` + `.stream.distinct()` | None — replay semantics hold, `firstWhere(ready)` is safe |
| `stop()` / `pause()` | **Identical** | None |
| `setBalance()` / `balance` / `balanceStream` | **Fork-only addition** — Android L/R channel balance via `MethodChannel('com.ryanheise.just_audio.methods.<id>')`, backed by `_balanceSubject = BehaviorSubject.seeded(0.0)` | None — orthogonal feature, does not touch play/load/ProcessingState |

**Implication:** The PROJECT.md hypothesis that "the fork might have changed `play()`/`setAudioSources`/`ProcessingState` semantics" is **disproven** for these APIs. The upstream just_audio contract holds on the fork. Therefore the bug is **not** caused by a fork divergence in play-init semantics.

## Root-Cause Inference (why the bug happens despite the contract being intact)

Confidence: **MEDIUM** (inferred from source + symptom, not directly observed in a debugger).

Per the verified upstream/fork source, `play()` called during `buffering` *should* work: it sets `playing = true` and sends `platform.play(PlayRequest())`, and ExoPlayer is documented to start when it reaches `ready`. Yet Sound-Books auto-play silently no-ops in practice. The most likely remaining causes, given the Dart source is correct:

1. **Native (ExoPlayer) quirk with unknown-duration sources.** When an MP3 has no duration metadata and ExoPlayer is still probing it, the `play` request sent during `buffering` may be dropped or not retained by the native side until the probe completes and state settles. This would explain why *only* Sound-Books (`length: 0`) fails while every source with known durations works. This is not visible in the Dart source — it's in the Android `just_audio` platform implementation / ExoPlayer behavior.
2. **`play()`'s internal `await audioSession.setActive(true)` window.** Between `play()` setting `playing = true` and sending the platform play request, there is an `await`. An intervening state change (e.g. a re-entrant `stop()` or an audio-session interruption) could flip `playing` back to `false`, causing the `if (!playing) return;` guard to abort the play request. The current code's fire-and-forget `_player.play()` at line `565` runs concurrently with the rest of `initSongs` (seek, listener attach, `_waitForStartToSettle`), increasing the surface for such an intervention.

**The recommended fix (await `ready` *before* `play()`) neutralizes both causes:** by the time `play()` runs, `processingState` is `ready` (probe done, buffers filled), so the native side honors the play request immediately, and the `audioSession.setActive` window is far less likely to race with anything because no further load/seek is in flight.

## What NOT to Do

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **Fire `_player.play()` before the player has reached `ready`** (current line `565`) | For sources with unknown duration, `setAudioSources` resolves at `buffering`, so `play()` lands while the native decoder is still probing. The native side may drop the request; the Dart-side `processingStateStream.listen` re-fire can't reliably rescue it (and is a no-op anyway once `playing` is true). | Await `processingStateStream.firstWhere(ready)` (with timeout) *before* calling `play()`. |
| **Re-fire `play()` from a `processingStateStream.listen((s) { if (s == ready) play(); })` listener** (current lines `569–605`) | `play()` has `if (playing) return;` — once `playing` is `true` the re-fire is a no-op. If `playing` got flipped back to `false` by an interruption, re-firing may double-fire or race. The listener is a workaround for a problem that disappears once you await `ready` first. | Remove the listener entirely. The single `play()` after the ready-await is sufficient. |
| **Attach a new `processingStateStream.listen` per `initSongs` call and never cancel it** (current lines `611–613` leak; `569–605` only cancels after 60s) | Every `initSongs` call leaks a stream subscription (and for the re-fire listener, holds a reference for 60s). Over a listening session this accumulates leaked subscriptions and callbacks. | Attach any long-lived listeners (buffering-skip backstop) **once** in the constructor; use one-shot `firstWhere` for the ready wait. |
| **Poll `processingState` in a `while + Future.delayed(50ms)` loop** (`_waitForProcessingReady`, lines `650–657`) | Works but is wasteful and less precise than the stream. 50ms granularity means up to 50ms of unnecessary delay after `ready`. | `processingStateStream.firstWhere((s) => s == ProcessingState.ready).timeout(...)` — reacts the instant `ready` is emitted. |
| **Await `_player.play()` to gate readiness** | `play()`'s Future completes on playback *completion/pause/stop*, not on playback *start*. Awaiting it blocks until the track finishes (or never returns if playback is interrupted) — it is NOT a readiness signal. | Use `processingStateStream.firstWhere(ready)` for readiness; call `play()` fire-and-forget. |
| **Add a new dependency to "fix" the race** (e.g. a wrapper package, a lock library) | The existing stack (`just_audio` + `audio_service` + `rxdart` + `dart:async`) has the exact APIs needed. PROJECT.md constraint: no new dependencies. | Use `processingStateStream.firstWhere` + `.timeout` from `dart:async`. |
| **Move the fix into the details screen (`_autoPlay`) or into `MyAudioHandler.play()`** | The race is in the shared `initSongs` play-init sequence. `_autoPlay` already calls `initSongs` then `play()` correctly; the drop happens inside `initSongs`. Moving it elsewhere duplicates logic and leaves the shared path broken for other callers. | Fix lives in `MyAudioHandler.initSongs` (the shared play-init), per the PROJECT.md key decision. |
| **Assume the fork changed play/load semantics** | Disproven: fork source is identical to upstream for all relevant APIs (only `setBalance` is added). | Treat the fork as upstream-equivalent for this fix. |

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| `processingStateStream.firstWhere(ready).timeout(10s)` before `play()` | Trust upstream contract: just `setAudioSources` then `play()` (no ready-await, no re-fire listener) | Only if you can confirm via on-device testing that ExoPlayer reliably honors a `play` request issued during `buffering` for unknown-duration MP3s. The user has already confirmed it does NOT for Sound-Books, so this alternative is rejected for this fix. (It would be the minimal-diff option on a stack where the native quirk didn't manifest.) |
| `processingStateStream.firstWhere(ready)` (one-shot) | `playerStateStream.firstWhere((s) => s.processingState == ready)` | Equivalent — `playerStateStream` is also a `BehaviorSubject` and carries both `playing` and `processingState`. Use it if you also want to assert `playing == false` at the gate. `processingStateStream` is simpler and sufficient. |
| Await `ready` before `play()` (recommended) | Listen on `processingStateStream` and re-fire `play()` on `ready` (current approach) | Never, for this fix — re-firing is a no-op once `playing` is true and is the pattern that produced the current race. |
| `.timeout(10s)` on the ready-wait | No timeout (wait forever for `ready`) | Never in production — a dead URL or a network stall would hang `initSongs` indefinitely and block all subsequent playback. The timeout is mandatory. |
| `firstWhere` on the stream | Keep the `while + Future.delayed(50ms)` poll (`_waitForProcessingReady`) | Only if `processingStateStream` were a non-replaying broadcast stream where `firstWhere` could miss the transition — but it is a `BehaviorSubject`, so `firstWhere` is strictly better (reacts instantly, no polling lag). |

## Stack Patterns by Variant

**If the source has known duration up front (LibriVox/Archive.org, YouTube, 4read, knigavuhe, local/downloaded):**
- After `await setAudioSources(preload:true)`, `processingState` is already `ready`.
- The `if (_player.processingState != ProcessingState.ready)` guard is **false**, so `firstWhere(ready)` is skipped — **zero added latency**.
- `play()` fires immediately on a ready decoder. Behavior unchanged from today's working sources.

**If the source has unknown duration (Sound-Books MP3 with `length: 0`):**
- After `await setAudioSources(preload:true)`, `processingState` is `buffering` (duration probe still in flight).
- The guard is **true**, so `await processingStateStream.firstWhere(ready).timeout(10s)` waits for the probe + buffer-fill to complete.
- Once `ready`, `play()` fires on a ready decoder and audio starts. **This is the fix.**
- If `ready` never arrives within 10s (dead URL / stall), the timeout logs a warning and falls through; the retained 30s buffering-skip backstop eventually skips the track.

**If the caller passes `playImmediately: false` (e.g. cold-restore via `_restoreQueueFromBoxIfEmpty`):**
- The `if (playImmediately)` block is skipped entirely — no ready-await, no `play()`. The queue is loaded but not started, matching today's restore-without-autoplay behavior.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|------------------|-------|
| `just_audio` fork @ `a6f8db8` (pinned, `pubspec.yaml:35–39`) | `audio_service` `0.18.18` | Already integrated via `just_audio_background` `0.0.1-beta.17`. The fix uses only `AudioPlayer` APIs that exist in both the fork and upstream — no version bump needed. |
| `just_audio` fork @ `a6f8db8` | `rxdart` `0.28.0` | `BehaviorSubject` replay semantics are the foundation of the `firstWhere(ready)` pattern. Fork uses the same `rxdart` `BehaviorSubject.seeded` as upstream. Compatible. |
| `just_audio` fork @ `a6f8db8` vs upstream `0.10.5`/`0.10.6` | Diff verified | Fork is upstream-equivalent for `play`/`setAudioSources`/`load`/`_load`/`ProcessingState`/`processingStateStream`; only `setBalance` is added. Safe to apply upstream-documented patterns. |
| `audio_service` `0.18.18` (pinned) vs `0.18.19` (latest) | Patch bump | `0.18.19` is the current pub.dev release. No `play()`/`BaseAudioHandler` contract change between `.18` and `.19`. **Do not bump** — out of scope for this fix and the constraint says no new deps. |

## Installation

No installation changes. The fix uses only APIs already available in the pinned dependencies:

```yaml
# pubspec.yaml — UNCHANGED. No new packages, no version bumps.
just_audio:
  git:
    url: https://github.com/sagarchaulagai/just_audio.git
    path: just_audio
    ref: a6f8db8ded43bdff0e39766fbbdbab8f22cadc2c
audio_service: ^0.18.18
rxdart: ^0.28.0   # transitive via just_audio; BehaviorSubject is internal
```

The only `import` the fix may newly reference is `dart:async` (for `TimeoutException`) — already imported at `my_audio_handler.dart:2`.

## Sources

- **Official just_audio API docs** — `pub.dev/documentation/just_audio/latest/just_audio/AudioPlayer-class.html`, `/play.html`, `/setAudioSource.html`, `/ProcessingState.html`. Verified: `play()` contract ("as soon as an audio source is loaded and ready to play"; "Future completes when playback completes or is paused or stopped"; "If the player is already playing, completes immediately"), `ProcessingState` enum definitions, `setAudioSources` returns `Future<Duration?>`. Confidence: **HIGH**.
- **Official just_audio source code** — `raw.githubusercontent.com/ryanheise/just_audio/minor/just_audio/lib/just_audio.dart`. Verified: `play()` implementation (`if (playing) return;` → `playing = true` → `_sendPlayRequest`/`_setPlatformActive`), `_load()` (`await processingStateStream.firstWhere((state) => state != ProcessingState.loading)`), `_processingStateSubject = BehaviorSubject<ProcessingState>.seeded(ProcessingState.idle)`, `processingStateStream` getter (`_processingStateSubject.stream.distinct()`), `stop()`/`pause()` implementations. Confidence: **HIGH**.
- **Fork source code** — `raw.githubusercontent.com/sagarchaulagai/just_audio/a6f8db8.../just_audio/lib/just_audio.dart`. Verified: `play()`/`setAudioSources()`/`load()`/`_load()`/`stop()`/`pause()`/`_processingStateSubject` identical to upstream; only `setBalance`/`_balanceSubject` added. Confidence: **HIGH**.
- **Official just_audio example** — `raw.githubusercontent.com/ryanheise/just_audio/minor/just_audio/example/lib/main.dart`. Verified: canonical pattern is `await _player.setAudioSource(...)` then `player.play` on button press; no ready-await, no re-fire listener. Confidence: **HIGH**.
- **Official just_audio README** — `pub.dev/packages/just_audio`. Verified: state model ("even when `playing == true`, no sound will actually be audible unless `processingState == ready`"; "play... immediately reflect the 'playing' state... once the buffers are finally filled (`processingState == ready`), audio playback will begin"); `setAudioSources` migration note. Confidence: **HIGH**.
- **Official audio_service README** — `pub.dev/packages/audio_service`. Verified: `BaseAudioHandler` canonical handler `Future<void> play() => _player.play();` (pure delegation, no queueing/dropping, no ready mediation); `PlaybackState` broadcasting contract. Confidence: **HIGH**.
- **Root-cause inference (ExoPlayer/Android native quirk)** — inferred from the gap between the verified Dart contract and the user-confirmed symptom (Sound-Books only fails; only source with `length: 0`). Not directly observed in a debugger. Confidence: **MEDIUM**.

---
*Stack research for: Flutter audiobook player — just_audio playback-init race fix*
*Researched: 2026-07-14*
