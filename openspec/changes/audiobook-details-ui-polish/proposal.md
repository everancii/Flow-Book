## Why

The audiobook details screen has a cluttered action row and a flat play button that doesn't visually communicate its primary action. Moving the download button into the title bar (next to the favourite icon) frees up the hero area, and making the play button large and circular creates a clear call-to-action consistent with modern media players.

## What Changes

- Download button removed from the action area and added to the app-bar/title bar, positioned next to the existing favourite icon button.
- Play/resume button restyled to a large circular FAB-style button centred in the chapter/details section.
- The existing linear action row (which held play + download) is simplified or removed.

## Capabilities

### New Capabilities

- `details-title-bar-actions`: Download button lives in the app-bar alongside the favourite button, accessible without scrolling.
- `details-round-play-button`: Primary play button is a large circular button centred on the screen, replacing the current flat play button.

### Modified Capabilities

<!-- No existing spec-level behaviour changes -->

## Impact

- `lib/screens/audiobook_details/audiobook_details.dart` — app-bar actions and play button widget.
- `lib/screens/audiobook_details/` widgets (if play button is extracted).
- `lib/screens/download_audiobook/widget/download_button.dart` — reused in app-bar context; may need a compact variant.
- Visual regression on all book types (Librivox, YouTube, 4Read, local, downloaded).
