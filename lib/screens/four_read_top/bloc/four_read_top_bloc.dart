import 'dart:async';

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_top_books_service.dart';
import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

part 'four_read_top_event.dart';
part 'four_read_top_state.dart';

class FourReadTopBloc extends Bloc<FourReadTopEvent, FourReadTopState> {
  final FourReadTopBooksService _service;

  FourReadTopBloc({FourReadTopBooksService? service})
      : _service = service ?? FourReadTopBooksService(),
        super(FourReadTopInitial()) {
    on<FetchTopBooks>(_onFetchTopBooks);
  }

  FutureOr<void> _onFetchTopBooks(
    FetchTopBooks event,
    Emitter<FourReadTopState> emit,
  ) async {
    emit(FourReadTopLoading());
    try {
      final books = await _service.fetchTopBooks();
      if (books.isEmpty) {
        emit(FourReadTopError('No books found.'));
      } else {
        emit(FourReadTopLoaded(books));
      }
    } catch (e) {
      emit(FourReadTopError(e.toString()));
    }
  }
}
