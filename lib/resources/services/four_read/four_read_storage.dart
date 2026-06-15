import 'dart:convert';
import 'dart:io';

import 'package:audiobookflow/utils/app_constants.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

String fourReadSafeFolderName(String audiobookId) {
  return base64UrlEncode(utf8.encode(audiobookId));
}

Future<Directory> fourReadRootDirectory() async {
  final appDir = await getApplicationDocumentsDirectory();
  final rootDir = Directory(p.join(appDir.path, AppConstants.fourReadDirName));
  if (!await rootDir.exists()) {
    await rootDir.create(recursive: true);
  }
  return rootDir;
}

Future<Directory> fourReadAudiobookDirectory(
  String audiobookId, {
  bool createIfMissing = true,
}) async {
  final rootDir = await fourReadRootDirectory();
  final audiobookDir =
      Directory(p.join(rootDir.path, fourReadSafeFolderName(audiobookId)));
  if (createIfMissing && !await audiobookDir.exists()) {
    await audiobookDir.create(recursive: true);
  }
  return audiobookDir;
}
