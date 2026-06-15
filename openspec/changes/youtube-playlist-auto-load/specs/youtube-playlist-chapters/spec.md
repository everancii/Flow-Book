## ADDED Requirements

### Requirement: Playlist chapters auto-loaded from search result
When a YouTube search result video has an associated playlist, the system SHALL fetch all videos in that playlist (up to 100) and return them as ordered chapters on the resulting `Audiobook`, so the user can play all chapters without performing additional searches.

#### Scenario: Video belongs to a playlist
- **WHEN** a user taps a YouTube search result whose video has a non-null `playlistId`
- **THEN** the app fetches all videos in that playlist (capped at 100)
- **AND** the returned `Audiobook.files` contains one entry per playlist video in playlist order
- **AND** each entry includes the video ID, title, and duration

#### Scenario: Video does not belong to a playlist
- **WHEN** a user taps a YouTube search result whose video has no `playlistId`
- **THEN** the app returns the single video as the only chapter (existing behaviour preserved)

#### Scenario: Playlist fetch fails
- **WHEN** fetching playlist videos throws an exception (e.g. rate limiting, network error)
- **THEN** the app falls back to the single video as the only chapter
- **AND** no error is shown to the user for the playlist fetch failure specifically

#### Scenario: Playlist has more than 100 videos
- **WHEN** a playlist contains more than 100 videos
- **THEN** only the first 100 videos are loaded as chapters
- **AND** the app does not attempt to fetch beyond the 100-video cap
