# Phase 3: Ready-Before-Play Fix - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-15
**Phase:** 3-Ready-Before-Play Fix
**Areas discussed:** Await mechanism design, Timeout + error behavior, Call-site consistency, Error surfacing + mounted guards

---

## Await Mechanism Design

**Q1: How should initSongs await ProcessingState.ready before play()?**

| Option | Description | Selected |
|--------|-------------|----------|
| Await replaces listener | `await processingStateStream.firstWhere(ready).timeout(10s)` replaces play() + _initSettleSub entirely | ✓ |
| Keep listener + add await | Both mechanisms coexist — await gates initial play, listener catches transitions | |
| Use existing polling loop | Use _waitForProcessingReady (50ms sleep) instead of stream-based firstWhere | |

**User's choice:** Await replaces listener
**Notes:** BehaviorSubject replays last value → zero latency for known-duration sources. _initSettleSub, 30s buffering-skip, and idle recovery all removed — the await makes them unnecessary.

**Q2: How should the 10s bounded timeout behave when ready never arrives?**

| Option | Description | Selected |
|--------|-------------|----------|
| 10s timeout, rethrow on timeout | Log + rethrow TimeoutException → caller shows SnackBar | ✓ |
| 10s timeout, skip to next track | Log + seekToNext + play, no rethrow | |
| Configurable timeout parameter | initSongs param with 10s default | |

**User's choice:** 10s timeout, rethrow on timeout
**Notes:** Matches Phase 1 probe-duration findings. Rethrow lets the caller's existing catch/SnackBar pattern handle the error.

---

## Call-Site Consistency

**Q1: How should the big play button be made consistent with _autoPlay and _playChapter?**

| Option | Description | Selected |
|--------|-------------|----------|
| Match _autoPlay pattern | await initSongs + await play(), try/catch, mounted guard | |
| playImmediately:false + explicit play() | await initSongs(playImmediately:false) + await play() — explicit load-then-play | ✓ |
| Minimal: add .catchError() only | Leave fire-and-forget, just catch errors | |

**User's choice:** playImmediately:false + explicit play()
**Notes:** Makes the button's intent clear: load first, then play. More explicit and testable than relying on playImmediately.

**Q2: Keep or remove redundant play() calls in _autoPlay/_playChapter?**

| Option | Description | Selected |
|--------|-------------|----------|
| Remove redundant play() calls | initSongs handles play internally with the new await-ready | ✓ |
| Keep as fallback | Harmless no-ops if already playing, defensive | |

**User's choice:** Remove redundant play() calls
**Notes:** Cleaner. initSongs with playImmediately:true handles everything internally.

---

## Error Surfacing + Mounted Guards

**Q1: How should PlayerException from setAudioSources be surfaced?**

| Option | Description | Selected |
|--------|-------------|----------|
| Rethrow, caller shows SnackBar | Keep Phase 1 rethrow; caller catches + SnackBar | ✓ |
| initSongs emits error state | New ValueNotifier/stream for error messages | |

**User's choice:** Rethrow, caller shows SnackBar
**Notes:** Matches existing _playChapter pattern. No new state-management plumbing needed.

**Q2: Where should mounted guards + SnackBar be added?**

| Option | Description | Selected |
|--------|-------------|----------|
| Match _playChapter everywhere | All 3 call sites get the same try/catch + mounted + SnackBar | ✓ |
| Add guards only where missing | Only fix _autoPlay + big button; _playChapter already done | |

**User's choice:** Match _playChapter pattern everywhere
**Notes:** Uniform error handling across all entry points.

**Q3: Remove [DIAG] logs now?**

| Option | Description | Selected |
|--------|-------------|----------|
| Remove [DIAG] logs | Phase 3 is THE fix — clean up diagnostic scaffolding | ✓ |
| Keep until Phase 4 | Preserve for cross-source smoke verification | |

**User's choice:** Remove [DIAG] logs
**Notes:** Keep non-[DIAG] AppLogger.debug calls that predated Phase 1.

---

## Claude's Discretion

- Whether to extract 10s timeout as static const or inline.
- Whether to remove _waitForProcessingReady if it becomes unused.
- Exact test updates for the Phase 1 "unconditionally" and "race detector" tests.

## Deferred Ideas

- Loading spinner / buffering feedback — v2
- Unifying _waitForProcessingReady (poll) with stream-based await — v2 if poll method still has callers
