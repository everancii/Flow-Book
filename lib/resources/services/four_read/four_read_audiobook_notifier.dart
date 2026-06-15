import 'dart:convert';
import 'dart:io';

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_storage.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FourReadAudiobookNotifier extends ChangeNotifier {
  static final FourReadAudiobookNotifier _instance =
      FourReadAudiobookNotifier._internal();

  factory FourReadAudiobookNotifier() => _instance;

  FourReadAudiobookNotifier._internal();

  List<Audiobook> _audiobooks = [];
  bool _isLoading = false;
  String? _error;

  List<Audiobook> get audiobooks => _audiobooks;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchAudiobooks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rootDir = await _rootDirectory();
      if (!await rootDir.exists()) {
        _audiobooks = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      final audiobooks = <Audiobook>[];
      await for (final entity in rootDir.list()) {
        if (entity is! Directory) continue;

        final audiobookFile = File(p.join(entity.path, 'audiobook.txt'));
        if (!await audiobookFile.exists()) continue;

        try {
          final content = await audiobookFile.readAsString();
          final audiobookData = Map<String, dynamic>.from(jsonDecode(content));

          if (audiobookData['origin'] == null) {
            audiobookData['origin'] = AppConstants.fourReadDirName;
          }
          if (audiobookData['lowQCoverImage'] != null &&
              !(audiobookData['lowQCoverImage'] as String).startsWith('http') &&
              (audiobookData['lowQCoverImage'] as String).isNotEmpty &&
              !p.isAbsolute(audiobookData['lowQCoverImage'] as String)) {
            audiobookData['lowQCoverImage'] =
                p.join(entity.path, audiobookData['lowQCoverImage']);
          }

          if (audiobookData['id'] != null && audiobookData['title'] != null) {
            audiobooks.add(Audiobook.fromMap(audiobookData));
          }
        } catch (e) {
          AppLogger.debug('Error decoding audiobook.txt in ${entity.path}: $e');
        }
      }

      audiobooks.sort((a, b) {
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return b.date!.compareTo(a.date!);
      });

      _audiobooks = audiobooks;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      AppLogger.debug('Error fetching 4Read audiobooks: $e');
      notifyListeners();
    }
  }

  Future<bool> deleteAudiobook(String audiobookId) async {
    try {
      final audiobookDir =
          await fourReadAudiobookDirectory(audiobookId, createIfMissing: false);
      if (await audiobookDir.exists()) {
        await audiobookDir.delete(recursive: true);
        _audiobooks.removeWhere((audiobook) => audiobook.id == audiobookId);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.debug('Error deleting 4Read audiobook $audiobookId: $e');
      return false;
    }
  }

  bool isAudiobookAlreadyImported(String audiobookId) {
    return _audiobooks.any((audiobook) => audiobook.id == audiobookId);
  }

  void addAudiobook(Audiobook audiobook) {
    final existingIndex = _audiobooks.indexWhere((ab) => ab.id == audiobook.id);
    if (existingIndex != -1) {
      _audiobooks[existingIndex] = audiobook;
    } else {
      _audiobooks.insert(0, audiobook);
    }

    _audiobooks.sort((a, b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return b.date!.compareTo(a.date!);
    });

    notifyListeners();
  }

  void refresh() {
    fetchAudiobooks();
  }

  Future<Directory> _rootDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final rootDir = Directory(p.join(appDir.path, AppConstants.fourReadDirName));
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    return rootDir;
  }
}
