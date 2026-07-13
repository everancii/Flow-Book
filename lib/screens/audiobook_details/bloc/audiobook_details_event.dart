part of 'audiobook_details_bloc.dart';

@immutable
sealed class AudiobookDetailsEvent {}

class FetchAudiobookDetails extends AudiobookDetailsEvent {
  final String audiobookId;
  final bool isDownload;
  final bool isYoutube;
  final bool isYoutubeSearch; // true = search result, no saved files
  final bool isLocal;
  final bool isFourRead;
  final bool isKnigavuhe;
  final bool isSoundBooks;

  FetchAudiobookDetails(
    this.audiobookId,
    this.isDownload,
    this.isYoutube, {
    this.isYoutubeSearch = false,
    this.isLocal = false,
    this.isFourRead = false,
    this.isKnigavuhe = false,
    this.isSoundBooks = false,
  });
}

class FavouriteIconButtonClicked extends AudiobookDetailsEvent {
  final Audiobook audiobook;

  FavouriteIconButtonClicked(this.audiobook);
}

class GetFavouriteStatus extends AudiobookDetailsEvent {
  final Audiobook audiobook;

  GetFavouriteStatus(this.audiobook);
}

/// Probe real durations for 4read tracks that have no duration metadata.
class ProbeFourReadDurations extends AudiobookDetailsEvent {
  final List<AudiobookFile> files;
  ProbeFourReadDurations(this.files);
}
