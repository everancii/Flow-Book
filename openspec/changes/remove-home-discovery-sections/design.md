## Context

The home screen (`lib/screens/home/home.dart`) is a `CustomScrollView` with multiple `SliverToBoxAdapter` children. Four of those children implement discovery sections:

1. **Recommended for You** — a `FutureBuilder` driven by `RecommendationService.getRecommendedGenres()`, rendered via `_buildLazyLoadSection` → `MyAudiobooks` with `fetchType: genre`.
2. **Popular All Time** — `MyAudiobooks` with `fetchType: popular`, driven by `_popularBloc`.
3. **Trending This Week** — `MyAudiobooks` with `fetchType: popularOfWeek`, driven by `_trendingBloc`.
4. **Browse Genres** — a section header + `GenreGrid` widget with tappable genre chips that push `/genre_audiobooks`.

Supporting code that exists solely for these sections:
- `HomeBloc` (`lib/screens/home/bloc/`) — internet Archive API wrapper; only ever instantiated in `home.dart` for the three `MyAudiobooks` widgets.
- `MyAudiobooks` (`lib/screens/home/widgets/my_audiobooks.dart`) — horizontal scroll list widget backed by `HomeBloc`.
- `RecommendationService` (`lib/resources/services/recommendation_service.dart`) — only imported in `home.dart`.
- `GenreGrid` (`lib/screens/home/widgets/genre_grid.dart`) — only used in `home.dart`.
- `HomeConstants` (`lib/screens/home/constants/home_constants.dart`) — only referenced from `genre_grid.dart` and the genres sliver in `home.dart`.

The `/genre_audiobooks` route and `GenreAudiobooks` screen are **also** reachable from `audiobook_details.dart`, so they are **not** removed.

## Goals / Non-Goals

**Goals:**
- Remove all four discovery sections and their associated slivers from `home.dart`.
- Delete all files that exist solely to support those sections.
- Leave the home screen compiling, rendering correctly, and containing no dead imports or dead state fields.

**Non-Goals:**
- Removing the `/genre_audiobooks` route or screen (still linked from audiobook details).
- Touching the footer guidance text widget (`_buildGenreSections`) — it is not a discovery section.
- Changing any other screen, service, or navigation entry point.

## Decisions

### 1 — Delete supporting files outright, do not gate behind a flag

The four sections are being removed permanently. Keeping dead code behind feature flags adds maintenance cost for no benefit. All exclusively-owned files (`HomeBloc`, `MyAudiobooks`, `RecommendationService`, `GenreGrid`, `HomeConstants`) will be deleted.

*Alternative considered*: Keep files but just hide widgets — rejected because it leaves unreachable dead code.

### 2 — Edit `home.dart` in place; do not extract a new widget

The cleanup is a straight deletion of sliver children and their backing fields. No new abstraction is needed.

### 3 — Keep `HomeConstants` file deletion isolated

`HomeConstants` contains nothing shared outside the home genres section. Deleting the file is safe. If constants are ever needed again they can be recreated.

## Risks / Trade-offs

- **Risk**: `HomeBloc` file also contains `AudiobooksFetchType` enum used by `MyAudiobooks`. If deleted together the enum disappears — but since both files are deleted in the same change this is safe. → **Mitigation**: Delete both files in the same task; verify `dart pub get` + analysis pass.
- **Risk**: A future developer may want to re-add a discovery section and find the infrastructure gone. → **Mitigation**: Git history preserves the deleted code; this is acceptable.
- **Trade-off**: Removing `RecommendationService` also removes the Hive box `recommened_audiobooks_box`. The box was write-only from the user's perspective (no UI to manage it), so no data migration is required.

## Migration Plan

1. Delete the five support files.
2. Edit `home.dart`: remove imports, state fields, `initState`/`dispose` lines, and four sliver blocks.
3. Run `flutter analyze` to confirm zero new errors.
4. Hot-reload and visually verify the home screen renders the remaining sections (Welcome, History, Local, YouTube, 4Read, Favourites, footer guidance).
