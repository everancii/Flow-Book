## Context

The app has a working 4read integration: search (`FourReadSearchService`), book details (`FourReadPageService`), and audio playback. The `Audiobook` model is shared between Archive.org and 4read results. Books are navigated to via `AudiobookDetailsScreen` with `isFourRead: true`. The top-100 page at `https://4read.org/top-100.html` lists 100 books as `linek` cards containing: cover image, article URL, title+author in `.linek__title`, genre in `.linek__meta`, and duration.

## Goals / Non-Goals

**Goals:**
- Fetch and parse `https://4read.org/top-100.html` into a ranked list of `Audiobook` objects
- Display the list in a dedicated screen with rank badge, cover, title, author
- Tap to open book in existing `AudiobookDetailsScreen` (4read mode)
- Add an entry point on the home screen (a "Top 100" banner/button in the 4read section)

**Non-Goals:**
- Caching / offline support (future work)
- Pagination (the page is a fixed 100 entries)
- Other websites' top lists (only 4read in this change)
- User-editable rankings

## Decisions

### 1. Reuse `Audiobook` model (not a new `FourReadTopEntry` model)
The existing `Audiobook` model has all required fields (`id` = article URL, `title`, `creator`/author, `coverImage`, `origin`). Using it means the existing `AudiobookItem` widget and navigation work without changes.
_Alternative_: New `FourReadTopEntry` model — rejected, unnecessary duplication.

### 2. New `FourReadTopBooksService` — mirrors `FourReadSearchService`
Use `package:http` (same as `FourReadSearchService`) with identical headers. Parse `.linek__title` for `"Title - Author"` format, `.linek__img img[src]` for cover. Rank is inferred from list order (1–100).
_Alternative_: Extend `FourReadSearchService` — rejected, different page structure and no pagination needed.

### 3. Dedicated BLoC + screen (`lib/screens/four_read_top/`)
Follows the existing pattern (search screen has its own BLoC). States: `TopBooksInitial`, `TopBooksLoading`, `TopBooksLoaded(books, cached)`, `TopBooksError`.
_Alternative_: Reuse search BLoC with a special event — rejected, different data source and no query state needed.

### 4. Entry point: home screen section row (not a tab)
Add a "4read Top 100" horizontal scroll row on the home screen, similar to existing recommendation rows. Tapping the section header navigates to the full screen.
_Alternative_: Add a tab to bottom navigation — rejected, too prominent for a single-site feature.

### 5. Title+author parsing
`.linek__title` contains `"Title - Author"` as a single string. Split on ` - ` (last occurrence) to separate title and author. Fall back to full string as title if no separator found.

## Risks / Trade-offs

- **HTML scraping fragility** → 4read may change markup. Mitigation: parse by class name (`linek__title`, `linek__img`, `linek__meta`), same approach as existing search service. Add graceful error state.
- **Title/author split ambiguity** — titles containing ` - ` will mis-parse author. Mitigation: split on last ` - ` occurrence.
- **No rank number in HTML** — rank is positional. If 4read reorders the page server-side between fetches the rank may shift. Mitigation: display the positional rank; acceptable for MVP.
- **Cover URL is relative** — must prepend `https://4read.org`. Already handled in `FourReadSearchService` pattern.
