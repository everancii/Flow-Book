part of 'four_read_top_bloc.dart';

@immutable
sealed class FourReadTopState {}

final class FourReadTopInitial extends FourReadTopState {}

final class FourReadTopLoading extends FourReadTopState {}

final class FourReadTopLoaded extends FourReadTopState {
  final List<Audiobook> books;
  FourReadTopLoaded(this.books);
}

final class FourReadTopError extends FourReadTopState {
  final String message;
  FourReadTopError(this.message);
}
