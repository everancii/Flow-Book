part of 'search_bloc.dart';

@immutable
sealed class SearchState {}

final class SearchInitial extends SearchState {}

class SearchLoading extends SearchState {
  /// How many of the requested sources have finished so far.
  final int completedSources;

  /// Total number of sources being queried in parallel.
  final int totalSources;

  /// Human-readable names of the sources that have already resolved.
  final List<String> readySources;

  SearchLoading({
    this.completedSources = 0,
    this.totalSources = 0,
    this.readySources = const [],
  });

  SearchLoading copyWith({
    int? completedSources,
    int? totalSources,
    List<String>? readySources,
  }) {
    return SearchLoading(
      completedSources: completedSources ?? this.completedSources,
      totalSources: totalSources ?? this.totalSources,
      readySources: readySources ?? this.readySources,
    );
  }
}

class SearchSuccess extends SearchState {
  final List<Audiobook> librivoxAudiobooks;
  final List<Audiobook> youtubeAudiobooks;
  final List<Audiobook> archiveOrgAudiobooks;
  final List<Audiobook> fourReadAudiobooks;
  final List<Audiobook> knigavuheAudiobooks;
  final bool hasMoreLibrivox;
  final bool hasMoreYoutube;
  final bool hasMoreArchiveOrg;
  final bool hasMoreFourRead;
  final bool hasMoreKnigavuhe;

  SearchSuccess({
    required this.librivoxAudiobooks,
    required this.youtubeAudiobooks,
    required this.archiveOrgAudiobooks,
    required this.fourReadAudiobooks,
    required this.knigavuheAudiobooks,
    this.hasMoreLibrivox = false,
    this.hasMoreYoutube = false,
    this.hasMoreArchiveOrg = false,
    this.hasMoreFourRead = false,
    this.hasMoreKnigavuhe = false,
  });

  List<Audiobook> get audiobooks => [
        ...librivoxAudiobooks,
        ...youtubeAudiobooks,
        ...archiveOrgAudiobooks,
        ...fourReadAudiobooks,
        ...knigavuheAudiobooks,
      ];

  bool get hasMoreResults =>
      hasMoreLibrivox || hasMoreYoutube || hasMoreArchiveOrg || hasMoreFourRead || hasMoreKnigavuhe;
}

class SearchFailure extends SearchState {
  final String errorMessage;
  SearchFailure(this.errorMessage);
}
