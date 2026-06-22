import 'dart:async';
import 'package:audiobookflow/resources/services/download/download_manager.dart';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
// import 'package:ionicons/ionicons.dart';
import 'package:audiobookflow/resources/designs/app_circular_progress_indicator.dart';
import 'package:audiobookflow/resources/designs/app_colors.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';

import 'package:audiobookflow/screens/audiobook_details/bloc/audiobook_details_bloc.dart';
import 'package:audiobookflow/screens/audiobook_details/widgets/description_text.dart';
import 'package:audiobookflow/screens/download_audiobook/widget/download_button.dart';
import 'package:audiobookflow/resources/services/audio_handler_provider.dart';
import 'package:audiobookflow/widgets/low_and_high_image.dart';
import 'package:audiobookflow/widgets/rating_widget.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

import '../../resources/models/history_of_audiobook.dart';

class AudiobookDetails extends StatefulWidget {
  final Audiobook audiobook;
  final bool isDownload;
  final bool isYoutube;
  final bool isYoutubeSearch;
  final bool isLocal;
  final bool isFourRead;
  final bool isKnigavuhe;

  const AudiobookDetails({
    super.key,
    required this.audiobook,
    this.isDownload = false,
    this.isYoutube = false,
    this.isYoutubeSearch = false,
    this.isLocal = false,
    this.isFourRead = false,
    this.isKnigavuhe = false,
  });

  @override
  State<AudiobookDetails> createState() => _AudiobookDetailsState();
}

class _AudiobookDetailsState extends State<AudiobookDetails> {
  late AudiobookDetailsBloc _audiobookDetailsBloc;
  late Box<dynamic> playingAudiobookDetailsBox;
  late WeSlideController _weSlideController;
  late AudioHandlerProvider audioHandlerProvider;
  late HistoryOfAudiobook historyOfAudiobook;

  StreamSubscription? _downloadSub;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  bool _isBufferingYouTube = false;
  bool _bufferingListenerSetup = false;

