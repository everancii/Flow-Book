## Why

Users browsing 4read content have no way to discover the most popular audiobooks without leaving the app. A "Top 100" screen surfaces 4read's curated popularity ranking directly in the app, giving users an instant entry point to high-quality content.

## What Changes

- Add a dedicated **Top 100** screen that fetches and displays the ranked list from `https://4read.org/top-100.html`
- Add a **Top 100** entry point on the 4read section of the home screen (or as a navigation shortcut)
- Parse the `linek` card HTML to extract: rank (positional), title+author, cover image URL, and article URL
- Tapping a book opens the existing `AudiobookDetailsScreen` in 4read mode

## Capabilities

### New Capabilities
- `four-read-top-books`: Fetch, parse, and display the 4read Top 100 ranked list; navigate to book details from it

### Modified Capabilities
- `four-read-home-entry`: Add a Top 100 entry point to the existing 4read home / discovery surface

## Impact

- **New service**: `FourReadTopBooksService` — HTTP fetch + HTML parse of `https://4read.org/top-100.html`
- **New screen**: `lib/screens/four_read_top/` with its own BLoC
- **New model**: `FourReadTopEntry` (rank, title, author, coverUrl, articleUrl)
- **Home screen**: Minor addition of a "Top 100" card/button in the 4read section
- **Navigation**: New named route for the top-books screen
- **No breaking changes** to existing screens or data models
