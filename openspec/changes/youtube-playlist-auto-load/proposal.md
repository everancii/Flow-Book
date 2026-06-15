## Why

When a user finds a YouTube audiobook by searching (e.g. "Стівен Кінг - Воно # 01"), the video is typically chapter 1 of a multi-part playlist. Today the user must go back to search and manually find every subsequent chapter, which breaks the listening experience. Surfacing the full playlist automatically turns a single search hit into a complete audiobook.

## What Changes

- When a YouTube search result is tapped and the video belongs to a playlist, all other videos in that playlist are fetched and added as chapters.
- The audiobook player loads the full chapter list (playlist order) rather than a single video.
- The audiobook details screen shows all chapters with their titles and durations.
- No change to the search results UI — the enhancement happens at the details/player layer.

## Capabilities

### New Capabilities

- `youtube-playlist-chapters`: Given a YouTube video that belongs to a playlist, fetch the full ordered list of playlist videos and expose them as chapters for the audiobook player.

### Modified Capabilities

- *(none — no existing spec-level requirements are changing)*

## Impact

- **`lib/resources/services/youtube/youtube_search_service.dart`** — after resolving a video, check for `video.playlistId`; if present, fetch the playlist and return all videos as chapters.
- **`lib/resources/models/audiobook.dart`** — `files` field populated with ordered playlist entries (url + title + duration).
- **`lib/screens/audiobook_details/audiobook_details.dart`** — chapter list already rendered when `files` is non-empty; no structural change needed.
- **`lib/resources/services/my_audio_handler.dart`** — already handles multi-file playlists; no change needed.
- **`youtube_explode_dart`** (pub-cache fork) — `PlaylistClient.getVideos()` already available; no patch needed.
