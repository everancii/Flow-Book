## ADDED Requirements

### Requirement: Play button is large and circular
The audiobook details screen SHALL render the primary play/resume action as a large circular button (minimum 72×72 dp) centred horizontally in the content column, placed between the metadata section and the chapter list.

#### Scenario: Play button appears as a circle
- **WHEN** the audiobook details screen loads successfully and files are available
- **THEN** the play button is displayed as a filled circle with a play icon centred inside it

#### Scenario: Play button starts playback from history position
- **WHEN** the user taps the circular play button and the audiobook has a history entry
- **THEN** playback begins at the stored chapter index and position

#### Scenario: Play button starts playback from the beginning
- **WHEN** the user taps the circular play button and there is no history entry for the audiobook
- **THEN** playback begins at chapter index 0, position 0

### Requirement: Orange action card is removed
The orange `Card` action row that previously contained the download and play buttons SHALL be removed from the details screen body.

#### Scenario: No orange action card visible
- **WHEN** the audiobook details screen is open
- **THEN** there is no orange/amber coloured card row beneath the cover art
