import 'dart:io';

import 'package:audiobookflow/resources/designs/theme_notifier.dart';
import 'package:audiobookflow/resources/models/latest_version_fetch_model.dart';
import 'package:audiobookflow/screens/setting/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('flow_book_settings_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox('language_prefs_box');
    await Hive.openBox('settings');
    await Hive.openBox('theme_mode_box');
  });

  tearDown(() async {
    await Hive.close();
    if (hiveDir.existsSync()) {
      hiveDir.deleteSync(recursive: true);
    }
  });

  testWidgets('manual update check reports when app is up to date',
      (tester) async {
    var checks = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeNotifier(),
        child: MaterialApp(
          home: Settings(
            loadAppVersion: () async => '1.1.17',
            fetchLatestVersion: () async {
              checks += 1;
              return Right(
                LatestVersionFetchModel(latestVersion: '1.1.17'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(checks, 1);
    expect(find.text("You're up to date."), findsOneWidget);
  });
}
