# Flow Book

## What This Is

Flow Book (`audiobookflow`) is a Flutter audiobook player that aggregates five audio sources (Librivox/Archive.org, YouTube, 4read, knigavuhe, Sound-Books) plus local/downloaded files into one browsing + playback experience. Targets Android and macOS. Already shipped as v1.2.0+2020 via GitHub Releases. **Milestone v1.0 (Sound-Books Auto-Play Fix) complete** — opening any book from any source now auto-plays in one gesture. **Milestone v1.1 (Cold-Restore Progress Bar Fix) in progress** — after quitting and returning, the progress bar must reflect the restored position from the first frame.

## Core Value

Tap a book from any source and it plays — discover to playback in one gesture.

## Requirements

### Validated

- ✓ Browse Librivox/Archive.org catalog (search + details + play) — existing
- ✓ Browse YouTube audiobooks (search + import + stream) — existing
- ✓ Browse 4read catalog (search + webview login + details + play) — existing
- ✓ Browse knigavuhe catalog (list + search + details + play) — existing
- ✓ Browse Sound-Books catalog (list + search + details + play) — existing
- ✓ Play local/downloaded files (chapter parsing, cover extraction) — existing
- ✓ Background playback + media notification (audio_service) — existing
- ✓ Position persistence + resume across sessions (Hive) — existing
- ✓ Bookmarks, favourites, listening stats, history — existing
- ✓ Sleep timer, equalizer (Android), speed control — existing
- ✓ In-app APK self-update (GitHub Releases) — existing
- ✓ Theme (light/dark/blue), language prefs — existing

### Active

(None — all milestone v1.0 work validated.)

## Current Milestone: v1.1 Cold-Restore Progress Bar Fix

**Goal:** After quitting the app and returning to the last played book, pressing play resumes at the saved position *and* the progress bar reflects that position correctly from the first frame.

**Target area (single bug):**
- The position-stream bridge between the forked just_audio's deferred-load path and the UI's `ProgressBarWidget` (`getPositionStream()` → `Rx.combineLatest3`). After cold-restore with `playImmediately: false`, the deferred native load applies the saved index/position, so audio is correct — but the Dart streams that feed the progress bar lag behind / emit `Duration.zero` until the native load settles, and the `total` duration is `null` until the load completes. Result: bar renders at 0:00 and doesn't advance.

**Key context:**
- Must not regress `playback_trust_test.dart` — in particular the `playImmediately: false` invariant ("NO seek before deferred load") and the restore test.
- Forked `just_audio` semantics pinned (ref `a6f8db8`): `initialSeekValues` applied on deferred load; `seek()` wipes them pre-load.
- v1.0 fix (await `ProcessingState.ready` before `play()`) stays intact.

### Validated (prior milestones)

- ✓ Browse Librivox/Archive.org catalog (search + details + play) — existing
- ✓ Browse YouTube audiobooks (search + import + stream) — existing
- ✓ Browse 4read catalog (search + webview login + details + play) — existing
- ✓ Browse knigavuhe catalog (list + search + details + play) — existing
- ✓ Browse Sound-Books catalog (list + search + details + play) — existing
- ✓ Play local/downloaded files (chapter parsing, cover extraction) — existing
- ✓ Background playback + media notification (audio_service) — existing
- ✓ Position persistence + resume across sessions (Hive) — existing
- ✓ Bookmarks, favourites, listening stats, history — existing
- ✓ Sleep timer, equalizer (Android), speed control — existing
- ✓ In-app APK self-update (GitHub Releases) — existing
- ✓ Theme (light/dark/blue), language prefs — existing
- ✓ **v1.0 PLAY-01..06 / ERR-01..02 / TEST-02..03** — Sound-Books auto-play fix (await `ProcessingState.ready` gate + call-site consistency + SnackBar error surfacing); `playback_trust_test.dart` green

### Active

(None — requirements for v1.1 defined in REQUIREMENTS.md.)

### Out of Scope

