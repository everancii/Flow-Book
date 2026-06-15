part of 'search_bloc.dart';

@immutable
sealed class SearchEvent {}

class EventSearchIconClicked extends SearchEvent {
  final String searchQuery;
  final SearchSourceSelection sourceSelection;

  EventSearchIconClicked(
    this.searchQuery, {
    this.sourceSelection = SearchSourceSelection.all,
  });
}

class EventLoadMoreResults extends SearchEvent {
  EventLoadMoreResults();
}
