## ADDED Requirements

### Requirement: Download button appears in app-bar
The audiobook details screen SHALL display the `DownloadButton` widget as an action in the app-bar, positioned to the left of the favourite icon button.

#### Scenario: Download button visible in app-bar on all book types
- **WHEN** any audiobook details screen is opened (Librivox, YouTube, 4Read, local, or downloaded)
- **THEN** the `DownloadButton` is rendered inside the app-bar `actions` list, to the left of the favourite heart icon

#### Scenario: Download button not present in the body action card
- **WHEN** the details screen renders the main body
- **THEN** there is no separate download icon or card row beneath the cover art area
