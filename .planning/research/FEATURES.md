# Feature Research

**Domain:** Audiobook player auto-play-on-open (single-source race fix, brownfield)
**Researched:** 2026-07-14
**Confidence:** HIGH for just_audio state model + codebase facts; MEDIUM for fix-surface mechanism; LOW for competitor UI behavior

## Scope Note

This is a **fix-scope feature landscape**, not greenfield product research. The "product" is already shipped (Flow Book v1.2.0+2020). The "features" here are **behaviors the fix must guarantee, must not break, or must deliberately not add** — organized per the downstream consumer's request. Source of truth: `.planning/PROJECT.md` Active/Out-of-Scope lists, `lib/screens/audiobook_details/audiobook_details.dart`, `lib/resources/services/my_audio_handler.dart`, `test/playback_trust_test.dart`.

## Feature Landscape

### Table Stakes (the fix counts as done only if these hold)

Behaviors users assume. Missing any = fix doesn't count as done.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Sound-Books book auto-plays on open — zero extra taps | User's stated bar: LibriVox/YouTube/knigavuhe/4read all do this; Sound-Books is the only outlier | MEDIUM | Entry point: `audiobook_details.dart:397` `_autoPlayTriggered` → `_autoPlay` → `initSongs` (playImmediately defaults true) → `_player.play()`. Race per PROJECT.md root cause. |
| Playback actually begins within reasonable time of opening | "Discover to playback in one gesture" is the app's Core Value (PROJECT.md:9); a 60s-silent-then-audio fix is not a fix | MEDIUM | Per just_audio state model (pub.dev, HIGH conf): `play()` during `loading` sets `playing=true`; audio auto-starts when `processingState` reaches `ready`. For Sound-Books (`length: 0`), `setAudioSources` must network-probe the MP3 to learn duration before `ready`. Reasonable = comparable to other sources' apparent start latency. |
| Resume case preserved — book in history auto-plays from saved position, not 0 | Resume is a validated existing feature (PROJECT.md:22); the fix must not regress it for Sound-Books | LOW | `_autoPlay` (audiobook_details.dart:107-119) already branches on `historyOfAudiobook.isAudiobookInHistory`. `initSongs` receives `idx` + `position` and seeks at my_audio_handler.dart:558. Edge: seeking on unknown-duration source. |
| Other 4 sources' auto-play unchanged | PROJECT.md Out-of-Scope: "confirmed working, not touching"; user reports only Sound-Books broken | LOW (verification) / HIGH (risk) | `initSongs` is shared code. Any change to the play sequence affects LibriVox/YouTube/knigavuhe/4read. Regression suite: `playback_trust_test.dart` (520 lines) + manual smoke per source. |
| Big play button (audiobook_details.dart:513) still works for Sound-Books after fix | Existing tap-to-play must not regress — it's the fallback when auto-play fails | LOW | The play button `onTap` calls `initSongs` (playImmediately defaults true) but does NOT call `play()` explicitly. It relies on `initSongs` self-playing. Fix must preserve this contract. |
| Chapter-list tap (audiobook_details.dart:606) still works for Sound-Books | Explicit per-chapter play is a validated existing feature | LOW | `_playChapter` calls `initSongs` then explicit `play()`. Fix must not break this path. |
| If the Sound-Books MP3 probe fails (404, network error), user sees a visible error — not silent no-op | "If the probe fails, user sees an error not a silent no-op" — explicit downstream requirement | MEDIUM | Per just_audio docs (HIGH conf): `setAudioSources` throws `PlayerException` on load failure. Current `initSongs` does NOT try/catch around `setAudioSources` (my_audio_handler.dart:540). `_autoPlay` catch (audiobook_details.dart:133) only `AppLogger.debug` — silent. `_playChapter` catch (line 84) shows SnackBar — visible. Fix must surface error consistently. |
| `playback_trust_test.dart` (520 lines) keeps passing | Encoded invariants: restore-without-play, skipToQueueItem-resumes, seek-persists | LOW (test shouldn't break) / MEDIUM (if fix touches initSongs play logic) | FakePlaybackEngine defaults `processingState = ProcessingState.ready` (test:384) so tests don't exercise the loading race. Fix likely safe for existing tests but new test must cover the loading→ready path with a fake that emits the transition. |

### Differentiators (competitive advantage but explicitly deferred per user)

Not required for this fix. Listed so they're not accidentally built.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Loading spinner / buffering % for non-YouTube sources | YouTube already has `isBufferingYouTube` + `bufferingProgress` (my_audio_handler.dart:257,263) showing a real % during probe; Sound-Books shows nothing during its probe | MEDIUM | **Explicitly deferred** (PROJECT.md Out-of-Scope: "Loading spinner / buffering feedback for non-YouTube sources — explicitly deferred ('just fix it')"). The `_durationSubtitle` shimmer (audiobook_details.dart:162-196) is the closest existing pattern but fires on chapter rows, not the play button. |
| Cross-source play-init hardening | Generalize the fix to all 5 sources, not just Sound-Books — single robust play-on-ready path | HIGH | **Explicitly deferred** (PROJECT.md Out-of-Scope: "Hardening the `initSongs` play race across all sources — explicitly deferred (minimal scope)"). The shared `initSongs` means the fix likely lands in shared code anyway, but the *verification* scope is Sound-Books only. |
| Skip details screen — straight-to-player navigation | Fewer taps to audio | LOW | **Explicitly out** (PROJECT.md: "user wants to keep opening the details screen; just wants it to auto-play"). |
| User-controlled auto-play toggle | AntennaPod has one (issue #7259 "playback starts immediately after connecting to Android Auto, even though I told it not to" — confirms a setting exists) | MEDIUM | Not requested. User wants auto-play ON, not a preference. |
| Predictive duration probe in details service | Pre-fetch Sound-Books MP3 duration during detail fetch so the source is `ready` by the time `_autoPlay` fires | MEDIUM | Would eliminate the race entirely but adds a network call to the details-service path. Out of scope per "minimal". |
| Stuck-buffering skip (30s → next track) generalized to non-YouTube | Current 30s skip (my_audio_handler.dart:590-604) is inside the play-on-ready listener; generalize as a recovery policy | MEDIUM | Adjacent to the fix but not required. |
| `useLazyPreparation: true` for large playlists | Mitigates just_audio issue #294 (1000+ children load >20s) | LOW | Flow Book uses `setAudioSources` (0.10.x API) with `preload: playImmediately`. Lazy preparation is a separate axis. Not relevant to the Sound-Books single-book race. |

### Anti-Features (deliberately NOT build per user's "just fix it" choice)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Loading-feedback UI for non-YouTube sources | Surface appeal: user sees progress during the Sound-Books probe | User explicitly said "just fix it" — no UI work; adds design + i18n + state surface for a fix that should be invisible | Make the probe fast enough or the play-on-ready robust enough that no UI is needed |
| Details-screen redesign | Tempting to "fix" the play button alignment while in there | Out of scope; user wants the details screen kept as-is; redesign risks regressing the 4 working sources | Touch only `MyAudioHandler.initSongs` play sequence, not the screen |
| Cross-source `initSongs` refactor | Clean-code appeal: fix the race for all sources once | PROJECT.md: minimal scope; refactor expands verification to all 5 sources + risks the 4 working ones | Fix the play-on-ready listener attachment; the same code path then serves all sources, but verification stays Sound-Books |
| New dependencies (alternative audio package, reactive helpers) | "Maybe a different player handles this better" | Stack is pinned (Flutter 3.44.1, forked `just_audio` `sagarchaulagai/just_audio@a6f8db8`); new deps = new risk surface | Use existing `processingStateStream` + `StreamSubscription` idioms |
| Auto-play user preference toggle | "Some users might not want auto-play" | Not requested; adds settings UI + persistence + test surface; user wants auto-play ON, full stop | Auto-play is the product; not a preference |
| Replace 60s `Future.delayed` listener-cancel with a proper subscription lifecycle | Adjacent leak fix; tempting while in the area | **This is a BUG (see Edge Case #5), not an anti-feature** — it must be fixed as part of the race fix because the 60s timer cancels listeners gen-agnostically and can cancel a later initSongs' listener | Gen-guard the listener cancellation or tie it to `_isReinitializing` |

## Feature Dependencies

```
[TS-1 Sound-Books auto-plays on open]
    ├──requires──> [TS-2 Playback begins within reasonable time]
    │                  └──requires──> [EC-5 60s listener-cancel bug fixed
    │                                    (else ready-re-fire listener dies prematurely)]
    ├──requires──> [TS-6 Probe failure shows visible error
    │                  └──requires──> [EC-3 setAudioSources try/catch
    │                                    (currently uncaught in initSongs)]]
    ├──requires──> [TS-3 Resume case preserved
    │                  └──requires──> [EC-4 Seek on unknown-duration source
    │                                    behaves for resume position]]
    ├──requires──> [EC-2 initSongs re-entry gen-discard
    │                  └──shares root with──> [EC-5 60s listener-cancel bug]]
    └──blocked-by──> [TS-4 Other sources unchanged
                       └──verified-by──> [TS-8 playback_trust_test.dart passes]]

[TS-5 Big play button still works] ──shares──> [initSongs self-play contract]
[TS-6 Chapter-list tap still works] ──shares──> [initSongs self-play contract]

[EC-1 Back-navigation during probe] ──conflicts──> [un guarded _weSlideController.show()
                                                     after dispose (audiobook_details.dart:132)]

[EC-7 Duplicate processingStateStream.listen at line 611] ──enhances──> [EC-5 leak fix]

[EC-8 _autoPlay double play() call] ──conflicts──> [single play-initiation point
                                                     (initSongs internal play vs line 131 external)]

[EC-9 _autoPlayTriggered flag] ──independent──> [acceptable for fix scope]

[EC-10 History-section tap entry point] ──shares──> [initSongs play sequence
                                                      (covered by same fix, must verify)]
```

### Dependency Notes

- **TS-1 requires EC-5:** The 60s `Future.delayed(() => sub.cancel())` at my_audio_handler.dart:608 is gen-agnostic and state-agnostic. If the Sound-Books probe takes >60s (slow network, large file), the ready-re-fire listener is already cancelled. If the user opens a second book within 60s, the first invocation's timer cancels the second invocation's listener. Fixing the race without fixing this timer is unstable.
- **TS-1 requires EC-2:** `_initGen` gen-guard (my_audio_handler.dart:424) already short-circuits stale invocations at lines 526, 549, 622. But the `processingStateStream` listener (line 569) and its 60s cancel timer (line 608) are NOT gen-guarded. Re-entry is the highest-risk edge case.
- **TS-6 requires EC-3:** `setAudioSources` throws `PlayerException` on probe failure (per just_audio docs, HIGH conf). Current `initSongs` has no try/catch around it. The exception propagates to `_autoPlay`'s catch which only logs. Fix must catch and surface.
- **TS-4 verified by TS-8:** `playback_trust_test.dart` uses `FakePlaybackEngine` with `processingState = ProcessingState.ready` by default (test:384) — it does NOT exercise the loading→ready transition. Existing tests will likely pass unchanged, but they also won't catch the race. A new test with a fake that emits `loading → ready` is needed (out of this research's scope, flagged for plan-phase).
- **EC-8 conflict:** `_autoPlay` calls `initSongs` (which internally calls `_player.play()` at line 565) AND then calls `audioHandlerProvider.audioHandler.play()` again at line 131. The second call is either redundant (playing already true) or harmful (re-enters play logic while the first is settling). The fix should consolidate to a single play initiation point — likely make `initSongs` return only after `ready` is reached (with timeout), so the external `play()` is a no-op.

## MVP Definition

### Launch With (this milestone — the fix)

Minimum viable fix — what's needed to close the bug.

- [ ] TS-1 Sound-Books book auto-plays on open — zero extra taps
- [ ] TS-2 Playback begins within reasonable time (comparable to other sources)
- [ ] TS-3 Resume case preserved for Sound-Books (history → seek to saved position → play)
- [ ] TS-4 Other 4 sources' auto-play unchanged (regression smoke per source)
- [ ] TS-5 Big play button still works for Sound-Books
- [ ] TS-6 Chapter-list tap still works for Sound-Books
- [ ] TS-7 Probe failure shows visible error (not silent no-op)
- [ ] TS-8 `playback_trust_test.dart` passes unchanged
- [ ] EC-2 `initSongs` re-entry gen-discard (listener + cancel timer gen-guarded)
- [ ] EC-5 60s listener-cancel bug fixed (gen-guarded or proper subscription lifecycle)
- [ ] EC-1 Back-navigation during probe doesn't crash (`mounted` / dispose guards)

### Add After Validation (deferred — next milestone candidates)

- [ ] Loading spinner / buffering % for non-YouTube sources — trigger: user reports "I can't tell if Sound-Books is loading"
- [ ] Cross-source play-init hardening — trigger: a second source develops a similar race
- [ ] Predictive duration probe in `SoundBooksDetailService` — trigger: probe latency exceeds 3s consistently
- [ ] Stuck-buffering skip generalized — trigger: user reports "Sound-Books hangs on slow network"
- [ ] Remove duplicate `processingStateStream.listen` at line 611 (debug logger leak) — trigger: next code-health pass

### Future Consideration (v2+ — not this milestone)

- [ ] Auto-play user preference toggle — trigger: user feedback requesting opt-out
- [ ] `useLazyPreparation: true` for very long audiobooks — trigger: just_audio issue #294 manifests (1000+ chapter books)
- [ ] Skip details screen / straight-to-player option — trigger: user-flow analytics show details screen is a drop-off

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| TS-1 Sound-Books auto-plays on open | HIGH | MEDIUM | P1 |
| TS-2 Playback begins in reasonable time | HIGH | MEDIUM | P1 |
| TS-3 Resume case preserved | HIGH | LOW | P1 |
| TS-4 Other sources unchanged | HIGH | LOW (verify) / HIGH (risk) | P1 |
| TS-5 Play button still works | HIGH | LOW | P1 |
| TS-6 Chapter tap still works | MEDIUM | LOW | P1 |
| TS-7 Probe failure visible | HIGH | MEDIUM | P1 |
| TS-8 playback_trust_test passes | HIGH | LOW | P1 |
| EC-2 gen-discard on re-entry | HIGH | MEDIUM | P1 |
| EC-5 60s listener-cancel fix | HIGH | MEDIUM | P1 |
| EC-1 back-navigation guard | MEDIUM | LOW | P1 |
| EC-4 seek on unknown duration | MEDIUM | LOW | P2 |
| EC-7 duplicate listen leak | LOW | LOW | P3 (defer) |
| EC-8 double play() consolidation | MEDIUM | LOW | P1 |
| EC-9 _autoPlayTriggered flag | LOW | LOW | P3 (no change needed) |
| EC-10 history-section entry verify | MEDIUM | LOW | P1 (verify only) |

**Priority key:**
- P1: Must have for the fix to count as done
- P2: Should verify, fix only if it regresses
- P3: Adjacent cleanup, defer to next milestone

## Competitor Feature Analysis

Confidence note: competitor UI behavior is **LOW confidence** — derived from issue trackers, not direct app testing. The HIGH-confidence bar is the user's own reference set (LibriVox/YouTube/knigavuhe/4read auto-play on open per PROJECT.md).

| Behavior | AntennaPod | BookPlayer | Smart Audiobook Player | Libby | Flow Book (target) |
|----------|------------|------------|------------------------|-------|--------------------|
| Auto-play on open (default) | Resume-on-open is default; issue #7643 "Occasionally unable to resume podcasts" confirms expected behavior | Not directly researched (repo moved, 404 on issue search) | Closed-source, not researched | Closed-source, not researched | Match LibriVox/YouTube/knigavuhe/4read — auto-play is the product |
| User-toggle for auto-play | Yes — issue #7259 "playback starts immediately… even though I told it not to" confirms a setting exists | Unknown | Unknown | Unknown | Not requested — auto-play ON, no toggle |
| Visible error on probe failure | Expected (mature app pattern) | Expected | Expected | Expected | **Currently missing for Sound-Books** — `_autoPlay` catch only logs (line 133) |
| Loading feedback during probe | Varies (spinner / buffered %) | Unknown | Unknown | Unknown | YouTube-only (`isBufferingYouTube`); Sound-Books deferred |
| Resume from saved position | Yes (core feature) | Yes (core feature) | Yes (core feature) | Yes (core feature) | Yes — preserve for Sound-Books |
| Reliability of play-on-ready handoff | Bug #7643 "Occasionally unable to resume" — even mature apps race | Unknown | Unknown | Unknown | Currently buggy for Sound-Books — fix target |

**Pattern worth mirroring:** None specifically. The fix is internal to `MyAudioHandler.initSongs` — no UI pattern to copy. The closest external validation is that mature audiobook/podcast apps (AntennaPod) also have play-on-open reliability bugs, which confirms this is a hard problem, not a Flow Book-specific mistake.

## Edge Cases (behaviors the fix must handle to not regress)

These are the specific scenarios the question asked about, grounded in the code.

### EC-1: User navigates back during the probe
**Scenario:** User taps a Sound-Books book, details screen opens, `_autoPlay` fires `initSongs` (probe in flight), user hits back before `ready`.
**Current behavior:** `AudiobookDetails.dispose()` (line 266) cancels `_downloadSub` and removes buffering listeners — but does NOT cancel the in-flight `initSongs`. `_autoPlay` continues: Hive writes (lines 100-105) already happened synchronously before any await — good. But `_weSlideController.show()` at line 132 fires after dispose → may throw or no-op on a disposed controller. `mounted` is not checked between `initSongs` await and `_weSlideController.show()`.
**Required:** No crash. Either guard `_weSlideController.show()` with `mounted`, or make `initSongs` cancellable. Low complexity.
**Detection:** Open Sound-Books book, tap back immediately (<500ms), check for framework errors in console.

### EC-2: `initSongs` re-entered (gen-discard)
**Scenario:** User taps book A, then before A's probe completes, taps book B (or navigates A → back → B).
**Current behavior:** `_initGen` (my_audio_handler.dart:424) increments on each entry. Stale invocation checks `if (myGen != _initGen) return;` at lines 526, 549, 622 — correctly short-circuits the stale queue build and seek. **BUT** the `processingStateStream` listener at line 569 and its 60s cancel timer at line 608 are NOT gen-guarded. Invocation A's listener stays alive for 60s, receiving states from invocation B's player. Invocation A's 60s timer can cancel invocation B's listener (if B's listener is the one `sub` refers to after re-assignment — actually `sub` is local to the `if (playImmediately)` block, so each invocation has its own `sub`, but A's 60s timer still fires and cancels A's `sub` — which is correct. The real risk is A's listener firing `_player.play()` during B's loading, re-triggering play on the wrong source).
**Required:** Gen-guard the listener body (`if (myGen != _initGen) { sub.cancel(); return; }`) and the cancel timer. Medium complexity.
**Detection:** Open book A, within 1s open book B, verify B plays (not A) and no duplicate audio.

### EC-3: MP3 probe 404s / network fails
**Scenario:** Sound-Books MP3 URL returns 404, or network is down, during `setAudioSources`.
**Current behavior:** `setAudioSources` (my_audio_handler.dart:540) throws `PlayerException` (per just_audio docs, HIGH conf). No try/catch around it. Exception propagates up through `initSongs` → `_autoPlay` catch (audiobook_details.dart:133) → `AppLogger.debug` only. **Silent no-op.** User sees the details screen, no playback, no error.
**Required:** Visible error. Either catch in `initSongs` and rethrow as a typed error that `_autoPlay` surfaces (SnackBar matching `_playChapter` pattern at line 87), or catch in `_autoPlay` and show SnackBar. Medium complexity (must preserve `playback_trust_test.dart` expectations — the fake doesn't throw).
**Detection:** Point the player at a 404 URL (or use a fake that throws from `setAudioSources`), verify SnackBar appears.

### EC-4: Book already in history (resume) + unknown duration
**Scenario:** User previously listened to a Sound-Books book to position 600000ms (10min), reopens it.
**Current behavior:** `_autoPlay` (audiobook_details.dart:107-119) reads `historyItem.index` + `historyItem.position`, calls `initSongs(files, audiobook, idx, historyItem.position)`. `initSongs` seeks to `positionInMilliseconds` at line 558 (`_player.seek(Duration(milliseconds: positionInMilliseconds), index: safeIndex)`). For non-YouTube, no `_waitForProcessingReady` before seek — seek happens immediately after `setAudioSources` returns, while the probe may still be in flight. Seeking on a source with unknown duration (duration is null until probe completes) may throw or no-op.
**Required:** Resume position preserved. Either await `ready` before seek (current YouTube path does this at line 553), or accept that seek-after-ready is the correct general pattern. Medium complexity.
**Detection:** Listen to a Sound-Books book for 10min, close, reopen, verify it resumes at ~10min not 0.

### EC-5: The 60-second fire-and-forget `Future.delayed` listener cancel
**Scenario:** The listener at line 569 is meant to re-fire `play()` on `ready`. The `Future.delayed(const Duration(seconds: 60), () => sub.cancel())` at line 608 cancels it after 60s regardless of state.
**Is this a feature or a bug?** **BUG.** It's a leak-prevention hack that creates two problems:
1. If the Sound-Books probe takes >60s (slow network, large file, server slow), the ready-re-fire listener is already cancelled. Playback never starts.
2. The `Future.delayed` is fire-and-forget — not gen-guarded, not stored, not cancellable. If `initSongs` is re-entered (EC-2), the first invocation's 60s timer still fires, but since `sub` is local to the first invocation's block, it cancels the first invocation's listener (correct). The deeper issue is that the listener itself isn't gen-guarded (see EC-2).
**Required:** Replace with a proper subscription lifecycle: store the `StreamSubscription`, cancel it on the next `initSongs` entry, on `stop()`, on `dispose()`. Or gen-guard the cancel. Medium complexity.
**Detection:** Throttle network to 56k speeds, open a long Sound-Books book, verify playback starts after 60s+ (currently fails).

### EC-6: `_isReinitializing` flips false before the listener's 60s window ends
**Scenario:** `initSongs` `finally` block (line 640) sets `_isReinitializing = false` as soon as `initSongs` returns — but the listener at line 569 keeps firing for 60s. During that window, `_isReinitializing` is false, so `MiniAudioPlayer` restore (mini_audio_player.dart:72) and other callers can race.
**Current behavior:** `MiniAudioPlayer` checks `isReinitializing` at line 72 and bails — but only if true. After `initSongs` returns, that guard is gone. If the listener re-fires `play()` during a `MiniAudioPlayer` restore, the restore can be disrupted.
**Required:** Define the listener's lifecycle as part of `initSongs`'s logical extent. Either keep `_isReinitializing` true while the listener is alive, or cancel the listener in `finally`. Tied to EC-5 fix. Medium complexity.

### EC-7: Duplicate `processingStateStream.listen` at line 611
**Scenario:** Immediately after the play-on-ready listener block, line 611 attaches a SECOND `processingStateStream.listen` that only logs debug output. It is never cancelled. Every `initSongs` call adds a permanent listener.
**Current behavior:** StreamSubscription leak. N invocations → N permanent listeners, each logging. Not directly part of the auto-play bug but adjacent.
**Required:** Remove or gen-guard. Low complexity. **Defer to next milestone (P3)** unless the fix naturally removes it.

### EC-8: `_autoPlay` calls `play()` twice
**Scenario:** `_autoPlay` (audiobook_details.dart:94) awaits `initSongs` (which internally calls `_player.play()` at my_audio_handler.dart:565), then at line 131 calls `audioHandlerProvider.audioHandler.play()` again.
**Current behavior:** The second `play()` either no-ops (playing already true) or re-enters `MyAudioHandler.play()` (line 877) which calls `_restoreQueueFromBoxIfEmpty` (line 880 — bails because `_audioSources` is non-empty) then `_player.play()` again. For Sound-Books during loading, the second call is at best redundant, at worst disruptive (re-enters play logic while the first is still settling).
**Required:** Consolidate to a single play-initiation point. Either `initSongs` returns only after `ready` (so the external `play()` is a no-op), or `_autoPlay` doesn't call external `play()` when `initSongs` was called with `playImmediately: true`. Low complexity.
**Detection:** Verify only one `_player.play()` call per open via debug log count.

### EC-9: `_autoPlayTriggered` flag (audiobook_details.dart:65)
**Scenario:** The flag at line 65 ensures `_autoPlay` fires only once per `AudiobookDetails` instance, on the first `AudiobookDetailsLoaded` state (line 397). If the bloc re-emits `Loaded` with different files (e.g. refresh), auto-play won't re-fire.
**Current behavior:** Acceptable — opening a book should auto-play once; re-emissions are metadata refreshes, not re-opens.
**Required:** No change. **P3 — no work needed.**

### EC-10: History-section tap (history_section.dart:170) is a third entry point
**Scenario:** Tapping a history item calls `initSongs` with `playImmediately` defaulting to true (no explicit `playImmediately: false`) — same as `_autoPlay`. Same bug surface.
**Current behavior:** Same race as `_autoPlay` for Sound-Books books in history.
**Required:** The fix to `initSongs` covers this path automatically (it's shared code). **Verify, don't separately fix.** Low complexity (verification only).
**Detection:** Tap a Sound-Books book from history, verify auto-play works.

## Sources

- `.planning/PROJECT.md` — bug statement, scope constraints, out-of-scope list (PRIMARY, HIGH confidence)
- `lib/screens/audiobook_details/audiobook_details.dart` — `_autoPlay`, `_playChapter`, play button `onTap`, `_autoPlayTriggered` (PRIMARY, HIGH confidence)
- `lib/resources/services/my_audio_handler.dart` — `initSongs` play sequence, 60s listener cancel, `_initGen` gen-guard, duplicate listen at line 611 (PRIMARY, HIGH confidence)
- `lib/widgets/mini_audio_player.dart` — `isReinitializing` guard at line 72, `playImmediately: false` restore pattern (PRIMARY, HIGH confidence)
- `lib/screens/home/widgets/history_section.dart` — third `initSongs` entry point at line 170 (PRIMARY, HIGH confidence)
- `lib/resources/services/soundbooks/soundbooks_detail_service.dart` — `_parseM3uPlaylist` at line 194, confirms `length: 0` for Sound-Books (PRIMARY, HIGH confidence)
- `test/playback_trust_test.dart` — 520 lines, `FakePlaybackEngine` with `processingState = ProcessingState.ready` default, encoded invariants (PRIMARY, HIGH confidence)
- `test/soundbooks_test.dart` — line 148 confirms `'length': 0.0` fixture for Sound-Books (PRIMARY, HIGH confidence)
- just_audio pub.dev README (https://pub.dev/packages/just_audio) — state model, ProcessingState transitions, `play()` during `loading` semantics, `PlayerException` on load failure, `preload` parameter (OFFICIAL DOCS, HIGH confidence)
- just_audio GitHub issue #294 (https://github.com/ryanheise/just_audio/issues/294) — large playlist load times, `useLazyPreparation` workaround (MEDIUM confidence, 2021 issue still open)
- AntennaPod GitHub issues #7259, #7643, #7712 — auto-play toggle exists, resume-on-open is expected but racy even in mature apps (LOW confidence — issue trackers, not UI testing)
- BookPlayer, Smart Audiobook Player, Libby — NOT directly researched (closed-source or repo moved); behavior inferred from the user's reference set in PROJECT.md (LOW confidence)

---
*Feature research for: audiobook player auto-play-on-open (Sound-Books race fix)*
*Researched: 2026-07-14*