  Future<void> _playChapter(List<AudiobookFile> files, int index) async {
    try {
      await playingAudiobookDetailsBox.put(
          'audiobook', widget.audiobook.toMap());
      await playingAudiobookDetailsBox.put(
        'audiobookFiles',
        files.map((e) => e.toMap()).toList(),
      );
      await playingAudiobookDetailsBox.put('index', index);
      await playingAudiobookDetailsBox.put('position', 0);

      await audioHandlerProvider.audioHandler
          .initSongs(files, widget.audiobook, index, 0);
      await audioHandlerProvider.audioHandler.play();
      _weSlideController.show();
    } catch (e) {
      AppLogger.debug('Error starting chapter playback: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Unable to start playback. Please try again.')),
      );
    }
  }

  Widget _durationSubtitle(AudiobookFile file) {
    final seconds = file.length?.toInt() ?? 0;
    if (seconds > 0) {
      final duration = Duration(seconds: seconds);
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      final secs = duration.inSeconds.remainder(60);

      String formatted = '';
      if (hours > 0) {
        formatted = "$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
      } else {
        formatted = "${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
      }

      return Text(
        formatted,
        style: GoogleFonts.ubuntu(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    // ... (rest of the method unchanged)
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.35, end: 0.9),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, opacity, child) {
        return Opacity(opacity: opacity, child: child);
      },
      onEnd: () {
        if (mounted) {
          setState(() {});
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading...',
            style: GoogleFonts.ubuntu(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _audiobookDetailsBloc = BlocProvider.of<AudiobookDetailsBloc>(context);
    _audiobookDetailsBloc.add(GetFavouriteStatus(widget.audiobook));
    _audiobookDetailsBloc.add(FetchAudiobookDetails(
      widget.audiobook.id,
      widget.isDownload,
      widget.isYoutube,
      isYoutubeSearch: widget.isYoutubeSearch,
      isLocal: widget.isLocal,
      isFourRead: widget.isFourRead,
      isKnigavuhe: widget.isKnigavuhe,
    ));
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');
    historyOfAudiobook = HistoryOfAudiobook();
    
    _setupDownloadListener();
  }

  void _setupDownloadListener() {
    final dm = DownloadManager();
    _isDownloading = dm.isDownloading(widget.audiobook.id);
    _downloadProgress = dm.getProgress(widget.audiobook.id);

    _downloadSub = dm.progressStream.listen((event) {
      if (event.audiobookId == widget.audiobook.id) {
        if (mounted) {
          setState(() {
            _isDownloading = event.isDownloading;
            _downloadProgress = event.progress;
          });
        }
      }
    });
  }

  void _setupYouTubeBufferingListener() {
    if (_bufferingListenerSetup) return;
    _bufferingListenerSetup = true;
    final handler = audioHandlerProvider.audioHandler;
    _isBufferingYouTube = handler.isBufferingYouTube.value;
    handler.isBufferingYouTube.addListener(_onYouTubeBufferingChanged);
  }

  void _onYouTubeBufferingChanged() {
    if (mounted) {
      setState(() {
        _isBufferingYouTube = audioHandlerProvider.audioHandler.isBufferingYouTube.value;
      });
    }
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    audioHandlerProvider.audioHandler.isBufferingYouTube.removeListener(_onYouTubeBufferingChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _weSlideController = Provider.of<WeSlideController>(context);
    audioHandlerProvider = Provider.of<AudioHandlerProvider>(context);
    _setupYouTubeBufferingListener();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.audiobook.title,
          style: GoogleFonts.ubuntu(
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          BlocBuilder<AudiobookDetailsBloc, AudiobookDetailsState>(
            buildWhen: (previous, current) => current is AudiobookDetailsLoaded,
            builder: (context, state) {
              if (state is AudiobookDetailsLoaded) {
                return SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: DownloadButton(
                      audiobook: widget.audiobook,
                      audiobookFiles: state.audiobookFiles,
                    ),
                  ),
                );
              }
              return const SizedBox(width: 48);
            },
          ),
          BlocConsumer<AudiobookDetailsBloc, AudiobookDetailsState>(
            listener: (context, state) {},
            listenWhen: (previous, current) =>
                current is AudiobookDetailsFavourite,
            buildWhen: (previous, current) =>
                current is AudiobookDetailsFavourite,
            builder: (context, state) {
              if (state is AudiobookDetailsFavourite) {
                return IconButton(
                  icon: state.isFavourite
                      ? const Icon(
                          Icons.favorite,
                          color: Colors.red,
                          size: 30,
                        )
                      : const Icon(Icons.favorite_border,
                          color: Colors.red, size: 30),
                  onPressed: () {
                    _audiobookDetailsBloc
                        .add(FavouriteIconButtonClicked(widget.audiobook));
                  },
                );
              } else {
                return const SizedBox();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_isDownloading)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: AppColors.primaryColor.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Downloading... ${(_downloadProgress * 100).toStringAsFixed(1)}%',
                        style: GoogleFonts.ubuntu(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            BlocConsumer<AudiobookDetailsBloc, AudiobookDetailsState>(
              listener: (context, state) {},
              listenWhen: (previous, current) =>
                  current is AudiobookDetailsInitial ||
                  current is AudiobookDetailsLoading ||
                  current is AudiobookDetailsError ||
                  current is AudiobookDetailsLoaded,
              buildWhen: (previous, current) =>
                  current is AudiobookDetailsInitial ||
                  current is AudiobookDetailsLoading ||
                  current is AudiobookDetailsError ||
                  current is AudiobookDetailsLoaded,
              builder: (context, state) {
                if (state is AudiobookDetailsInitial || state is AudiobookDetailsLoading) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 100),
                      child: AppCircularProgressIndicator(),
                    ),
                  );
                } else if (state is AudiobookDetailsLoaded) {
                  final fourReadDesc = state.fourReadDescription?.trim() ?? '';
                  final knigavuheDesc = state.knigavuheDescription?.trim() ?? '';
                  final rawDescription = fourReadDesc.isNotEmpty
                      ? fourReadDesc
                      : knigavuheDesc.isNotEmpty
                          ? knigavuheDesc
                          : (widget.audiobook.description?.trim() ?? '');
                  final descriptionText = rawDescription.isEmpty
                      ? 'No description available.'
                      : rawDescription;
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LowAndHighImage(
                              lowQImage: widget.audiobook.lowQCoverImage,
                              highQImage: state.audiobookFiles[0].highQCoverImage,
                              height: 200,
                              width: 200,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: 200,
                          alignment: Alignment.center,
                          child: Text(
                            widget.audiobook.title,
                            textAlign: TextAlign.center,
                            softWrap: true,
                            style: GoogleFonts.ubuntu(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          widget.audiobook.author ?? 'N/A',
                          style: GoogleFonts.ubuntu(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        if (widget.audiobook.origin == 'librivox')
                          Text(
                            "Downloads : ${widget.audiobook.downloads != null ? widget.audiobook.downloads! > 999 ? widget.audiobook.downloads! > 999999 ? "${(widget.audiobook.downloads! / 1000000).toStringAsFixed(1)}M" : "${(widget.audiobook.downloads! / 1000).toStringAsFixed(1)}K" : widget.audiobook.downloads.toString() : "N/A"}",
                            style: GoogleFonts.ubuntu(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        Text(
                          widget.audiobook.origin ?? "librivox",
                          style: GoogleFonts.ubuntu(
                            fontSize: 13,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        if (widget.audiobook.origin == 'librivox')
                          RatingWidget(
                            rating: widget.audiobook.rating ?? 0.0,
                            size: 20,
                          ),
                        const SizedBox(height: 16),
                        Center(
                          child: _isBufferingYouTube
                              ? const SizedBox(
                                  width: 72,
                                  height: 72,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: AppColors.primaryColor,
                                    ),
                                  ),
                                )
                              : Material(
                                  shape: const CircleBorder(),
                                  color: AppColors.primaryColor,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () {
                                      playingAudiobookDetailsBox.put(
                                          'audiobook', widget.audiobook.toMap());
                                      playingAudiobookDetailsBox.put(
                                        'audiobookFiles',
                                        state.audiobookFiles
                                            .map((e) => e.toMap())
                                            .toList(),
                                      );

                                      if (historyOfAudiobook
                                          .isAudiobookInHistory(widget.audiobook.id)) {
                                        final historyItem = historyOfAudiobook
                                            .getHistoryOfAudiobookItem(widget.audiobook.id);
                                        audioHandlerProvider.audioHandler.initSongs(
                                          state.audiobookFiles,
                                          widget.audiobook,
                                          historyItem.index,
                                          historyItem.position,
                                        );
                                        playingAudiobookDetailsBox.put('index', historyItem.index);
                                        playingAudiobookDetailsBox.put('position', historyItem.position);
                                      } else {
                                        playingAudiobookDetailsBox.put('index', 0);
                                        playingAudiobookDetailsBox.put('position', 0);
                                        audioHandlerProvider.audioHandler.initSongs(
                                          state.audiobookFiles,
                                          widget.audiobook,
                                          0,
                                          0,
                                        );
                                      }

                                      _weSlideController.show();
                                    },
                                    child: const SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: Icon(
                                        Icons.play_arrow,
                                        size: 36,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Description',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            DescriptionText(
                              description: descriptionText,
                              maxLength: widget.isYoutubeSearch
                                  ? 600
                                  : widget.isFourRead
                                      ? 800
                                      : widget.isKnigavuhe
                                          ? 800
                                          : 400,
                              expandable: true,
                            ),
                            const SizedBox(height: 10),
                            Container(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Audio Files",
                                    style: GoogleFonts.ubuntu(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  ListView.builder(
                                    itemCount: state.audiobookFiles.length,
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      final isCurrentTrack = _isBufferingYouTube &&
                                          audioHandlerProvider.audioHandler.currentIndex == index;
                                      return ListTile(
                                          onTap: () => _playChapter(
                                                state.audiobookFiles,
                                                index,
                                              ),
                                          title: Text(
                                            state.audiobookFiles[index].title ??
                                                'N/A',
                                            style: GoogleFonts.ubuntu(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          subtitle: _durationSubtitle(
                                            state.audiobookFiles[index],
                                          ),
                                          trailing: isCurrentTrack
                                              ? const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: AppColors.primaryColor,
                                                  ),
                                                )
                                              : IconButton(
                                                  onPressed: () => _playChapter(
                                                    state.audiobookFiles,
                                                    index,
                                                  ),
                                                  icon: const Icon(Icons.play_arrow),
                                                ));
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Subjects',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Wrap(
                              spacing: 5,
                              children: List.generate(
                                (widget.audiobook.subject ?? []).length,
                                (index) {
                                  final subjectName = widget.audiobook.subject![index];
                                  return widget.audiobook.origin == 'youtube'
                                      ? Chip(
                                          label: Text(
                                            subjectName,
                                            style: GoogleFonts.ubuntu(
                                              fontSize: 13,
                                            ),
                                          ),
                                        )
                                      : GestureDetector(
                                          onTap: () {
                                            context.push(
                                              '/genre_audiobooks',
                                              extra: subjectName,
                                            );
                                            AppLogger.debug('Tapped subject: $subjectName');
                                          },
                                          child: Chip(
                                            label: Text(
                                              subjectName,
                                              style: GoogleFonts.ubuntu(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                } else if (state is AudiobookDetailsError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            state.message,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.ubuntu(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              _audiobookDetailsBloc.add(FetchAudiobookDetails(
                                widget.audiobook.id,
                                widget.isDownload,
                                widget.isYoutube,
                                isYoutubeSearch: widget.isYoutubeSearch,
                                isLocal: widget.isLocal,
                                isFourRead: widget.isFourRead,
                                isKnigavuhe: widget.isKnigavuhe,
                              ));
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          ],
        ),
      ),
    );
  }
}
