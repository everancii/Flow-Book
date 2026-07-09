import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/services/my_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

Duration effectiveTrackLength(List<AudiobookFile> audiobookFiles, int index) {
  final f = audiobookFiles[index];
  if (f.durationMs != null) {
    return Duration(milliseconds: f.durationMs!);
  } else if (f.length != null) {
    return Duration(seconds: f.length!.toInt());
  } else if (f.startMs != null && index + 1 < audiobookFiles.length) {
    final next = audiobookFiles[index + 1];
    if (next.startMs != null) {
      final diffMs = next.startMs! - f.startMs!;
      return diffMs > 0 ? Duration(milliseconds: diffMs) : Duration.zero;
    }
  }
  return Duration.zero;
}

String formatTrackDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

class TrackSelectionDialog extends StatefulWidget {
  final MyAudioHandler audioHandler;

  const TrackSelectionDialog({
    super.key,
    required this.audioHandler,
  });

  @override
  State<TrackSelectionDialog> createState() => _TrackSelectionDialogState();
}

class _TrackSelectionDialogState extends State<TrackSelectionDialog> {
  late Box<dynamic> playingAudiobookDetailsBox;
  List<AudiobookFile> _audiobookFiles = [];
  int _currentTrackIndex = 0;
  String? _lastQueueSignature;

  @override
  void initState() {
    super.initState();
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');
    _loadCurrentData();
  }

  void _loadCurrentData() {
    final audiobookFilesData =
        playingAudiobookDetailsBox.get('audiobookFiles') as List?;
    if (audiobookFilesData != null) {
      _audiobookFiles = audiobookFilesData
          .map((fileData) => AudiobookFile.fromMap(fileData))
          .toList();
    }

    _currentTrackIndex = widget.audioHandler.queue.value.indexWhere(
      (item) => item.id == widget.audioHandler.mediaItem.value?.id,
    );
    if (_currentTrackIndex == -1) _currentTrackIndex = 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<List<MediaItem>>(
      stream: widget.audioHandler.queue,
      builder: (context, queueSnapshot) {
        final queue = queueSnapshot.data;
        final queueSignature = queue == null
            ? null
            : '${queue.length}:${queue.map((item) => item.id).join('|')}:${widget.audioHandler.mediaItem.value?.id}';
        if (queueSignature != null && queueSignature != _lastQueueSignature) {
          _lastQueueSignature = queueSignature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _loadCurrentData());
            }
          });
        }

        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF282828) : Colors.grey[100],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.queue_music, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Chapters',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _audiobookFiles.length,
                    itemBuilder: (context, index) {
                      final isCurrentTrack = index == _currentTrackIndex;

                      return Container(
                        decoration: BoxDecoration(
                          color: isCurrentTrack
                              ? (isDark
                                  ? Colors.deepOrange.withValues(alpha: 0.2)
                                  : Colors.deepOrange[50])
                              : null,
                          border: isCurrentTrack
                              ? Border(
                                  left: BorderSide(
                                      color: Colors.deepOrange, width: 4))
                              : null,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCurrentTrack
                                ? Colors.deepOrange
                                : (isDark
                                    ? Colors.grey[700]
                                    : Colors.grey[300]),
                            child: Icon(
                              isCurrentTrack
                                  ? Icons.play_arrow
                                  : Icons.music_note,
                              color: isCurrentTrack
                                  ? Colors.white
                                  : (isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600]),
                            ),
                          ),
                          title: Text(
                            _audiobookFiles[index].title ??
                                'Track ${_audiobookFiles[index].track ?? (index + 1)}',
                            style: TextStyle(
                              fontWeight: isCurrentTrack
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrentTrack
                                  ? Colors.deepOrange
                                  : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatTrackDuration(
                                  effectiveTrackLength(_audiobookFiles, index),
                                ),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                              if (isCurrentTrack) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.check_circle,
                                    color: Colors.deepOrange, size: 20),
                              ],
                            ],
                          ),
                          onTap: () {
                            if (index != _currentTrackIndex) {
                              widget.audioHandler.skipToQueueItem(index);
                            }
                            Navigator.of(context).pop();
                          },
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF282828) : Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_audiobookFiles.length} tracks',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
