import 'dart:async';

import 'package:audiobookflow/resources/archive_api.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_search_service.dart';
import 'package:audiobookflow/resources/services/knigavuhe/knigavuhe_search_service.dart';
import 'package:audiobookflow/resources/services/youtube/youtube_search_service.dart';
import 'package:audiobookflow/utils/app_events.dart';
import 'package:bloc/bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:meta/meta.dart';

part 'search_event.dart';
part 'search_state.dart';

enum SearchSourceSelection { all, librivox, youtube, archiveOrg, fourRead, knigavuhe }

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  static const int _librivoxRows = 10;
  static const int _youtubePageSize = 20;

  int currentPage = 1;

  /// The last raw query that was explicitly submitted (button press / Enter).
  String? lastQuery;

  SearchSourceSelection lastSourceSelection = SearchSourceSelection.all;

  final YoutubeSearchService _youtubeSearch = YoutubeSearchService();
  final FourReadSearchService _fourReadSearch = FourReadSearchService();
  final KnigavuheSearchService _knigavuheSearch = KnigavuheSearchService();

  StreamSubscription<void>? _langSub;

  SearchBloc() : super(SearchInitial()) {
    on<EventSearchIconClicked>(_onSearchSubmitted);
    on<EventLoadMoreResults>(_onLoadMore);

    // Refresh the current query on language change so LibriVox results stay in sync.
    _langSub = AppEvents.languagesChanged.stream.listen((_) {
      final q = lastQuery?.trim();
      if (q != null && q.isNotEmpty) {
        add(EventSearchIconClicked(
          q,
          sourceSelection: lastSourceSelection,
        ));
      }
    });
  }

  Future<void> _onSearchSubmitted(
    EventSearchIconClicked event,
    Emitter<SearchState> emit,
  ) async {
    currentPage = 1;
    lastQuery = event.searchQuery.trim();
    lastSourceSelection = event.sourceSelection;
    await _runSearch(
      emit,
      query: lastQuery!,
      sourceSelection: lastSourceSelection,
      page: currentPage,
      isFresh: true,
    );
  }

  Future<void> _onLoadMore(
    EventLoadMoreResults event,
    Emitter<SearchState> emit,
  ) async {
    final q = lastQuery?.trim();
    if (q == null || q.isEmpty) return;

    currentPage += 1;
    await _runSearch(
      emit,
      query: q,
      sourceSelection: lastSourceSelection,
      page: currentPage,
      isFresh: false,
    );
  }

  Future<void> _runSearch(
    Emitter<SearchState> emit, {
    required String query,
    required SearchSourceSelection sourceSelection,
    required int page,
    required bool isFresh,
  }) async {
    if (isFresh) {
      emit(SearchLoading());
    }

    final futures = <Future<_SearchBatchResult>>[];
    final includeLibrivox =
        sourceSelection == SearchSourceSelection.librivox ||
            (sourceSelection == SearchSourceSelection.all &&
                _isSourceEnabled('librivox'));
    final includeYoutube =
        sourceSelection == SearchSourceSelection.youtube ||
            (sourceSelection == SearchSourceSelection.all &&
                _isSourceEnabled('youtube'));
    final includeArchiveOrg =
        sourceSelection == SearchSourceSelection.archiveOrg ||
            (sourceSelection == SearchSourceSelection.all &&
                _isSourceEnabled('archiveOrg'));
    final includeFourRead =
        sourceSelection == SearchSourceSelection.fourRead ||
            (sourceSelection == SearchSourceSelection.all &&
                _isSourceEnabled('fourRead'));
    final includeKnigavuhe =
        sourceSelection == SearchSourceSelection.knigavuhe ||
            (sourceSelection == SearchSourceSelection.all &&
                _isSourceEnabled('knigavuhe'));

    if (includeLibrivox) {
      futures.add(_searchLibrivox(query, page));
    }
    if (includeYoutube) {
      futures.add(_searchYoutube(query, page));
    }
    if (includeArchiveOrg) {
      futures.add(_searchArchiveOrg(query, page));
    }
    if (includeFourRead) {
      futures.add(_searchFourRead(query, page));
    }
    if (includeKnigavuhe) {
      futures.add(_searchKnigavuhe(query, page));
    }

    final results = await Future.wait(futures);
    var resultIndex = 0;
    final librivoxResult = includeLibrivox
        ? results[resultIndex++]
        : const _SearchBatchResult(books: []);
    final youtubeResult = includeYoutube
        ? results[resultIndex++]
        : const _SearchBatchResult(books: []);
    final archiveOrgResult = includeArchiveOrg
        ? results[resultIndex++]
        : const _SearchBatchResult(books: []);
    final fourReadResult = includeFourRead
        ? results[resultIndex++]
        : const _SearchBatchResult(books: []);
    final knigavuheResult = includeKnigavuhe
        ? results[resultIndex++]
        : const _SearchBatchResult(books: []);
    final librivoxBooks = librivoxResult.books;
    final youtubeBooks = youtubeResult.books;
    final archiveOrgBooks = archiveOrgResult.books;
    final fourReadBooks = fourReadResult.books;
    final knigavuheBooks = knigavuheResult.books;
    final hasAnyResults = librivoxBooks.isNotEmpty ||
        youtubeBooks.isNotEmpty ||
        archiveOrgBooks.isNotEmpty ||
        fourReadBooks.isNotEmpty ||
        knigavuheBooks.isNotEmpty;
    final allErrors = [
      if (librivoxResult.error != null) librivoxResult.error!,
      if (youtubeResult.error != null) youtubeResult.error!,
      if (archiveOrgResult.error != null) archiveOrgResult.error!,
      if (fourReadResult.error != null) fourReadResult.error!,
      if (knigavuheResult.error != null) knigavuheResult.error!,
    ];

    if (!hasAnyResults && allErrors.isNotEmpty) {
      if (isFresh) {
        emit(SearchFailure(allErrors.join('\n')));
      } else if (state is SearchSuccess) {
        final prev = state as SearchSuccess;
        emit(
          SearchSuccess(
            librivoxAudiobooks: prev.librivoxAudiobooks,
            youtubeAudiobooks: prev.youtubeAudiobooks,
            archiveOrgAudiobooks: prev.archiveOrgAudiobooks,
            fourReadAudiobooks: prev.fourReadAudiobooks,
            knigavuheAudiobooks: prev.knigavuheAudiobooks,
            hasMoreLibrivox: prev.hasMoreLibrivox,
            hasMoreYoutube: prev.hasMoreYoutube,
            hasMoreArchiveOrg: prev.hasMoreArchiveOrg,
            hasMoreFourRead: prev.hasMoreFourRead,
            hasMoreKnigavuhe: prev.hasMoreKnigavuhe,
          ),
        );
      }
      return;
    }

    if (isFresh) {
      emit(
        SearchSuccess(
          librivoxAudiobooks: librivoxBooks,
          youtubeAudiobooks: youtubeBooks,
          archiveOrgAudiobooks: archiveOrgBooks,
          fourReadAudiobooks: fourReadBooks,
          knigavuheAudiobooks: knigavuheBooks,
          hasMoreLibrivox:
              includeLibrivox && librivoxBooks.length >= _librivoxRows,
          hasMoreYoutube:
              includeYoutube && youtubeBooks.length >= _youtubePageSize,
          hasMoreArchiveOrg: includeArchiveOrg && archiveOrgBooks.length >= 20,
          hasMoreFourRead: includeFourRead && fourReadBooks.length >= 15,
          hasMoreKnigavuhe: includeKnigavuhe && knigavuheBooks.length >= 20,
        ),
      );
      return;
    }

    final prev = state;
    if (prev is SearchSuccess) {
      final nextLibrivoxHasMore =
          prev.hasMoreLibrivox &&
          includeLibrivox &&
          librivoxBooks.length >= _librivoxRows;
      final nextYoutubeHasMore =
          prev.hasMoreYoutube &&
          includeYoutube &&
          youtubeBooks.length >= _youtubePageSize;
      final nextArchiveOrgHasMore =
          prev.hasMoreArchiveOrg && includeArchiveOrg && archiveOrgBooks.length >= 20;
      final nextFourReadHasMore =
          prev.hasMoreFourRead && includeFourRead && fourReadBooks.length >= 15;
      final nextKnigavuheHasMore =
          prev.hasMoreKnigavuhe && includeKnigavuhe && knigavuheBooks.length >= 20;
      emit(
        SearchSuccess(
          librivoxAudiobooks: [
            ...prev.librivoxAudiobooks,
            ...librivoxBooks,
          ],
          youtubeAudiobooks: [
            ...prev.youtubeAudiobooks,
            ...youtubeBooks,
          ],
          archiveOrgAudiobooks: [
            ...prev.archiveOrgAudiobooks,
            ...archiveOrgBooks,
          ],
          fourReadAudiobooks: [
            ...prev.fourReadAudiobooks,
            ...fourReadBooks,
          ],
          knigavuheAudiobooks: [
            ...prev.knigavuheAudiobooks,
            ...knigavuheBooks,
          ],
          hasMoreLibrivox: nextLibrivoxHasMore,
          hasMoreYoutube: nextYoutubeHasMore,
          hasMoreArchiveOrg: nextArchiveOrgHasMore,
          hasMoreFourRead: nextFourReadHasMore,
          hasMoreKnigavuhe: nextKnigavuheHasMore,
        ),
      );
    } else {
      emit(
        SearchSuccess(
          librivoxAudiobooks: librivoxBooks,
          youtubeAudiobooks: youtubeBooks,
          archiveOrgAudiobooks: archiveOrgBooks,
          fourReadAudiobooks: fourReadBooks,
          knigavuheAudiobooks: knigavuheBooks,
          hasMoreLibrivox:
              includeLibrivox && librivoxBooks.length >= _librivoxRows,
          hasMoreYoutube:
              includeYoutube && youtubeBooks.length >= _youtubePageSize,
          hasMoreArchiveOrg: includeArchiveOrg && archiveOrgBooks.length >= 20,
          hasMoreFourRead: includeFourRead && fourReadBooks.length >= 15,
          hasMoreKnigavuhe: includeKnigavuhe && knigavuheBooks.length >= 20,
        ),
      );
    }
  }

  Future<_SearchBatchResult> _searchLibrivox(
    String query,
    int page,
  ) async {
    try {
      final res = await ArchiveApi().searchAudiobook(query, page, _librivoxRows);
      final list = res.fold(
        (err) => throw Exception(err),
        (books) => books,
      );
      return _SearchBatchResult(books: list);
    } catch (e) {
      return _SearchBatchResult(books: const [], error: e.toString());
    }
  }

  Future<_SearchBatchResult> _searchYoutube(
    String query,
    int page,
  ) async {
    try {
      final list = await _youtubeSearch.search(
        query,
        page: page,
        pageSize: _youtubePageSize,
      );
      return _SearchBatchResult(books: list);
    } catch (e) {
      return _SearchBatchResult(books: const [], error: e.toString());
    }
  }

  Future<_SearchBatchResult> _searchArchiveOrg(
    String query,
    int page,
  ) async {
    try {
      final res = await ArchiveApi().searchArchiveOrg(query, page, 20);
      final list = res.fold(
        (err) => throw Exception(err),
        (books) => books,
      );
      return _SearchBatchResult(books: list);
    } catch (e) {
      return _SearchBatchResult(books: const [], error: e.toString());
    }
  }

  Future<_SearchBatchResult> _searchFourRead(
    String query,
    int page,
  ) async {
    try {
      final list = await _fourReadSearch.search(
        query,
        page: page,
        pageSize: 15,
      );
      return _SearchBatchResult(books: list);
    } catch (e) {
      return _SearchBatchResult(books: const [], error: e.toString());
    }
  }

  Future<_SearchBatchResult> _searchKnigavuhe(
    String query,
    int page,
  ) async {
    try {
      final list = await _knigavuheSearch.search(
        query,
        page: page,
        pageSize: 20,
      );
      return _SearchBatchResult(books: list);
    } catch (e) {
      return _SearchBatchResult(books: const [], error: e.toString());
    }
  }

  bool _isSourceEnabled(String source) {
    final box = Hive.box('settings');
    final enabled = List<String>.from(
      box.get('enabledSearchSources',
          defaultValue: ['librivox', 'youtube', 'archiveOrg', 'fourRead', 'knigavuhe']),
    );
    return enabled.contains(source);
  }

  @override
  Future<void> close() {
    _langSub?.cancel();
    _youtubeSearch.dispose();
    return super.close();
  }
}

class _SearchBatchResult {
  final List<Audiobook> books;
  final String? error;

  const _SearchBatchResult({
    required this.books,
    this.error,
  });
}
