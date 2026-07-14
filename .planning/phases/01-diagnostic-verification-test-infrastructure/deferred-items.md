# Deferred Items — Phase 01

Out-of-scope discoveries logged during execution. Not fixed per scope-boundary rule.

## Pre-existing test failures (discovered during 01-01 Task 1)

| Test | File | Group | Status |
|------|------|-------|--------|
| `derives display durations from explicit duration, length, and start offsets` | `test/playback_trust_test.dart` | `chapter switching metadata` | FAILING on clean baseline `codex/improve-android-update-flow` (verified via `git stash` + re-run) |
| `falls back to next chapter start when no explicit duration exists` | `test/playback_trust_test.dart` | `chapter switching metadata` | FAILING on clean baseline |

**Verification:** `git stash` (revert 01-01 changes) → `flutter test test/playback_trust_test.dart` → same 2 failures, `+9 -2`. Failures are in the `chapter switching metadata` group (lines 176-208), which 01-01 does NOT touch. 01-01 only modifies the `MyAudioHandler with fake playback engine` group (line 210+).

**Impact on 01-01 acceptance criteria:** The criterion "`flutter test test/playback_trust_test.dart` exits 0" cannot be satisfied because of these pre-existing failures. 01-01's new tests (1 passes, 1 skipped) introduce ZERO new failures. The suite goes from `+9 -2` (baseline) to `+10 ~1 -2` (with 01-01) — the 2 failures are unchanged, 1 new pass + 1 new skip added.

**Root cause hypothesis (not investigated — out of scope):** Likely a `formatTrackDuration` / `effectiveTrackLength` behavior drift in `track_section_dialog.dart` or `_sampleFiles()` duration field shape. Not related to the Sound-Books auto-play race this phase targets.

**Disposition:** Deferred. Do NOT fix in Phase 01. Track for a separate maintenance pass.
