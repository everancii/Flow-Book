## Why

Users searching for audiobooks can only access LibriVox, YouTube, and 4read sources. knigavuhe.org hosts a large catalog of Ukrainian/Russian audiobooks (17,600+ fantasy titles, 11,000+ prose titles) with narrator information and download counts. Adding it as a search source significantly expands the catalog, especially for Slavic-language content.

## What Changes

- Add **knigavuhe.org** as a fourth search source in the search screen
- Implement `KnigavuheSearchService` to search `https://knigavuhe.org/search/?q=<query>&page=<page>`
- Parse HTML response to extract: book ID, title, author, description, cover image, duration, downloads, rating, narrators
- Add `knigavuhe` option to `SearchSourceSelection` enum
- Wire parallel search execution in `SearchBloc` (same pattern as YouTube/4read)
- Display knigavuhe results in existing search UI (no new screens)

## Capabilities

### New Capabilities
- `knigavuhe-search`: Search knigavuhe.org catalog via query string; paginate results; parse book cards into `Audiobook` model

### Modified Capabilities
- `multi-source-search`: Add knigavuhe as fourth parallel search source alongside LibriVox, YouTube, 4read

## Impact

- **New service**: `KnigavuheSearchService` — HTTP fetch + HTML parse of `https://knigavuhe.org/search/`
- **SearchBloc**: Add knigavuhe parallel search, error handling, state fields (`knigavuheAudiobooks`, `hasMoreKnigavuhe`)
- **SearchSourceSelection**: Add `knigavuhe` enum value
- **AppConstants`: Add `knigavuheDirName` constant
- **Search UI**: Reuse existing `AudiobookItem` widget (no new components)
- **No breaking changes** to existing screens or data models
