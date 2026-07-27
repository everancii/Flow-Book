# Milestones

## v1.0 Sound-Books Auto-Play Fix (Shipped: 2026-07-27)

**Phases completed:** 4 phases, 5 plans, 9 tasks

**Key accomplishments:**

- FakePlaybackEngine loading->ready simulation via test-code config + 5 [DIAG]-tagged AppLogger.debug checkpoints in initSongs (try/catch rethrows, no behavior change)
- Release APK built with [DIAG] logs; 5 Sound-Books books tested on macOS desktop — race confirmed (play fires during buffering), audio plays on macOS, Android-specific mechanism pending
- 1. [Rule 4 - Architectural] _initSettleSub field removed by Phase 03
- initSongs now awaits ProcessingState.ready (10s timeout) before play() — the actual Sound-Books auto-play fix; Phase 2 listener machinery and Phase 1 diagnostics removed; big play button made consistent with all callers showing SnackBars on failure.
- history_section.dart's onTap now matches the canonical _autoPlay pattern (async try/catch + await + mounted guard + SnackBar) with all 4 Hive writes relocated before the await — closing the last call-site consistency gap; TEST-02 stays 18/18 and PLAY-03 is captured as an 8-row manual smoke.

---
