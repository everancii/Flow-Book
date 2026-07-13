# Flow Book

## What This Is

Flow Book (`audiobookflow`) is a Flutter audiobook player that aggregates five audio sources (Librivox/Archive.org, YouTube, 4read, knigavuhe, Sound-Books) plus local/downloaded files into one browsing + playback experience. Targets Android and macOS. Already shipped as v1.2.0+2020 via GitHub Releases.

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

- [ ] Opening a Sound-Books book starts playback automatically — no play button press required (matches LibriVox/YouTube/knigavuhe/4read behavior)

### Out of Scope

- Other sources' auto-play — confirmed working, not touching (user reports only Sound-Books is broken)
- Details-screen skip / straight-to-player navigation — user wants to keep opening the details screen; just wants it to auto-play
- Loading spinner / buffering feedback for non-YouTube sources — explicitly deferred ("just fix it")
- Hardening the `initSongs` play race across all sources — explicitly deferred (minimal scope)
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
| Fix lives in `MyAudioHandler.initSongs` play sequence, not in the details screen | The race is in the shared play-init logic; the details-screen `_autoPlay` already calls `play()` correctly — the drop happens deeper | — Pending |
| Sound-Books is the only affected source (confirmed by user) | Other sources return durations in their API responses; only Sound-Books m3u has `length: 0` forcing a network probe | — Pending |
| Keep the details screen in the flow | User wants to "open book and it starts playing" — opening the details screen is desired, just wants auto-play to work | — Pending |

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
*Last updated: 2026-07-14 after initialization*
