# Phase 4 — PLAY-03 Manual On-Device Smoke (UAT)

**Purpose:** This is a MANUAL on-device smoke for requirement **PLAY-03** (the other 4 sources' auto-play must keep working — no regression) and **PLAY-04** (Sound-Books works across every user-facing entry point). It is run by the user on a real device after the Phase 4 code lands. It is NOT automated — the underlying zero-latency claim (BehaviorSubject replay short-circuits the await synchronously for known-duration sources) and the cross-source real-network probe cannot be exercised by the unit suite.

**When to run:** After the Phase 4 `04-01` code commit (`feat(phase-04/04-01)`) is on the device.

**Automated backing:** `test/playback_trust_test.dart` (TEST-02 = 18/18 green) backs this manual smoke by proving the `initSongs` await-ready gate and race detector hold. It cannot replace the real-network probe below — the fake playback engine never makes a network call.

---

## Pass Bar (D-07)

The phase PASSES the manual smoke when ALL of the following are true:

1. **Zero regressions** in LibriVox, YouTube, knigavuhe, and 4read auto-play on open — each plays immediately, no error SnackBar.
2. **Sound-Books works across all 4 entry points** (auto-play on open, resume from history, big play button, chapter-list tap).
3. **Tap-to-audio latency under 100ms** for known-duration sources (LibriVox, YouTube, knigavuhe, 4read). The Phase 3 await-ready gate short-circuits synchronously because the fork's `processingStateStream` is a `BehaviorSubject.seeded(idle)` that replays the current value — for sources whose duration is known up front, `firstWhere(ready)` completes without yielding. (Sound-Books is exempt — it waits up to ~10s for its duration probe, which is the intended Phase 3 behavior.)
4. **No red screens, no silent no-ops, no crashes** on any entry point.

If ANY of the above fails, the phase FAILS UAT — investigate before release.

---

## Smoke Matrix

Run each row on a real device. Check the box when it passes. The Sound-Books rows are the focus (Phase 3 fixed them); the other 4 sources are regression guards.

| # | Source | Entry Point | Expected Behavior | Pass/Fail |
|---|--------|-------------|-------------------|-----------|
| 1 | Sound-Books | auto-play on open (details screen) | Opens details screen and playback begins automatically within ~10s, zero extra taps | ☐ |
| 2 | Sound-Books | resume from history (history carousel tap on Home — the call site hardened in Task 1) | Resumes at the saved position and plays within ~10s, zero extra taps | ☐ |
| 3 | Sound-Books | big play button (details screen) | Playback starts on the first tap (no second tap needed) | ☐ |
| 4 | Sound-Books | chapter-list tap (details screen) | Plays the selected chapter immediately after tap | ☐ |
| 5 | LibriVox | auto-play on open | Plays immediately (tap-to-audio < 100ms) | ☐ |
| 6 | YouTube | auto-play on open | Plays (network stream-extraction probe latency acceptable; no error SnackBar) | ☐ |
| 7 | knigavuhe | auto-play on open | Plays immediately (tap-to-audio < 100ms) | ☐ |
| 8 | 4read | auto-play on open | Plays immediately (tap-to-audio < 100ms) | ☐ |

---

## Regression Check (PLAY-03 core)

Open and auto-play one book from EACH of the 4 non-Sound-Books sources (LibriVox, YouTube, knigavuhe, 4read). For each, confirm:

- Playback starts automatically on opening the details screen.
- **No error SnackBar appears** (specifically, the message "Unable to start playback. Please try again." must NOT appear for a healthy URL).
- No behavior change vs. before the Phase 4 code landed.

If the SnackBar appears for a known-good book in any of these 4 sources, that is a **PLAY-03 regression** — stop and investigate before proceeding.

---

## Error-Path Check (validates Task 1's catch block)

This row validates the history-tap hardening landed in Task 1 end-to-end.

**Scenario:** Tap a Sound-Books book in the Home "Recently Played" carousel whose underlying URL is dead / 404 / unreachable (e.g., temporarily block the host or use a known-stale history entry).

**Expected:** The generic error SnackBar **"Unable to start playback. Please try again."** appears (instead of a silent no-op, an unhandled exception, or a red error screen). The app remains usable; tapping a different book still works.

**Pass/Fail:** ☐

This confirms the `try/catch` around `await initSongs(...)` in `history_section.dart`'s onTap catches both the `TimeoutException` (Phase 3 D-05/D-06 — 10s ready-timeout rethrow) and any `setAudioSources` rethrow (Phase 3 D-10), and surfaces them as the user-visible SnackBar.

---

## Results (to be filled in by the user)

- **Run on device:** ___ (model / OS version)
- **Date:** ___
- **Result:** ☐ PASS / ☐ FAIL
- **Notes:** ___
- **Failures (if any):** list the row number(s) that failed and what happened

---

*Phase: 04-Call-Site Consistency + Cross-Source Verification*
*Plan: 01 — Task 2 UAT artifact (manual, user-run on real device)*
*Requirements: PLAY-03, PLAY-04*
*Automated backing: TEST-02 (playback_trust_test.dart 18/18)*
