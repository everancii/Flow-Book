import 'package:audiobookflow/resources/services/my_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../../resources/designs/app_colors.dart';
import 'characters_dialog.dart';

class Controls extends StatefulWidget {
  final MyAudioHandler audioHandler;
  final void Function(BuildContext) onTimerPressed;
  final VoidCallback onCancelTimer;
  final VoidCallback onToggleSkipSilence;
  final bool isTimerActive;
  final Duration? activeTimerDuration;
  final bool skipSilence;

  const Controls({
    super.key,
    required this.audioHandler,
    required this.onTimerPressed,
    required this.isTimerActive,
    required this.activeTimerDuration,
    required this.onCancelTimer,
    required this.onToggleSkipSilence,
    required this.skipSilence,
  });

  @override
  State<Controls> createState() => _ControlsState();
}

class _ControlsState extends State<Controls> {
  double _playbackSpeed = 1.0;
  double _volume = 0.5;

  void _changePlaybackSpeed() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Adjust Playback Speed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Slider(
                activeColor: const Color.fromRGBO(255, 165, 0, 1),
                inactiveColor: Colors.grey[300],
                thumbColor: const Color.fromRGBO(204, 119, 34, 1),
                value: _playbackSpeed,
                min: 0.5,
                max: 2.0,
                divisions: 6,
                label: "${_playbackSpeed.toStringAsFixed(1)}x",
                onChanged: (value) {
                  setModalState(() {
                    _playbackSpeed = value;
                  });
                  setState(() {
                    widget.audioHandler.setSpeed(_playbackSpeed);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _changeVolume() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Adjust Volume',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Slider(
                activeColor: const Color.fromRGBO(255, 165, 0, 1),
                inactiveColor: Colors.grey[300],
                thumbColor: const Color.fromRGBO(204, 119, 34, 1),
                value: _volume,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                label: "${(_volume * 100).toInt()}%",
                onChanged: (value) {
                  setModalState(() {
                    _volume = value;
                  });
                  setState(() {
                    widget.audioHandler.setVolume(_volume);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCharactersDialog() {
    final audiobookId = widget.audioHandler.getCurrentAudiobookId();
    if (audiobookId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audiobook is currently playing')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => CharactersDialog(audiobookId: audiobookId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.isTimerActive && widget.activeTimerDuration != null)
          Text(
            "Timer: ${widget.activeTimerDuration!.inMinutes}:${(widget.activeTimerDuration!.inSeconds % 60).toString().padLeft(2, '0')} remaining",
            style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _changePlaybackSpeed,
              icon: const Icon(Icons.speed),
              tooltip: 'Adjust Playback Speed',
              color: Theme.of(context).brightness == Brightness.dark
                  ? (_playbackSpeed != 1.0 ? Colors.deepOrange : Colors.white)
                  : (_playbackSpeed != 1.0 ? Colors.deepOrange : Colors.black),
            ),
            IconButton(
              onPressed: _changeVolume,
              icon: const Icon(Icons.volume_up),
              tooltip: 'Adjust Volume',
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
            IconButton(
              onPressed: _showCharactersDialog,
              icon: const Icon(Icons.people),
              tooltip: 'Manage Characters',
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
            IconButton(
              onPressed: widget.onToggleSkipSilence,
              icon: Icon(
                widget.skipSilence ? Icons.flash_on : Icons.flash_off,
                color: widget.skipSilence
                    ? Colors.deepOrange
                    : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black),
              ),
              tooltip:
                  widget.skipSilence ? 'Skip Silence On' : 'Skip Silence Off',
            ),
            IconButton(
              onPressed: widget.isTimerActive
                  ? widget.onCancelTimer
                  : () => widget.onTimerPressed(context),
              icon: Icon(
                widget.isTimerActive ? Icons.snooze : Icons.snooze_outlined,
                color: widget.isTimerActive
                    ? Colors.deepOrange
                    : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black),
              ),
              tooltip: widget.isTimerActive
                  ? 'Cancel Timer (${widget.activeTimerDuration?.inMinutes} min)'
                  : 'Set Sleep Timer',
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: () {
                widget.audioHandler.seek(
                    widget.audioHandler.position - const Duration(seconds: 10));
              },
              icon: const Icon(Icons.replay_10),
              iconSize: 32.0,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
            IconButton(
              onPressed: () {
                widget.audioHandler.playPrevious();
              },
              icon: const Icon(Icons.skip_previous),
              iconSize: 32.0,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
            StreamBuilder<PlaybackState>(
              stream: widget.audioHandler.playbackState,
              builder: (context, snapshot) {
                final st = snapshot.data;
                final isPlaying = st?.playing ?? false;
                final isLoading = st?.processingState == AudioProcessingState.loading;

                if (isLoading) {
                  return SizedBox(
                    width: 61,
                    height: 61,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 3.0,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                  );
                }

                return IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 45,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                  onPressed: () {
                    if (isPlaying) {
                      widget.audioHandler.pause();
                    } else {
                      widget.audioHandler.play();
                    }
                  },
                );
              },
            ),
            IconButton(
              onPressed: () {
                widget.audioHandler.playNext();
              },
              icon: const Icon(Icons.skip_next),
              iconSize: 32.0,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
            IconButton(
              onPressed: () {
                widget.audioHandler.seek(
                    widget.audioHandler.position + const Duration(seconds: 10));
              },
              icon: const Icon(Icons.forward_10),
              iconSize: 32.0,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ],
        ),
      ],
    );
  }
}
