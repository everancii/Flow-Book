// lib/widgets/mini_audio_player.dart
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:audiobookflow/resources/designs/app_colors.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/services/audio_handler_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:audiobookflow/screens/audiobook_player/audiobook_player.dart';
import 'package:audiobookflow/screens/audiobook_player/widgets/favourite_button.dart';
import 'package:audiobookflow/screens/download_audiobook/widget/download_button.dart';
import 'package:provider/provider.dart';
import 'package:audiobookflow/resources/services/download/download_manager.dart';
import 'package:we_slide/we_slide.dart';

class MiniAudioPlayer extends StatefulWidget {
  final Box<dynamic> playingAudiobookDetailsBox;
  final StatefulNavigationShell navigationShell;
  final BottomNavigationBar bottomNavigationBar;
  final double bottomNavBarSize;
  final bool isKeyboardOpen;

  const MiniAudioPlayer({
    super.key,
    required this.playingAudiobookDetailsBox,
    required this.navigationShell,
    required this.bottomNavigationBar,
    required this.bottomNavBarSize,
    required this.isKeyboardOpen,
  });

  @override
  State<MiniAudioPlayer> createState() => _MiniAudioPlayerState();
}

class _MiniAudioPlayerState extends State<MiniAudioPlayer> {
  late final WeSlideController weSlideController;
  String? _initializedAudiobookId; // avoid re-init

  @override
  void initState() {
    super.initState();
    weSlideController = Provider.of<WeSlideController>(context, listen: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final provider = Provider.of<AudioHandlerProvider>(context, listen: false);
    final box = widget.playingAudiobookDetailsBox;

    final audiobookMap = box.get('audiobook');
    if (audiobookMap == null) return;

    final audiobook = Audiobook.fromMap(Map<String, dynamic>.from(audiobookMap));
    
    // Defer initialization to avoid blocking startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final handlerIsEmpty =
          provider.audioHandler.getAudioSourcesFromPlaylist().isEmpty;
      if (!handlerIsEmpty && _initializedAudiobookId == audiobook.id) {
        return; // already initialized with this book
      }

      final files = (box.get('audiobookFiles') as List)
          .map((e) => AudiobookFile.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      final index = box.get('index') as int;
      final position = box.get('position') as int;

      provider.audioHandler.initSongs(files, audiobook, index, position, playImmediately: false);
      _initializedAudiobookId = audiobook.id;
    });
  }

  static String _safeDirectoryName(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.]'), '_');

  Widget _buildSliderIndicator() {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  // Helper to display cover art safely for local or remote
  Widget _coverImage(MediaItem mediaItem) {
    final art = mediaItem.artUri;
    if (art == null) {
      return Container(
        width: 50,
        height: 50,
        color: Colors.grey[700],
        child: const Icon(Icons.headphones, color: Colors.white70),
      );
    }

    if (art.scheme == 'file') {
      return Image.file(
        File(art.toFilePath()),
        width: 50,
        height: 50,
        fit: BoxFit.cover,
      );
    }

    return Image.network(
      art.toString(),
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      errorBuilder: (context, _, __) =>
          const Icon(Icons.broken_image, color: Colors.white54),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = widget.isKeyboardOpen;

    if (keyboardOpen && weSlideController.isOpened) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) weSlideController.hide();
      });
    }

    final handler = context.read<AudioHandlerProvider>().audioHandler;

    final panelMaxSize = MediaQuery.of(context).size.height;
    final footerHeight = keyboardOpen ? 0.0 : widget.bottomNavBarSize;
    final footer =
        keyboardOpen ? const SizedBox.shrink() : widget.bottomNavigationBar;
    final panelMin = keyboardOpen ? 0.0 : (80 + widget.bottomNavBarSize);

    return WeSlide(
      controller: weSlideController,
      panelMinSize: panelMin,
      panelMaxSize: panelMaxSize,
      footerHeight: footerHeight,
      footer: footer,
      body: widget.navigationShell,
      panel: AudiobookPlayer(
        onSwipeDown: () => weSlideController.hide(),
      ),
      panelHeader: Offstage(
        offstage: keyboardOpen,
        child: Container(
          height: 80,
          color: Colors.grey[850],
          child: Column(
            children: [
              Center(child: _buildSliderIndicator()),
              Expanded(
                child: StreamBuilder<MediaItem?>(
                  stream: handler.mediaItem,
                  builder: (context, snapshot) {
                    final mediaItem = snapshot.data;
                    if (mediaItem == null) return const SizedBox.shrink();

                    final box = widget.playingAudiobookDetailsBox;
                    final filesDyn = box.get('audiobookFiles') as List?;
                    final isSingleTrack = (filesDyn?.length ?? 0) <= 1;

                    final audiobookMap = box.get('audiobook');
                    if (audiobookMap == null) return const SizedBox.shrink();
                    final audiobook = Audiobook.fromMap(Map<String, dynamic>.from(audiobookMap as Map));
                    
                    final files = (filesDyn ?? []).map((e) => AudiobookFile.fromMap(Map<String, dynamic>.from(e as Map))).toList();

                    final secondaryLine = isSingleTrack
                        ? (audiobook.author ?? mediaItem.artist ?? '')
                        : mediaItem.title;

                    final audiobookId = _safeDirectoryName(audiobook.id);
                    final isDownloaded = DownloadManager().isDownloaded(audiobookId);
                    final isDownloading = DownloadManager().isDownloading(audiobookId);
                    final progress = DownloadManager().getProgress(audiobookId);

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: _coverImage(mediaItem),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: MediaQuery.of(context).size.width * 0.4,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          mediaItem.album ?? "",
                                          style: const TextStyle(color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        Text(
                                          secondaryLine,
                                          style: const TextStyle(color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(
                                width: 130,
                                height: 48,
                                child: StreamBuilder<PlaybackState>(
                                  stream: handler.playbackState,
                                  builder: (context, s) {
                                    final st = s.data;
                                    final playing = st?.playing ?? false;
                                    final isLoading = st?.processingState == AudioProcessingState.loading;
                                    return Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        DownloadButton(
                                          audiobook: audiobook,
                                          audiobookFiles: files,
                                        ),
                                        FavouriteButton(
                                          audiobook: audiobook,
                                          size: 24,
                                        ),
                                        isLoading
                                            ? const SizedBox(
                                                width: 48,
                                                height: 48,
                                                child: Padding(
                                                  padding: EdgeInsets.all(12.0),
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.0,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              )
                                            : IconButton(
                                                icon: Icon(
                                                  playing ? Icons.pause : Icons.play_arrow,
                                                  color: isDownloaded ? Colors.green : Colors.white,
                                                ),
                                                onPressed: () =>
                                                    playing ? handler.pause() : handler.play(),
                                              ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isDownloading)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white10,
                              color: Colors.deepOrange,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
