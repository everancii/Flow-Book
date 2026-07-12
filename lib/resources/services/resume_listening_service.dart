/// Reads now-playing and history data, validates whether an item can be
/// resumed, and returns a display-ready [ResumeState] for the Home screen.
library;

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/models/history_of_audiobook.dart';
import 'package:hive/hive.dart';

/// Result of a resume-listing check.
class ResumeState {
  const ResumeState({
    required this.audiobook,
    required this.files,
    required this.index,
    required this.position,
    required this.lastModified,
    this.currentChapterTitle,
  });

  final Audiobook audiobook;
  final List<AudiobookFile> files;
  final int index;
  final int position; // milliseconds
  final DateTime lastModified;
  final String? currentChapterTitle;

  /// The source provider origin (e.g. "librivox", "youtube", "fourRead").
  String get source => audiobook.origin ?? '';
}

/// Whether there is no valid saved playback state.
class EmptyResumeState {
  const EmptyResumeState();
}

/// Checks whether the user has a resumable audiobook.
///
/// Priority order:
/// 1. The currently-playing audiobook in `playing_audiobook_details_box`.
/// 2. The most recent item in the history box.
///
/// Returns [EmptyResumeState] when there is nothing to resume.
class ResumeListeningService {
  const ResumeListeningService({
    this.historyOfAudiobook,
  });

  final HistoryOfAudiobook? historyOfAudiobook;

  /// Returns a valid [ResumeState] or [EmptyResumeState].
  Future<Object> getResumeState() async {
    // 1. Check the currently-playing box first.
    final playingBox = Hive.box('playing_audiobook_details_box');
    final playingResult = _tryFromPlayingBox(playingBox);
    if (playingResult != null) return playingResult;

    // 2. Fall back to the most recent history item.
    final history = historyOfAudiobook ?? HistoryOfAudiobook();
    return _tryFromHistory(history);
  }

  ResumeState? _tryFromPlayingBox(Box<dynamic> box) {
    final audiobookData = box.get('audiobook');
    final filesData = box.get('audiobookFiles');
    if (audiobookData == null || filesData == null) return null;

    try {
      final audiobook =
          Audiobook.fromMap(Map<String, dynamic>.from(audiobookData as Map));
      if (audiobook.id.isEmpty || audiobook.title.isEmpty) return null;

      final files = (filesData as List)
          .map((e) => AudiobookFile.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      if (files.isEmpty) return null;

      final index = (box.get('index') as int?) ?? 0;
      final position = (box.get('position') as int?) ?? 0;
      final clampedIndex = index.clamp(0, files.length - 1);

      return ResumeState(
        audiobook: audiobook,
        files: files,
        index: clampedIndex,
        position: position,
        lastModified: DateTime.now(),
        currentChapterTitle: _chapterTitle(files, clampedIndex),
      );
    } catch (_) {
      return null;
    }
  }

  Object _tryFromHistory(HistoryOfAudiobook history) {
    final items = history.getHistory();
    if (items.isEmpty) return const EmptyResumeState();

    final mostRecent = items.first;
    if (mostRecent.audiobook.id.isEmpty ||
        mostRecent.audiobook.title.isEmpty) {
      return const EmptyResumeState();
    }
    if (mostRecent.audiobookFiles.isEmpty) {
      return const EmptyResumeState();
    }

    final clampedIndex =
        mostRecent.index.clamp(0, mostRecent.audiobookFiles.length - 1);

    return ResumeState(
      audiobook: mostRecent.audiobook,
      files: mostRecent.audiobookFiles,
      index: clampedIndex,
      position: mostRecent.position,
      lastModified: mostRecent.lastModified,
      currentChapterTitle: _chapterTitle(mostRecent.audiobookFiles, clampedIndex),
    );
  }

  String? _chapterTitle(List<AudiobookFile> files, int index) {
    if (index < 0 || index >= files.length) return null;
    return files[index].title;
  }
}
