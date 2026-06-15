## 1. Delete support files

- [x] 1.1 Delete `lib/screens/home/bloc/home_bloc.dart`
- [x] 1.2 Delete `lib/screens/home/bloc/home_event.dart`
- [x] 1.3 Delete `lib/screens/home/bloc/home_state.dart`
- [x] 1.4 Delete `lib/screens/home/widgets/my_audiobooks.dart`
- [x] 1.5 Delete `lib/resources/services/recommendation_service.dart`
- [x] 1.6 Delete `lib/screens/home/widgets/genre_grid.dart`
- [x] 1.7 Delete `lib/screens/home/constants/home_constants.dart`

## 2. Clean up `home.dart`

- [x] 2.1 Remove imports: `home_bloc.dart`, `my_audiobooks.dart`, `recommendation_service.dart`, `genre_grid.dart`, `home_constants.dart`
- [x] 2.2 Remove state fields: `_recommendationService`, `_recommendedGenresFuture`, `_popularBloc`, `_trendingBloc`, `_recommendedBloc`, `_popularCtrl`, `_trendingCtrl`, `_recommendedCtrl`
- [x] 2.3 Remove `initState` body lines that initialise the removed fields
- [x] 2.4 Remove `dispose` body lines that close/dispose the removed fields
- [x] 2.5 Remove the "Recommended genres section" sliver (`FutureBuilder` for `_recommendedGenresFuture`)
- [x] 2.6 Remove the "Featured sections" sliver (`_buildFeaturedSections()` call)
- [x] 2.7 Remove the "Browse Genres" header sliver and the `GenreGrid` sliver
- [x] 2.8 Delete the `_buildFeaturedSections()` method
- [x] 2.9 Delete the `_buildLazyLoadSection()` method

## 3. Verify

- [x] 3.1 Run `flutter analyze` — zero new errors or warnings
- [x] 3.2 Hot-reload the app and confirm home screen renders Welcome, History, Local Imports, YouTube Imports, 4Read Imports, Favourites, and footer guidance sections
- [x] 3.3 Confirm no network calls to Archive.org are made on home screen load (check device logs)
