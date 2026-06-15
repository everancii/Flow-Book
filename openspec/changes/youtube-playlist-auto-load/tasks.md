## 1. Service Layer — Playlist Expansion

- [x] 1.1 In `YoutubeSearchService.search()`, after `_yt.videos.get(video.id.value)`, check `fullVideo.playlistId` (or `video.playlistId`); if non-null, call `_yt.playlists.getVideos(playlistId).take(100).toList()`
- [x] 1.2 Map each playlist video to a `Map` with keys `url` (video ID string), `name` (title), `size` (duration in milliseconds as int)
- [x] 1.3 Wrap the playlist fetch in a try/catch; on failure fall back to the single-video `files` list
- [x] 1.4 Pass the resulting `files` list into `Audiobook.fromMap` under the `'files'` key

## 2. Model Verification

- [x] 2.1 Confirm `Audiobook.fromMap` correctly reads a `files` list of `{'url', 'name', 'size'}` maps and populates `audiobook.files`
- [x] 2.2 Confirm `AudiobookFile.fromMap` maps `url` → playable video ID, `name` → display title, `size` → duration

## 3. Player Integration

- [x] 3.1 Confirm `MyAudioHandler.initSongs` already handles YouTube `files` entries (each `url` is a video ID passed to `YouTubeAudioSource`); no code change expected — verify and document
- [x] 3.2 If `initSongs` assumes `files[0]` is the current track index, verify seek-to-chapter works correctly for playlist entries

## 4. Details Screen

- [ ] 4.1 Open a YouTube search result that has a playlist; verify the chapter list in `AudiobookDetailsScreen` renders all fetched chapters with titles
- [ ] 4.2 Tap a chapter mid-list; verify playback starts at the correct chapter

## 5. Edge Cases & Graceful Degradation

- [ ] 5.1 Test a YouTube video with no playlist (`playlistId == null`): single chapter loads as before
- [ ] 5.2 Simulate a playlist fetch failure (e.g. bad ID); verify fallback to single video and no crash
- [ ] 5.3 Test a playlist with >100 videos; verify only first 100 chapters appear
