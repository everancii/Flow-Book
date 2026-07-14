# Phase 2: Subscription Lifecycle + State-Guard Cleanup - Context

**Gathered:** 2026-07-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Pure refactors inside `MyAudioHandler.initSongs` that eliminate subscription leaks and the `_isReinitializing`-clobber race. **Zero user-visible behavior change.** This is a precondition so the Phase 3 `await ProcessingState.ready` doesn't widen existing races.

Three requirements (PLAY-07, PLAY-08, PLAY-09):
- Guard the `finally` block with gen-check so a stale init can't clobber a newer init's `_isReinitializing` flag
- Replace the fire-and-forget `Future.delayed(60s, () => sub.cancel())` with a tracked `StreamSubscription` cancelled at three sites
- Remove the orphan `processingStateStream.listen` (log-only, never cancelled)

**Not in scope:** The ready-before-play await (Phase 3), bounded timeout (Phase 3), call-site consistency (Phase 4), cross-source smoke (Phase 4).

</domain>

<decisions>
## Implementation Decisions

### Gen-Guard on Finally (PLAY-07)
- **D-01:** Guard the finally block with: `finally { if (myGen == _initGen) { _isReinitializing = false; } }`. Only the active generation clears the flag. A stale init (superseded by a newer `++_initGen`) skips the clear, so it cannot clobber the newer init's flag.
- **D-02:** No change to the existing early-return points (lines 526, 566, 656). They already guard with `if (myGen != _initGen) return;`. Combined with the guarded finally: stale init returns early → finally sees `myGen != _initGen` → skips the clear. The newer init's finally will clear when IT completes. Correct as-is.

### Tracked Subscription Design (PLAY-08)
- **D-03:** Introduce a single field `StreamSubscription? _initSettleSub;` (alongside the existing `_coverSub`, `_eventSub` etc. at lines 240–254). At line 603, replace `final sub = _player.processingStateStream.listen(...)` with `_initSettleSub?.cancel(); _initSettleSub = _player.processingStateStream.listen(...)`.
- **D-04:** Delete the fire-and-forget `Future.delayed(const Duration(seconds: 60), () => sub.cancel())` at line 642 entirely. The tracked field replaces it.
- **D-05:** Cancel `_initSettleSub` at three sites:
  1. **Top of next `initSongs`** — immediately after `final myGen = ++_initGen;` (line 424). Prevents stacking on re-entry: the previous init's listener dies before the new one starts.
  2. **In `stop()`** (line 936) — add `_initSettleSub?.cancel();` alongside the existing `_positionUpdateTimer?.cancel()` and `_coverSub?.cancel()`. Full teardown when playback stops.
  3. **In the guarded finally block** — when `myGen == _initGen`, cancel `_initSettleSub` before clearing `_isReinitializing`. Handles the normal-completion path inside initSongs itself.

### Buffering-Recovery + Orphan Listener Fate (PLAY-09)
- **D-06:** Fold ALL THREE existing behaviors from the listener callback (lines 603–639) into `_initSettleSub` as-is:
  - Ready re-trigger (lines 606–609): if `state == ProcessingState.ready`, call `_player.play()` — the "ensure play after buffering" recovery
  - Idle recovery (lines 613–620): if player goes idle while `playing`, retry play after 500ms
  - 30s buffering-skip (lines 624–637): if stuck in buffering >30s, skip to next track
  - These behaviors are preserved exactly — only the subscription lifecycle changes (tracked vs fire-and-forget).
- **D-07:** Remove the orphan listener at line 645 entirely: `_player.processingStateStream.listen((state) { AppLogger.debug('initSongs: player processingState=$state'); })`. It logs only, and line 604 (`AppLogger.debug('initSongs: processingState=$state')` inside the tracked listener) already logs every state change. The orphan is redundant and leaks a subscription per `initSongs` call.
- **D-08:** Keep ALL `[DIAG]` diagnostic checkpoints from Phase 1 (lines 542–598) in place. Still valuable for on-device debugging through Phase 2/3. Phase 3 may remove them after the fix is verified on-device.

### Test Strategy for Refactors
- **D-09:** Add focused refactor tests NOW in `test/playback_trust_test.dart` inside the existing `group('MyAudioHandler with fake playback engine', ...)` block (after the last existing test, before the group closing brace). Tests cover:
  1. **Gen-discard clobber protection** — call `initSongs` twice rapidly (A→B), verify B's `_isReinitializing` isn't clobbered when A's finally runs (inspect via `handler.isReinitializing` getter at line 220)
  2. **Tracked-sub cancellation on re-entry** — call `initSongs` twice, verify only one active listener exists (FakePlaybackEngine can expose active listener count via `processingStates.hasListener`)
  3. **No orphan listeners** — after `initSongs` + `stop()`, verify zero active listeners on `processingStateStream`
