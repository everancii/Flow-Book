part of 'soundbooks_lists_bloc.dart';

@immutable
sealed class SoundBooksListsState {}

class SoundBooksListsInitial extends SoundBooksListsState {}
class SoundBooksListsLoading extends SoundBooksListsState {}

class SoundBooksListsLoaded extends SoundBooksListsState {
  final List<Audiobook> latestBooks;
  final List<Audiobook> popularBooks;
  final List<Audiobook> topBooks;

  SoundBooksListsLoaded({
    required this.latestBooks,
    required this.popularBooks,
    required this.topBooks,
  });
}

class SoundBooksListsError extends SoundBooksListsState {
  final String message;
  SoundBooksListsError(this.message);
}
