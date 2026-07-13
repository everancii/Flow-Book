import 'package:flutter/foundation.dart' show immutable;

@immutable
class AppConstants {
  const AppConstants._(); 

  static const String youtubeDirName = 'youtube';
  static const String fourReadDirName = '4read';
  static const String knigavuheDirName = 'knigavuhe';
  static const String soundBooksDirName = 'soundbooks';
  static const String localDirName = 'local';

  static const List<String> supportedAudioExtensions = [
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.opus',
    '.flac',
  ];
}