- Other restore/resume issues beyond the progress bar (e.g. duration not showing for streaming sources, mini-player state, notification position) — explicitly deferred (minimal scope, "just this bug")
- Cross-source restore hardening — explicitly deferred
- 4 active OpenSpec changes (`fix-4read-book-open-error`, `four-read-top-books`, `knigavuhe-search-integration`, `youtube-playlist-auto-load`) — tracked separately under openspec/, not part of this milestone

## Context

**Root cause (from codebase audit + questioning):**

Sound-Books is the only source whose files come back with `length: 0` (duration unknown) — the m3u playlist parsed in `soundbooks_detail_service.dart:194` has no duration metadata. Every other source either has durations in its API response or probes them inline. When `MyAudioHandler.initSongs` (my_audio_handler.dart:416) builds `AudioSource.uri` for a Sound-Books MP3, `just_audio` must make a network probe to learn the duration before the source is `ready`.

The auto-play flow (`audiobook_details.dart:397` → `_autoPlay` → `initSongs`) fires `_player.play()` at `my_audio_handler.dart:565` **while the player is still in `loading`/`buffering`** state. The `processingStateStream` listener that should re-fire `play()` on `ready` (line 569) is attached **after** the initial `play()` call — a race that can miss the `ready` transition. The explicit `play()` from `_autoPlay` (line 131) lands while `_isReinitializing` is still true and the probe is still in flight, so it's also dropped. Result: auto-play silently no-ops for Sound-Books; the user must press play (sometimes twice) to start playback.

Other sources don't hit this because their durations are known up front, so `setAudioSources` resolves to `ready` synchronously and the first `_player.play()` works.

**Relevant prior fixes (archived OpenSpec changes):**
- `2026-07-13-fix-soundbooks-playback-encoding` — fixed URL encoding for Cyrillic filenames in Sound-Books playlists (this is why playback works at all once started)
- `2026-07-13-fix-player-url-encoding-defense` — defense-in-depth `sanitizePlayerUrl` in `my_audio_handler.dart`

**Existing tests touching this area:**
- `test/playback_trust_test.dart` (520 lines) — covers `MyAudioHandler` init/restore via `FakePlaybackEngine`. Any fix to `initSongs` play logic must keep these passing.
- `test/soundbooks_test.dart` (291 lines) — covers `SoundBooksDetailService` detail parsing. Unaffected by the play fix.

## Constraints

- **Tech stack**: Flutter 3.44.1 / Dart ^3.5.4, `just_audio` (forked), `audio_service`, `flutter_bloc`, `provider`, Hive v2 — no new dependencies for this fix
- **Don't break other sources**: LibriVox/YouTube/knigavuhe/4read auto-play must keep working — any change to `initSongs` play sequence is shared code
- **Don't break `playback_trust_test.dart`**: the 520-line test suite encodes the invariants the fix must preserve
- **Minimal scope**: user explicitly chose "just fix it" — no loading-feedback UI, no cross-source hardening, no details-screen redesign
- **Forked `just_audio`** (`sagarchaulagai/just_audio.git @ a6f8db8`): `ProcessingState` / `setAudioSources` semantics are pinned to this fork; don't assume upstream behavior

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Fix lives in `MyAudioHandler.initSongs` play sequence, not in the details screen | The race is in the shared play-init logic; the details-screen `_autoPlay` already calls `play()` correctly — the drop happens deeper | ✓ Validated in Phase 3: `await ProcessingState.ready` gate in initSongs; race detector un-skipped and passing |
| Sound-Books is the only affected source (confirmed by user) | Other sources return durations in their API responses; only Sound-Books m3u has `length: 0` forcing a network probe | ✓ Validated in Phase 1 diagnostic (4/5 Sound-Books books confirmed race on macOS); fix landed in Phase 3 |
| Keep the details screen in the flow | User wants to "open book and it starts playing" — opening the details screen is desired, just wants auto-play to work | ✓ Validated in Phase 3: big play button, `_autoPlay`, `_playChapter` all consistent (playImmediately:true) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-03 — milestone v1.1 (Cold-Restore Progress Bar Fix) started*
