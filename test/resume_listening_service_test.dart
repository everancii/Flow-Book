import 'dart:io';

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/models/history_of_audiobook.dart';
import 'package:audiobookflow/resources/services/resume_listening_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('flow_book_resume_test_');
    Hive.init(hiveDir.path);
    for (final boxName in [
      'playing_audiobook_details_box',
      'history_of_audiobook_box',
    ]) {
      await Hive.openBox(boxName);
    }
  });

  setUp(() async {
    await Hive.box('playing_audiobook_details_box').clear();
    await Hive.box('history_of_audiobook_box').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  group('ResumeListeningService', () {
    test('returns EmptyResumeState when no saved state exists', () async {
      final service = ResumeListeningService();
      final result = await service.getResumeState();

      expect(result, isA<EmptyResumeState>());
    });

    test('returns ResumeState from playing box when available', () async {
      final box = Hive.box('playing_audiobook_details_box');
      final audiobook = _sampleAudiobook();
      final files = _sampleFiles();

      await box.put('audiobook', audiobook.toMap());
      await box.put('audiobookFiles', files.map((f) => f.toMap()).toList());
      await box.put('index', 1);
      await box.put('position', 42000);

      final service = ResumeListeningService();
      final result = await service.getResumeState();

      expect(result, isA<ResumeState>());
      final state = result as ResumeState;
      expect(state.audiobook.title, 'Test Book');
      expect(state.index, 1);
      expect(state.position, 42000);
      expect(state.currentChapterTitle, 'Chapter Two');
      expect(state.source, 'librivox');
    });

    test('falls back to history when playing box is empty', () async {
      final history = HistoryOfAudiobook();
      final audiobook = _sampleAudiobook();
      final files = _sampleFiles();

      await history.addToHistory(audiobook, files, 0, 5000);

      final service = ResumeListeningService(
        historyOfAudiobook: history,
      );
      final result = await service.getResumeState();

      expect(result, isA<ResumeState>());
      final state = result as ResumeState;
      expect(state.audiobook.title, 'Test Book');
      expect(state.index, 0);
      expect(state.position, 5000);
    });

    test('clamps out-of-range index', () async {
      final box = Hive.box('playing_audiobook_details_box');
      final audiobook = _sampleAudiobook();
      final files = _sampleFiles();

      await box.put('audiobook', audiobook.toMap());
      await box.put('audiobookFiles', files.map((f) => f.toMap()).toList());
      await box.put('index', 99); // out of range
      await box.put('position', 0);

      final service = ResumeListeningService();
      final result = await service.getResumeState();

      expect(result, isA<ResumeState>());
      final state = result as ResumeState;
      expect(state.index, 2); // clamped to last valid index
    });

    test('ignores corrupt playing box and falls back to history', () async {
      final box = Hive.box('playing_audiobook_details_box');
      await box.put('audiobook', 'not-a-map');

      final history = HistoryOfAudiobook();
      final audiobook = _sampleAudiobook();
      final files = _sampleFiles();
      await history.addToHistory(audiobook, files, 0, 100);

      final service = ResumeListeningService(
        historyOfAudiobook: history,
      );
      final result = await service.getResumeState();

      expect(result, isA<ResumeState>());
      final state = result as ResumeState;
      expect(state.audiobook.title, 'Test Book');
    });
  });
}

Audiobook _sampleAudiobook() {
  return Audiobook.fromMap({
    'id': 'test-id-123',
    'title': 'Test Book',
    'author': 'Test Author',
    'description': 'A test book',
    'lowQCoverImage': 'https://example.com/cover.jpg',
    'language': 'en',
    'origin': 'librivox',
  });
}

List<AudiobookFile> _sampleFiles() {
  return [
    AudiobookFile.fromMap({
      'identifier': 'test-id-123',
      'title': 'Chapter One',
      'name': 'chapter1.mp3',
      'track': 1,
      'size': 1000,
      'length': 120.0,
      'url': 'https://example.com/ch1.mp3',
      'highQCoverImage': null,
      'startMs': null,
      'durationMs': null,
    }),
    AudiobookFile.fromMap({
      'identifier': 'test-id-123',
      'title': 'Chapter Two',
      'name': 'chapter2.mp3',
      'track': 2,
      'size': 1000,
      'length': 180.0,
      'url': 'https://example.com/ch2.mp3',
      'highQCoverImage': null,
      'startMs': null,
      'durationMs': null,
    }),
    AudiobookFile.fromMap({
      'identifier': 'test-id-123',
      'title': 'Chapter Three',
      'name': 'chapter3.mp3',
      'track': 3,
      'size': 1000,
      'length': 200.0,
      'url': 'https://example.com/ch3.mp3',
      'highQCoverImage': null,
      'startMs': null,
      'durationMs': null,
    }),
  ];
}
