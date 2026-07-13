import 'dart:async';

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/soundbooks/soundbooks_list_service.dart';
import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

part 'soundbooks_lists_event.dart';
part 'soundbooks_lists_state.dart';

class SoundBooksListsBloc
    extends Bloc<SoundBooksListsEvent, SoundBooksListsState> {
  final SoundBooksListService _service = SoundBooksListService();

  SoundBooksListsBloc() : super(SoundBooksListsInitial()) {
    on<FetchSoundBooksLists>(_onFetch);
  }

  Future<void> _onFetch(
    FetchSoundBooksLists event,
    Emitter<SoundBooksListsState> emit,
  ) async {
    emit(SoundBooksListsLoading());
    try {
      final results = await Future.wait([
        _service.fetchLatestBooks(),
        _service.fetchPopularCarousel(),
        _service.fetchTopBooks(),
      ]);
      emit(SoundBooksListsLoaded(
        latestBooks: results[0],
        popularBooks: results[1],
        topBooks: results[2],
      ));
    } catch (e) {
      emit(SoundBooksListsError(e.toString()));
    }
  }
}
