import 'dart:async';

import 'package:audiobookflow/resources/archive_api.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_search_service.dart';
import 'package:audiobookflow/resources/services/knigavuhe/knigavuhe_search_service.dart';
import 'package:audiobookflow/resources/services/soundbooks/soundbooks_search_service.dart';
import 'package:audiobookflow/resources/services/youtube/youtube_search_service.dart';
import 'package:audiobookflow/utils/app_events.dart';
import 'package:bloc/bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:meta/meta.dart';

part 'search_event.dart';
part 'search_state.dart';

enum SearchSourceSelection { all, librivox, youtube, archiveOrg, fourRead, knigavuhe, soundBooks }

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
  final SoundBooksSearchService _soundBooksSearch = SoundBooksSearchService();

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
    final includeSoundBooks =
        sourceSelection == SearchSourceSelection.soundBooks ||
            (sourceSelection == SearchSourceSelection.all &&
                _isSourceEnabled('soundbooks'));

    // Build (source name, future) pairs so each source can report its own
    // completion and we can emit incremental progress to the UI.
    final pending = <MapEntry<String, Future<_SearchBatchResult>>>[];
    if (includeLibrivox) {
      pending.add(MapEntry('LibriVox', _searchLibrivox(query, page)));
    }
    if (includeYoutube) {
      pending.add(MapEntry('YouTube', _searchYoutube(query, page)));
    }
    if (includeArchiveOrg) {
      pending.add(MapEntry('Archive.org', _searchArchiveOrg(query, page)));
    }
    if (includeFourRead) {
      pending.add(MapEntry('4Read', _searchFourRead(query, page)));
    }
    if (includeKnigavuhe) {
      pending.add(MapEntry('Knigavuhe', _searchKnigavuhe(query, page)));
    }
    if (includeSoundBooks) {
      pending.add(MapEntry('Sound-Books', _searchSoundBooks(query, page)));
    }

    final totalSources = pending.length;
    final resultsByName = <String, _SearchBatchResult>{};
    final completed = <int, bool>{
      for (var i = 0; i < pending.length; i++) i: false
    };
    var completedCount = 0;

    // Emit an initial (0/N) progress state for fresh searches.
    if (isFresh && totalSources > 0) {
      emit(SearchLoading(
        completedSources: 0,
        totalSources: totalSources,
        readySources: const [],
      ));
    }

    // Run all sources concurrently but count completions so we can report
    // real progress as each one resolves (keeping total latency at the max,
    // not the sum, of the source times).
    await Future.wait(pending.asMap().entries.map((e) async {
      final index = e.key;
      final entry = e.value;
      final result = await entry.value;
      resultsByName[entry.key] = result;
      completed[index] = true;
      completedCount++;
      if (isFresh) {
        final ready = <String>[
          for (var i = 0; i < pending.length; i++)
            if (completed[i] == true) pending[i].key,
        ];
        emit(SearchLoading(
          completedSources: completedCount,
          totalSources: totalSources,
          readySources: List<String>.unmodifiable(ready),
        ));
      }
    }));

    final librivoxResult =
        includeLibrivox ? resultsByName['LibriVox']! : const _SearchBatchResult(books: []);
    final youtubeResult =
        includeYoutube ? resultsByName['YouTube']! : const _SearchBatchResult(books: []);
    final archiveOrgResult = includeArchiveOrg
        ? resultsByName['Archive.org']!
        : const _SearchBatchResult(books: []);
    final fourReadResult =
        includeFourRead ? resultsByName['4Read']! : const _SearchBatchResult(books: []);
    final knigavuheResult = includeKnigavuhe
        ? resultsByName['Knigavuhe']!
        : const _SearchBatchResult(books: []);
    final soundBooksResult = includeSoundBooks
        ? resultsByName['Sound-Books']!
        : const _SearchBatchResult(books: []);
    final librivoxBooks = librivoxResult.books;
    final youtubeBooks = youtubeResult.books;
    final archiveOrgBooks = archiveOrgResult.books;
    final fourReadBooks = fourReadResult.books;
    final knigavuheBooks = knigavuheResult.books;
    final soundBooksBooks = soundBooksResult.books;
    final hasAnyResults = librivoxBooks.isNotEmpty ||
        youtubeBooks.isNotEmpty ||
        archiveOrgBooks.isNotEmpty ||
        fourReadBooks.isNotEmpty ||
        knigavuheBooks.isNotEmpty ||
        soundBooksBooks.isNotEmpty;
    final allErrors = [
      if (librivoxResult.error != null) librivoxResult.error!,
      if (youtubeResult.error != null) youtubeResult.error!,
      if (archiveOrgResult.error != null) archiveOrgResult.error!,
      if (fourReadResult.error != null) fourReadResult.error!,
      if (knigavuheResult.error != null) knigavuheResult.error!,
      if (soundBooksResult.error != null) soundBooksResult.error!,
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
            soundBooksAudiobooks: prev.soundBooksAudiobooks,
            hasMoreLibrivox: prev.hasMoreLibrivox,
            hasMoreYoutube: prev.hasMoreYoutube,
            hasMoreArchiveOrg: prev.hasMoreArchiveOrg,
            hasMoreFourRead: prev.hasMoreFourRead,
            hasMoreKnigavuhe: prev.hasMoreKnigavuhe,
            hasMoreSoundBooks: prev.hasMoreSoundBooks,
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
          soundBooksAudiobooks: soundBooksBooks,
          hasMoreLibrivox:
              includeLibrivox && librivoxBooks.length >= _librivoxRows,
          hasMoreYoutube:
              includeYoutube && youtubeBooks.length >= _youtubePageSize,
          hasMoreArchiveOrg: includeArchiveOrg && archiveOrgBooks.length >= 20,
          hasMoreFourRead: includeFourRead && fourReadBooks.length >= 15,
          hasMoreKnigavuhe: includeKnigavuhe && knigavuheBooks.length >= 20,
          hasMoreSoundBooks: includeSoundBooks && soundBooksBooks.length >= 10,
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
      final nextSoundBooksHasMore =
          prev.hasMoreSoundBooks && includeSoundBooks && soundBooksBooks.length >= 10;
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
          soundBooksAudiobooks: [
            ...prev.soundBooksAudiobooks,
            ...soundBooksBooks,
          ],
          hasMoreLibrivox: nextLibrivoxHasMore,
          hasMoreYoutube: nextYoutubeHasMore,
          hasMoreArchiveOrg: nextArchiveOrgHasMore,
          hasMoreFourRead: nextFourReadHasMore,
          hasMoreKnigavuhe: nextKnigavuheHasMore,
          hasMoreSoundBooks: nextSoundBooksHasMore,
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
          soundBooksAudiobooks: soundBooksBooks,
          hasMoreLibrivox:
              includeLibrivox && librivoxBooks.length >= _librivoxRows,
          hasMoreYoutube:
              includeYoutube && youtubeBooks.length >= _youtubePageSize,
          hasMoreArchiveOrg: includeArchiveOrg && archiveOrgBooks.length >= 20,
          hasMoreFourRead: includeFourRead && fourReadBooks.length >= 15,
          hasMoreKnigavuhe: includeKnigavuhe && knigavuheBooks.length >= 20,
          hasMoreSoundBooks: includeSoundBooks && soundBooksBooks.length >= 10,
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

  Future<_SearchBatchResult> _searchSoundBooks(
    String query,
    int page,
  ) async {
    try {
      final list = await _soundBooksSearch.search(
        query,
        page: page,
        pageSize: 10,
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
          defaultValue: ['librivox', 'youtube', 'archiveOrg', 'fourRead', 'knigavuhe', 'soundbooks']),
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
