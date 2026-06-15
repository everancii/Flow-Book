part of 'audiobook_details_bloc.dart';

@immutable
sealed class AudiobookDetailsState {}

final class AudiobookDetailsInitial extends AudiobookDetailsState {}

final class AudiobookDetailsLoading extends AudiobookDetailsState {}

final class AudiobookDetailsLoaded extends AudiobookDetailsState {
  final List<AudiobookFile> audiobookFiles;
  final String? fourReadDescription;
  final String? knigavuheDescription;

  AudiobookDetailsLoaded(this.audiobookFiles, {this.fourReadDescription, this.knigavuheDescription});
}

final class AudiobookDetailsError extends AudiobookDetailsState {
  final String message;

  AudiobookDetailsError(this.message);
}

final class AudiobookDetailsFavourite extends AudiobookDetailsState {
  final bool isFavourite;

  AudiobookDetailsFavourite(this.isFavourite);
}
