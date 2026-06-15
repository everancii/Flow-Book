import 'dart:async';

import 'package:audiobookflow/utils/app_logger.dart';
import 'package:bloc/bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audiobookflow/resources/archive_api.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/services/knigavuhe/knigavuhe_detail_service.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_audiobook_notifier.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_guard.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_telemetry.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_page_service.dart';
import 'package:meta/meta.dart';

part 'audiobook_details_event.dart';
part 'audiobook_details_state.dart';

class AudiobookDetailsBloc
    extends Bloc<AudiobookDetailsEvent, AudiobookDetailsState> {
  StreamSubscription? _favouriteBoxSubscription;
  String? _currentAudiobookId;
  AudiobookDetailsBloc() : super(AudiobookDetailsInitial()) {
    on<FetchAudiobookDetails>((event, emit) => fetchAudiobookDetails(
          event,
          emit,
          event.audiobookId,
          event.isDownload,
          event.isYoutube,
          event.isLocal,
          event.isFourRead,
          event.isKnigavuhe,
        ));
    on<FavouriteIconButtonClicked>(favouriteIconButtonClicked);
    on<GetFavouriteStatus>(getFavouriteStatus);
    on<ProbeFourReadDurations>(probeFourReadDurations);

    final box = Hive.box('favourite_audiobooks_box');
    _favouriteBoxSubscription = box.watch().listen((event) {
      if (_currentAudiobookId != null && event.key == _currentAudiobookId) {
        add(GetFavouriteStatus(Audiobook.fromMap(event.value ?? {})));
      }
    });
  }

  FutureOr<void> fetchAudiobookDetails(
    FetchAudiobookDetails event,
    Emitter<AudiobookDetailsState> emit,
    String id,
    bool isDownload,
    bool isYoutube,
    bool isLocal,
    bool isFourRead,
    bool isKnigavuhe,
  ) async {
    emit(AudiobookDetailsLoading());
    AppLogger.debug('fetching audiobook details for id: $id');
    AppLogger.debug('isDownload: $isDownload');
    AppLogger.debug('isYoutube: $isYoutube');
    AppLogger.debug('isYoutubeSearch: ${event.isYoutubeSearch}');
    AppLogger.debug('isLocal: $isLocal');
    AppLogger.debug('isFourRead: $isFourRead');
    Either<String, List<AudiobookFile>> audiobookFiles;
    try {
      if (isDownload) {
        AppLogger.debug('fetching audiobook files from downloaded files');
        audiobookFiles = await AudiobookFile.fromDownloadedFiles(id);
      } else if (event.isYoutubeSearch) {
        AppLogger.debug(
            'fetching audiobook files from YouTube video ID (search result)');
        audiobookFiles = await AudiobookFile.fromYoutubeVideoId(id);
      } else if (isYoutube) {
        AppLogger.debug('fetching audiobook files from imported files');
        audiobookFiles = await AudiobookFile.fromYoutubeFiles(id);
      } else if (isLocal) {
        AppLogger.debug('fetching audiobook files from local files');
        audiobookFiles = await AudiobookFile.fromLocalFiles(id);
      } else if (isFourRead) {
        final validationFailure = FourReadOpenGuard.validateArticleUrl(id);
        if (validationFailure != null) {
          FourReadOpenTelemetry.validationFailure(
            stage: 'details_fetch',
            reason: validationFailure.code,
            audiobookId: id,
          );
          emit(
            AudiobookDetailsError(
              'This 4Read title cannot be opened right now. Please retry or choose another title.',
            ),
          );
          return;
        }
        final normalizedId = FourReadOpenGuard.normalizeArticleUrl(id);
        if (normalizedId == null) {
          FourReadOpenTelemetry.validationFailure(
            stage: 'details_fetch',
            reason: 'normalized_article_missing',
            audiobookId: id,
          );
          emit(
            AudiobookDetailsError(
              'This 4Read title cannot be opened right now. Please retry or choose another title.',
            ),
          );
          return;
        }
        FourReadOpenTelemetry.openAttempt(
          stage: 'details_fetch',
          audiobookId: normalizedId,
        );

        if (FourReadAudiobookNotifier()
            .isAudiobookAlreadyImported(normalizedId)) {
          AppLogger.debug('fetching audiobook files from 4Read imported files');
          audiobookFiles = await AudiobookFile.fromFourReadFiles(normalizedId);
        } else {
          AppLogger.debug('fetching audiobook files directly from 4Read page');
          audiobookFiles =
              await AudiobookFile.fromFourReadPageUrl(normalizedId);
        }
      } else if (isKnigavuhe) {
        AppLogger.debug('fetching audiobook files from knigavuhe');
        final result = await KnigavuheDetailService().getAudiobookFiles(id);
        return result.fold(
          (l) {
            emit(AudiobookDetailsError(l));
            return;
          },
          (r) {
            if (r.files.isEmpty) {
              emit(AudiobookDetailsError(
                'No audiobook files were found for this title.',
              ));
              return;
            }
            emit(AudiobookDetailsLoaded(r.files,
                knigavuheDescription: r.description));
          },
        );
      } else {
        audiobookFiles = await ArchiveApi().getAudiobookFiles(id);
      }

      audiobookFiles.fold((l) {
        emit(AudiobookDetailsError(l));
      }, (r) {
        if (r.isEmpty) {
          emit(AudiobookDetailsError(
            'No audiobook files were found for this title.',
          ));
          return;
        }
        final desc =
            isFourRead ? FourReadPageService.descriptionCache[id] ?? '' : null;
        emit(AudiobookDetailsLoaded([...r],
            fourReadDescription: desc?.isEmpty == true ? null : desc));
        // Probe real durations for 4read tracks that have no metadata.
        if (isFourRead && r.any((f) => (f.length ?? 0) <= 0)) {
          add(ProbeFourReadDurations([...r]));
        }
      });
    } catch (e) {
      AppLogger.debug('Error coming from fetchAudiobookDetails bloc: $e');
      if (isFourRead) {
        FourReadOpenTelemetry.runtimeFailure(
          stage: 'details_fetch',
          error: e,
          audiobookId: id,
        );
      }
      emit(AudiobookDetailsError(
        isFourRead
            ? 'Unable to open this 4Read title right now. Please retry or choose another title.'
            : 'Failed to load audiobook details: $e',
      ));
    }
  }

  /// Probes the real duration of each 4read track that has no duration
  /// metadata, using just_audio's URL loader (reads audio headers without
  /// downloading the full file), then re-emits the track list with durations.
  FutureOr<void> probeFourReadDurations(
    ProbeFourReadDurations event,
    Emitter<AudiobookDetailsState> emit,
  ) async {
    final files = List<AudiobookFile>.from(event.files);
    var updated = false;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if ((f.length ?? 0) > 0 || f.url == null) continue;
      final player = AudioPlayer();
      try {
        final dur =
            await player.setUrl(f.url!).timeout(const Duration(seconds: 8));
        if (dur != null && dur.inSeconds > 0) {
          files[i] = f.copyWithLength(dur.inSeconds.toDouble());
          updated = true;
        }
      } catch (e) {
        AppLogger.debug('[probeDuration] track $i failed: $e');
      } finally {
        await player.dispose();
      }
    }
    if (updated) {
      // Preserve description already surfaced in the previous state.
      final prevDesc = state is AudiobookDetailsLoaded
          ? (state as AudiobookDetailsLoaded).fourReadDescription
          : null;
      emit(AudiobookDetailsLoaded(files, fourReadDescription: prevDesc));
    }
  }

  FutureOr<void> getFavouriteStatus(
    GetFavouriteStatus event,
    Emitter<AudiobookDetailsState> emit,
  ) async {
    _currentAudiobookId = event.audiobook.id;
    var box = Hive.box('favourite_audiobooks_box');
    emit(AudiobookDetailsFavourite(box.containsKey(event.audiobook.id)));
  }

  FutureOr<void> favouriteIconButtonClicked(
    FavouriteIconButtonClicked event,
    Emitter<AudiobookDetailsState> emit,
  ) async {
    var box = Hive.box('favourite_audiobooks_box');
    _currentAudiobookId = event.audiobook.id;
    AppLogger.debug('Favourite icon clicked and id is ${event.audiobook.id}');

    if (box.containsKey(event.audiobook.id)) {
      await box.delete(event.audiobook.id);
      AppLogger.debug('Favourite removed for this id ${event.audiobook.id}');
      emit(AudiobookDetailsFavourite(false));
    } else {
      await box.put(event.audiobook.id, event.audiobook.toMap());
      AppLogger.debug('Favourite added for this id ${event.audiobook.id}');
      emit(AudiobookDetailsFavourite(true));
    }
  }

  @override
  Future<void> close() {
    _favouriteBoxSubscription?.cancel();
    return super.close();
  }
}
