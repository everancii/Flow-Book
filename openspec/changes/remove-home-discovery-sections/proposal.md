## Why

The home screen is cluttered with four discovery sections — "Recommended for You", "Popular All Time", "Trending This Week", and "Browse Genres" — that add visual noise, slow initial render, and distract users from their primary goal of reaching their current audiobook. Removing them simplifies the UI and reduces unnecessary network calls.

## What Changes

- Remove the **Recommended for You** horizontal scroll section from the home screen.
- Remove the **Popular All Time** horizontal scroll section from the home screen.
- Remove the **Trending This Week** horizontal scroll section from the home screen.
- Remove the **Browse Genres** grid/section from the home screen.
- Delete or gate any service/bloc logic that exists solely to power these sections.
- Remove any navigation routes or bottom-sheet flows that are exclusively entered from these sections.

## Capabilities

### New Capabilities
<!-- None introduced — this is a removal change -->

### Modified Capabilities
- `home-screen`: The home screen no longer renders the four discovery sections; only the remaining content (library, 4Read import strip, mini-player, etc.) is displayed.

## Impact

- `lib/screens/home/` — widget files containing the four section widgets will be deleted or stripped.
- Any BLoC/service files that exist solely to fetch data for these sections (e.g., recommendations, trending, genre list) will be removed.
- `lib/main.dart` / router — any routes reachable only from these sections may be removed.
- No API contract changes; purely UI and state-layer removal.
- No breaking changes to navigation for screens reachable from other entry points.
