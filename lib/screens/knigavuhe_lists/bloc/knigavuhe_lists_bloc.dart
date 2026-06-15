import 'dart:async';

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/knigavuhe/knigavuhe_list_service.dart';
import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

part 'knigavuhe_lists_event.dart';
part 'knigavuhe_lists_state.dart';

class KnigavuheListsBloc extends Bloc<KnigavuheListsEvent, KnigavuheListsState> {
  final KnigavuheListService _service = KnigavuheListService();

  KnigavuheListsBloc() : super(KnigavuheListsInitial()) {
    on<FetchKnigavuheLists>(_onFetch);
  }

  Future<void> _onFetch(
    FetchKnigavuheLists event,
    Emitter<KnigavuheListsState> emit,
  ) async {
    emit(KnigavuheListsLoading());
    try {
      final results = await Future.wait([
        _service.fetchNewBooks(),
        _service.fetchPopularBooks(period: event.period),
        _service.fetchRatingBooks(period: event.period),
      ]);
      emit(KnigavuheListsLoaded(
        newBooks: results[0],
        popularBooks: results[1],
        ratingBooks: results[2],
      ));
    } catch (e) {
      emit(KnigavuheListsError(e.toString()));
    }
  }
}
