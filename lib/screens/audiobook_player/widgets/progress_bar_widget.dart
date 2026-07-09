import 'package:audiobookflow/resources/services/my_audio_handler.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';

class ProgressBarWidget extends StatelessWidget {
  final MyAudioHandler audioHandler;

  const ProgressBarWidget({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: audioHandler.getPositionStream(),
      builder: (context, snapshot) {
        final positionData = snapshot.data;

        final totalDuration = positionData?.duration ?? Duration.zero;
        final position = positionData?.position ?? Duration.zero;
        final bufferedPosition =
            positionData?.bufferedPosition ?? Duration.zero;
        final remainingTime = totalDuration - position;

        return Column(
          children: [
            ProgressBar(
              progressBarColor: Colors.deepOrange[600],
              thumbColor: Colors.deepOrange[800],
              baseBarColor: Colors.deepOrange[100],
              bufferedBarColor: Colors.deepOrange[200]!,
              progress: position,
              buffered: bufferedPosition,
              total: totalDuration,
              timeLabelType: TimeLabelType.totalTime,
              onSeek: (duration) {
                audioHandler.seek(duration);
              },
            ),
            const SizedBox(height: 8),
            Text(
              "Time Remaining: ${remainingTime.inMinutes}:${(remainingTime.inSeconds % 60).toString().padLeft(2, '0')}",
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}
