## 1. Service Layer

- [ ] 1.1 Create `lib/resources/services/knigavuhe/knigavuhe_search_service.dart` with a `search(String query, {int page, int pageSize})` method that GETs `https://knigavuhe.org/search/?q=<encoded_query>&page=<page>` using `package:http` with the same User-Agent/headers as `FourReadSearchService`
- [ ] 1.2 Implement `_parseSearchResults(String html, {required int limit})` — split on book card markers (e.g. `class="book-item"`), extract title, author, cover image, description, duration, downloads, book ID, narrators, and genre
- [ ] 1.3 Implement `_match(String input, RegExp exp)` — extract first regex match group
- [ ] 1.4 Implement `_cleanText(String input)` — decode HTML entities (`&amp;`, `&quot;`, `&#039;`, `&nbsp;`)
- [ ] 1.5 Implement `_parseDuration(String text)` — parse Russian duration format "X часов Y минут" into total minutes, with fallback to 0
- [ ] 1.6 Prepend `https://knigavuhe.org` to relative cover image URLs
- [ ] 1.7 Return `List<Audiobook>` with fields mapped: `id` (book URL), `title`, `author`, `description` (include narrators), `lowQCoverImage`, `totalTime` (parsed duration), `downloads`, `rating` (if available), `language: 'uk'`, `origin: AppConstants.knigavuheDirName`

## 2. Constants

- [ ] 2.1 Add `static const knigavuheDirName = 'knigavuhe'` to `lib/utils/app_constants.dart`

## 3. Search BLoC

- [ ] 3.1 Add `knigavuhe` to `SearchSourceSelection` enum in `lib/screens/search/bloc/search_bloc.dart`
- [ ] 3.2 Add service instance field: `final KnigavuheSearchService _knigavuheSearch = KnigavuheSearchService()`
- [ ] 3.3 Implement `_searchKnigavuhe(String query, int page)` method returning `Future<_SearchBatchResult>` with try-catch pattern matching `_searchFourRead`
- [ ] 3.4 In `_runSearch()`, add knigavuhe inclusion check: `final includeKnigavuhe = sourceSelection == SearchSourceSelection.all || sourceSelection == SearchSourceSelection.knigavuhe`
- [ ] 3.5 Add knigavuhe to parallel search futures: `if (includeKnigavuhe) { futures.add(_searchKnigavuhe(query, page)); }`
- [ ] 3.6 Extract knigavuhe results from `futures` array after `Future.wait()` (maintain resultIndex pattern)
- [ ] 3.7 Add `knigavuheAudiobooks` and `hasMoreKnigavuhe` fields to `SearchSuccess` state constructor
- [ ] 3.8 Add knigavuhe error to `allErrors` array in error handling logic
- [ ] 3.9 Update `hasAnyResults` check to include `knigavuheBooks.isNotEmpty`
- [ ] 3.10 Add `hasMoreKnigavuhe: includeKnigavuhe && knigavuheBooks.length >= 20` (or actual page size)
- [ ] 3.11 Update fresh search emission to include knigavuhe fields
- [ ] 3.12 Update pagination append logic to include knigavuhe books with `hasMoreKnigavuhe` tracking
- [ ] 3.13 Add `dispose()` cleanup for `_knigavuheSearch` if needed

## 4. Search State

- [ ] 4.1 Add `final List<Audiobook> knigavuheAudiobooks` field to `SearchSuccess` state in `lib/screens/search/bloc/search_state.dart`
- [ ] 4.2 Add `final bool hasMoreKnigavuhe` field to `SearchSuccess` state
- [ ] 4.3 Update `SearchSuccess` constructor to accept and initialize knigavuhe fields
- [ ] 4.4 Update copy/constructor calls in `SearchBloc` to pass knigavuhe parameters

## 5. Search UI

- [ ] 5.1 Add "knigavuhe" filter option to search source selector UI (if UI source selector exists; otherwise, skip as all sources search by default)
- [ ] 5.2 Ensure `AudiobookItem` widget renders knigavuhe results correctly (reuse existing widget, no changes needed)
- [ ] 5.3 Verify search results screen displays knigavuhe books in appropriate section/row

## 6. Tests & Verification

- [ ] 6.1 Add unit test for `_parseDuration` covering: standard format ("2 часа 30 минут"), singular ("1 час 15 минут"), variations ("часов/часу"), and malformed input
- [ ] 6.2 Add unit test for `_cleanText` covering HTML entity decoding
- [ ] 6.3 Add unit test for `_parseSearchResults` using minimal HTML fixture with 2-3 book cards
- [ ] 6.4 Add integration test for `KnigavuheSearchService.search()` with mock HTTP response
- [ ] 6.5 Add BLoC test for knigavuhe search execution in `SearchBloc`
- [ ] 6.6 Manually verify on device/emulator:
  - Search with "all" sources → knigavuhe results appear
  - Search with knigavuhe-only source → only knigavuhe results appear
  - Pagination works ("Load More" loads more knigavuhe results)
  - Tapping knigavuhe result navigates correctly (even if details screen not yet implemented)
  - Error handling: network failure shows appropriate error state
  - Duration parsing displays correctly in UI

## 7. Documentation

- [ ] 7.1 Update `CLAUDE.md` or project README with knigavuhe source information (if documentation exists)
