import 'dart:io';

import 'package:audiobookflow/main.dart';
import 'package:audiobookflow/resources/designs/theme_notifier.dart';
import 'package:audiobookflow/resources/services/audio_handler_provider.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_audiobook_notifier.dart';
import 'package:audiobookflow/resources/services/youtube/webview_keep_alive_provider.dart';
import 'package:audiobookflow/resources/services/youtube/youtube_audiobook_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('flow_book_widget_test_');
    Hive.init(hiveDir.path);
    for (final boxName in [
      'favourite_audiobooks_box',
      'download_status_box',
      'playing_audiobook_details_box',
      'theme_mode_box',
      'history_of_audiobook_box',
      'recommened_audiobooks_box',
      'dual_mode_box',
      'language_prefs_box',
      'bookmarks_box',
      'listening_stats_box',
      'four_read_auth',
      'settings',
    ]) {
      await Hive.openBox(boxName);
    }
  });

  tearDown(() async {
    await Hive.close();
    if (hiveDir.existsSync()) {
      hiveDir.deleteSync(recursive: true);
    }
  });

  testWidgets('Flow Book app shell opens on home tab', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AudioHandlerProvider()),
          ChangeNotifierProvider(create: (_) => WeSlideController()),
          ChangeNotifierProvider(create: (_) => ThemeNotifier()),
          ChangeNotifierProvider(create: (_) => YoutubeAudiobookNotifier()),
          ChangeNotifierProvider(create: (_) => FourReadAudiobookNotifier()),
          ChangeNotifierProvider(create: (_) => WebViewKeepAliveProvider()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Flow Book'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.download), findsOneWidget);
  });
}