- **D-10:** The 2 pre-existing failures in the `chapter switching metadata` group (lines 176–208) stay deferred. They are unrelated to subscription lifecycle — failing on clean baseline per `deferred-items.md`. Do NOT fix them in Phase 2.
- **D-11:** Reuse existing test helpers: `_sampleFiles()`, `_sampleAudiobook()`, `FakePlaybackEngine` (lines 295–499). Do not redefine. `configureAudioSession: false` is mandatory in all handler constructions.

### Claude's Discretion
- Exact test assertion mechanisms (e.g., whether to expose a new getter on `FakePlaybackEngine` for active-listener count, or use `processingStates.hasListener`) — pick whichever is cleanest.
- Whether to add a brief inline comment at the new `_initSettleSub` field declaration explaining the three cancel sites.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 1 Context (predecessor)
- `.planning/phases/01-diagnostic-verification-test-infrastructure/01-PATTERNS.md` — Pattern map for `initSongs` + `playback_trust_test.dart`. Contains the exact code conventions, gen-guard pattern, AppLogger.debug format, FakePlaybackEngine fields, and test construction shape. Phase 2 follows the same patterns.
- `.planning/phases/01-diagnostic-verification-test-infrastructure/deferred-items.md` — Documents the 2 pre-existing test failures in `chapter switching metadata` group. Phase 2 must NOT fix these — verified pre-existing via `git stash` on clean baseline.

### Requirements
- `.planning/REQUIREMENTS.md` §Play-Init Sequence — PLAY-07 (finally gen-guard), PLAY-08 (tracked sub), PLAY-09 (orphan removal). The exact requirement text the implementation must satisfy.

### Codebase Maps
- `.planning/codebase/CONCERNS.md` §`Future.delayed(60s, () => sub.cancel())` is fire-and-forget — Documents the exact bug PLAY-08 fixes. Also §`MyAudioHandler` 1054-line state machine — fragile-area note: "read `playback_trust_test.dart` to understand the invariants the tests enforce" before editing.

### Source Code (the files being modified)
- `lib/resources/services/my_audio_handler.dart` lines 214–215 (`_isReinitializing`, `_initGen` declarations), 240–254 (existing `StreamSubscription` fields — pattern to follow), 416–676 (`initSongs` method — the refactor target), 936–942 (`stop()` — add cancel here)
- `test/playback_trust_test.dart` lines 210–359 (`MyAudioHandler with fake playback engine` group — test insertion point), 418–499 (`FakePlaybackEngine` — fake to extend if needed for listener-count assertions)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Existing StreamSubscription fields** (lines 240–254): `_coverSub`, `_eventSub`, `_playerStateSub`, `_playingSub`, `_bufferedSub` — all follow the `StreamSubscription<T>? _name` pattern with cancellation in `stop()` (lines 319–323). `_initSettleSub` follows this exact convention.
- **Gen-guard pattern** (lines 526, 566, 656): `if (myGen != _initGen) return;` — already used at three early-return points. The finally guard reuses the same comparison.
- **FakePlaybackEngine** (test lines 418–499): `processingStates` is a broadcast `StreamController<ProcessingState>`. `processingStateStream` getter returns `processingStates.stream`. `hasListener` property can detect active subscriptions. `playCount` tracks `play()` calls.

### Established Patterns
- **Subscription lifecycle convention**: declare `StreamSubscription<T>?`, cancel in `stop()` and at re-entry points. All 5 existing subs follow this. `_initSettleSub` is the 6th, same pattern.
- **Gen-staleness guard**: `if (myGen != _initGen) return;` — the canonical way to discard stale init work. Used at 3 return points; now also in the finally block.
- **AppLogger.debug format**: `AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: <desc>, processingState=${_player.processingState}')` — Phase 1 diagnostic convention. Phase 2 preserves these logs unchanged.

### Integration Points
- **`initSongs` re-entry**: the top-of-method cancel (D-05.1) connects to the existing `_isReinitializing = true; final myGen = ++_initGen;` sequence at lines 423–424.
- **`stop()` teardown**: the cancel in stop() (D-05.2) connects to the existing `_positionUpdateTimer?.cancel(); _coverSub?.cancel();` at lines 937–939.
- **`finally` block**: the guarded cancel (D-05.3) connects to the new `if (myGen == _initGen)` guard on `_isReinitializing = false` at line 674.

</code_context>

<specifics>
## Specific Ideas

- The user emphasized **"no behavior change"** multiple times — this phase is invisible to users. All three listener behaviors (ready re-trigger, idle recovery, 30s buffering-skip) must work identically after the refactor. The only difference: the subscription is tracked and deterministically cancelled instead of fire-and-forget.
- The user wants refactor tests added NOW (not deferred to Phase 4) to prove the "no behavior change" claim immediately and catch regressions before Phase 3 builds on top.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. The 2 pre-existing test failures (`chapter switching metadata` group) were discussed but explicitly deferred per `deferred-items.md` — they predate Phase 1 and are unrelated to subscription lifecycle.

</deferred>

---

*Phase: 2-Subscription Lifecycle + State-Guard Cleanup*
*Context gathered: 2026-07-15*
