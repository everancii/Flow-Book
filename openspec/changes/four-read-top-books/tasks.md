## 1. Service Layer

- [x] 1.1 Create `lib/resources/services/four_read/four_read_top_books_service.dart` with a `fetchTopBooks()` method that GETs `https://4read.org/top-100.html` using `package:http` with the same User-Agent/headers as `FourReadSearchService`
- [x] 1.2 Implement `_parseTopBooks(String html)` — split on `linek` card boundaries, extract `.linek__title` (title+author), `.linek__img img[src]` (cover), and the `<a href>` article URL for each card
- [x] 1.3 Implement `_splitTitleAuthor(String combined)` — split on last ` - ` occurrence; return `(title, author)` tuple
- [x] 1.4 Prepend `https://4read.org` to relative cover image URLs
- [x] 1.5 Return `List<Audiobook>` with `origin` set to `AppConstants.fourReadDirName` and positional rank stored in an available field (e.g. `track` or a dedicated `rank` field if added)

## 2. BLoC

- [x] 2.1 Create `lib/screens/four_read_top/bloc/four_read_top_bloc.dart` with states: `FourReadTopInitial`, `FourReadTopLoading`, `FourReadTopLoaded(List<Audiobook> books)`, `FourReadTopError(String message)`
- [x] 2.2 Create `lib/screens/four_read_top/bloc/four_read_top_event.dart` with `FetchTopBooks` event
- [x] 2.3 Create `lib/screens/four_read_top/bloc/four_read_top_state.dart`
- [x] 2.4 Implement `on<FetchTopBooks>` handler

## 3. Screen & UI

- [x] 3.1 Create `lib/screens/four_read_top/four_read_top_screen.dart` — scaffold with `BlocProvider<FourReadTopBloc>`, dispatch `FetchTopBooks` on `initState`
- [x] 3.2 Build list state: `ListView.builder` (or `SliverList`) rendering each book as a row with rank badge (`#N` in a coloured circle), cover thumbnail (`LowAndHighImage` or `Image.network`), title, and author
- [x] 3.3 Build loading state: shimmer list skeleton (consistent with rest of app)
- [x] 3.4 Build error state: error message + "Retry" button that re-dispatches `FetchTopBooks`
- [x] 3.5 Build empty state: "No books found" message

## 4. Navigation

- [x] 4.1 Add a named route `/four_read_top` (or equivalent) to the app router that instantiates `FourReadTopScreen`
- [x] 4.2 Ensure tapping a book item navigates to `AudiobookDetailsScreen` with `isFourRead: true` and the article URL as ID — reuse the same `Navigator.pushNamed` call pattern as `AudiobookItem`

## 5. Home Screen Entry Point

- [x] 5.1 Locate the 4read section in `lib/screens/home/home.dart` (or create one if absent) and add a "4read Top 100" tappable card/button
- [x] 5.2 Wire the tap to navigate to `/four_read_top`

## 6. Tests & Verification

- [x] 6.1 Add a unit test for `_splitTitleAuthor` covering: standard case, no separator, and multiple separators
- [x] 6.2 Add a unit test for `_parseTopBooks` using a minimal HTML fixture with 2–3 linek cards
- [ ] 6.3 Manually verify on device: home entry point visible → navigates to list → 100 items render with covers and ranks → tapping a book opens AudiobookDetailsScreen correctly
