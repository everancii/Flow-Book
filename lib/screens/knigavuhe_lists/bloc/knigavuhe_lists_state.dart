part of 'knigavuhe_lists_bloc.dart';

@immutable
sealed class KnigavuheListsState {}

class KnigavuheListsInitial extends KnigavuheListsState {}
class KnigavuheListsLoading extends KnigavuheListsState {}

class KnigavuheListsLoaded extends KnigavuheListsState {
  final List<Audiobook> newBooks;
  final List<Audiobook> popularBooks;
  final List<Audiobook> ratingBooks;

  KnigavuheListsLoaded({
    required this.newBooks,
    required this.popularBooks,
    required this.ratingBooks,
  });
}

class KnigavuheListsError extends KnigavuheListsState {
  final String message;
  KnigavuheListsError(this.message);
}
