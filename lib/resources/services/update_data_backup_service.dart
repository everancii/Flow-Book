import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

class UpdateDataBackupService {
  static const _backupFileName = 'flowbook_pre_update_backup.json';

  static const _protectedBoxes = [
    'history_of_audiobook_box',
    'playing_audiobook_details_box',
    'favourite_audiobooks_box',
    'bookmarks_box',
    'listening_stats_box',
  ];

  const UpdateDataBackupService._();

  static Future<void> createPreUpdateBackup() async {
    final backupFile = await _backupFile();
    final backup = <String, dynamic>{
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'boxes': <String, dynamic>{},
    };

    final boxes = backup['boxes'] as Map<String, dynamic>;
    for (final boxName in _protectedBoxes) {
      final box = Hive.box(boxName);
      boxes[boxName] = {
        for (final key in box.keys) key.toString(): box.get(key),
      };
    }

    await backupFile.writeAsString(jsonEncode(backup), flush: true);
  }

  static Future<void> restoreMissingDataAfterUpdate() async {
    final backupFile = await _backupFile();
    if (!await backupFile.exists()) return;

    final decoded = jsonDecode(await backupFile.readAsString());
    if (decoded is! Map<String, dynamic>) return;

    final boxes = decoded['boxes'];
    if (boxes is! Map<String, dynamic>) return;

    for (final boxName in _protectedBoxes) {
      final savedValues = boxes[boxName];
      if (savedValues is! Map<String, dynamic> || savedValues.isEmpty) {
        continue;
      }

      final box = Hive.box(boxName);
      if (box.isNotEmpty) continue;

      await box.putAll(savedValues);
    }
  }

  static Future<File> _backupFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_backupFileName');
  }
}
