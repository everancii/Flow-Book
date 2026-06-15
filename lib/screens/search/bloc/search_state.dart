part of 'search_bloc.dart';

@immutable
sealed class SearchState {}

final class SearchInitial extends SearchState {}

class SearchLoading extends SearchState {}

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
