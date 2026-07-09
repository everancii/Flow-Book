import 'dart:io';

import 'package:audiobookflow/screens/audiobook_details/bloc/audiobook_details_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('aradia_hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('favourite_audiobooks_box');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('emits source-specific error when 4read id is invalid', () async {
    final bloc = AudiobookDetailsBloc();
    final emittedStates = <AudiobookDetailsState>[];
    final sub = bloc.stream.listen(emittedStates.add);

    bloc.add(
      FetchAudiobookDetails(
        '',
        false,
        false,
        isFourRead: true,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 120));

    final errorStates =
        emittedStates.whereType<AudiobookDetailsError>().toList();
    expect(errorStates, isNotEmpty);
    expect(
      errorStates.last.message,
      'This 4Read title cannot be opened right now. Please retry or choose another title.',
    );

    await sub.cancel();
    await bloc.close();
  });
}
