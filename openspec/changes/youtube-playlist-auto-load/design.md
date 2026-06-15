## Context

YouTube audiobooks are often split into numbered chapters uploaded to a single playlist (e.g. "Стівен Кінг - Воно # 01 … # 67"). The current flow returns a `SearchVideo` with a `playlistId` already embedded in the `youtube_explode_dart` response, but the app only fetches the single video and ignores the playlist. The `PlaylistClient` in the library exposes `getVideos(playlistId)` which streams all videos in order.

Affected surfaces: `YoutubeSearchService` (new playlist fetch logic), `Audiobook.fromMap` (already handles `files` list), the player (`MyAudioHandler` — already handles multi-file), and the details screen (chapter list already rendered from `files`).

## Goals / Non-Goals

**Goals:**
- When a tapped search result video belongs to a playlist, fetch all playlist videos and expose them as ordered chapters.
- Map each playlist video to an `AudiobookFile`-compatible map entry (`url`, `title`, `duration`).
- Gracefully degrade: if playlist fetch fails, fall back to single-video behaviour.
- Keep search result display unchanged (one card per video, not one card per playlist).

**Non-Goals:**
- De-duplicating playlists in search results (e.g. showing only chapter 1 when chapters 1–67 all appear).
- Caching playlist contents across sessions.
- Modifying the search query or ranking.
- Supporting playlists from sources other than YouTube.

## Decisions

### 1 — Where to do the playlist expansion

**Decision**: Expand inside `YoutubeSearchService.search()` per-video, at the same point where `_yt.videos.get()` is already called.

**Rationale**: The service layer already owns the YouTube API calls. Putting expansion here keeps the BLoC and details screen unchanged and allows the returned `Audiobook` to already carry all chapters.

**Alternative considered**: Expand lazily in the details screen BLoC when the user opens the details. Rejected because it would require a new BLoC state, new event, and would leave the `Audiobook` model incomplete until a second network round-trip.

### 2 — File list format

**Decision**: Populate `Audiobook.files` (the `List<Map>` that `AudiobookFile.fromMap` already reads) with one entry per playlist video: `{ 'url': videoId, 'name': title, 'size': durationMs }`.

**Rationale**: Reuses the existing data model and player without schema changes. The player already iterates `files` as chapters.

**Alternative considered**: A separate `chapters` field. Rejected — unnecessary model change; `files` already carries this semantic for 4Read and Librivox.

### 3 — Playlist fetch cap

**Decision**: Cap playlist fetch at 100 videos to avoid very long initial load times.

**Rationale**: Typical audiobook playlists are 10–100 chapters. Streaming the full playlist of 500+ music videos would be slow and wasteful.

## Risks / Trade-offs

- **Slow cold load for large playlists** → Mitigation: 100-video cap; fetch is parallel (Future.wait already used).
- **`playlistId` absent on some videos** → Mitigation: fall back to single-video; no user-visible regression.
- **YouTube rate limiting during playlist fetch** → Mitigation: per-item catch already in place; playlist fetch wrapped in same try/catch.
- **Chapter ordering** → `getVideos` returns playlist order by default; no extra sorting needed.
