## Context

The app has 3 working search sources: LibriVox (`ArchiveApi`), YouTube (`YoutubeSearchService`), and 4read (`FourReadSearchService`). All follow the same pattern: a service with `search(query, page, pageSize)` returning `List<Audiobook>`, wired in parallel in `SearchBloc`, results displayed in `SearchSuccess` state. The `Audiobook` model is shared across sources. knigavuhe.org at `https://knigavuhe.org/search/?q=<query>&page=<page>` returns HTML with ~20 book cards per page containing: cover image, title, author, description, genre, narrators, duration, downloads, and book link.

## Goals / Non-Goals

**Goals:**
- Fetch and parse knigavuhe.org search results into `Audiobook` objects
- Display results in existing search UI (same as YouTube/4read)
- Support pagination (page parameter in URL)
- Handle search errors gracefully (same pattern as existing sources)

**Non-Goals:**
- knigavuhe book details/player integration (future work)
- Caching/offline support
- knigavuhe-specific features (top lists, genres)
- User authentication on knigavuhe.org

## Decisions

### 1. Follow 4read pattern (HTML scraping with http package)
Use `package:http` with identical headers (User-Agent, Accept, Referer). Parse HTML by splitting on known card markers and extracting fields via regex. Same approach as `FourReadSearchService._parseSearchResults()`.
*Alternative* API → none available publicly.
*Alternative* WebView → rejected, overkill for simple HTML fetch.

### 2. New `KnigavuheSearchService` in `lib/resources/services/knigavuhe/`
Dedicated service mirroring `FourReadSearchService` structure. Methods:
- `search(query, page, pageSize)` → `Future<List<Audiobook>>`
- `_parseSearchResults(html, limit)` → `List<Audiobook>`
- `_match(input, regex)` → `String`
- `_cleanText(input)` → `String`
*Alternative* extend existing service → rejected, different domain and parsing logic.

### 3. Search URL structure
`https://knigavuhe.org/search/?q=<encoded_query>&page=<page>`
- Query parameter: URL-encoded UTF-8 string
- Page parameter: 1-indexed (default 1)
- Results per page: ~20 (server-side, no client control)

### 4. Parse strategy
Based on browse analysis, book cards contain:
- Title: `class="book-item-title"` or `h3` tag
- Author: `class="book-item-author"` or nearby span
- Cover: `img` tag inside card, `src` attribute
- Description: `class="book-item-description"` or `p` tag
- Duration: text pattern "X часов Y минут"
- Downloads: numeric value in card
- Book ID: extracted from `href` attribute
- Narrators: comma-separated list in card
- Genre: `class="genre"` tag

Parse by:
1. Split HTML on `class="book-item"` or similar marker
2. For each card, extract fields via regex
3. Clean HTML entities (`&amp;`, `&quot;`, etc.)
4. Normalize URLs (prepend base if relative)
5. Map to `Audiobook.fromMap()` with `origin: AppConstants.knigavuheDirName`

### 5. Error handling
Follow existing pattern:
- HTTP non-200 → throw exception
- Parse failures → return empty list (log warning)
- Network errors → catch, return empty list, store error in `_SearchBatchResult`
- SearchBloc displays error only if ALL sources fail

### 6. SearchSourceSelection enum
Add `knigavuhe` as fourth option:
```dart
enum SearchSourceSelection { all, librivox, youtube, fourRead, knigavuhe }
```
- `all` includes all 4 sources
- Individual selection disables other sources
- UI needs new filter option

### 7. SearchBloc wiring
Mirror YouTube/4read pattern:
- Add service instance: `final KnigavuheSearchService _knigavuheSearch`
- Add `_searchKnigavuhe(query, page)` method returning `_SearchBatchResult`
- In `_runSearch()`, add knigavuhe branch:
  ```dart
  final includeKnigavuhe = sourceSelection == SearchSourceSelection.all ||
      sourceSelection == SearchSourceSelection.knigavuhe;
  if (includeKnigavuhe) {
    futures.add(_searchKnigavuhe(query, page));
  }
  ```
- Extract results from `futures` array after `Future.wait()`
- Add state fields: `knigavuheAudiobooks`, `hasMoreKnigavuhe` (same pattern)

### 8. State management
Add to `SearchSuccess` state:
```dart
final List<Audiobook> knigavuheAudiobooks;
final bool hasMoreKnigavuhe;
```
Constructor and fields follow existing pattern. UI renders via existing `AudiobookItem` widget.

### 9. Duration parsing
knigavuhe uses Russian format: "X часов Y минут" or "X час Y минут".
Parse strategy:
1. Extract numbers via regex
2. Convert to total minutes: `(hours * 60) + minutes`
3. Store as integer or Duration object
4. Fall back to 0 if parse fails

### 10. Language detection
knigavuhe is primarily Ukrainian/Russian. Set `language: 'uk'` or `'ru'` based on:
- Domain analysis (.org = international, but content is Slavic)
- Default to `'uk'` (Ukrainian) as site name suggests
- Future work: auto-detect from content

### 11. Cover image handling
- URLs may be relative or absolute
- Prepend `https://knigavuhe.org` if relative
- Fall back to empty string if missing
- Use `lowQCoverImage` field (same as 4read)

### 12. Narrators mapping
knigavuhe lists multiple narrators per book. `Audiobook` model has `creator` (author) but no dedicated narrator field.
Options:
- Store narrators in `description` field
- Ignore for MVP (focus on author)
- Future: extend model for multi-narrator support

Decision: Store in `description` for MVP, e.g. "Narrated by: X, Y, Z".

## Risks / Trade-offs

- **HTML scraping fragility** → knigavuhe may change markup. Mitigation: parse by class names/structure, add graceful error handling.
- **Duration parsing language-specific** → Russian format only. Mitigation: regex handles variations (час/часов/часу), fallback to 0.
- **No page size control** → server returns ~20 results, client can't change. Mitigation: accept default, handle variable counts.
- **Relative URLs** → cover images may be relative paths. Mitigation: prepend base URL, validate absolute.
- **Narrator field missing** → model lacks dedicated narrator field. Mitigation: store in description for MVP, extend model later.
- **Language detection heuristic** → defaulting to 'uk' may be wrong. Mitigation: observable, can be refined post-launch.

## Open Questions

- Should we add a filter UI for knigavuhe-specific genres? (deferred)
- Should we implement book details/player for knigavuhe? (future change)
- How to handle knigavuhe auth if required later? (deferred)
