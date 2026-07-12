import 'dart:async';

import 'package:audiobookflow/resources/models/source_error.dart';
import 'package:audiobookflow/resources/services/source_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapToSourceError — 4Read', () {
    test('403 maps to loginRequired', () {
      final result = mapToSourceError(
        Exception('403 Forbidden'),
        source: SourceProvider.fourRead,
        stage: SourceStage.details,
      );
      expect(result.type, SourceErrorType.loginRequired);
      expect(result.source, SourceProvider.fourRead);
      expect(result.canRetry, isFalse);
      expect(result.canSearchAlternatives, isTrue);
      expect(result.sourceUrl, isNotNull);
    });

    test('404 maps to notFound', () {
      final result = mapToSourceError(
        Exception('HTTP 404 Not Found'),
        source: SourceProvider.fourRead,
        stage: SourceStage.details,
      );
      expect(result.type, SourceErrorType.notFound);
      expect(result.canRetry, isFalse);
      expect(result.canSearchAlternatives, isTrue);
    });

    test('parse error maps to parseFailure', () {
      final result = mapToSourceError(
        Exception('Could not parse HTML'),
        source: SourceProvider.fourRead,
        stage: SourceStage.search,
      );
      expect(result.type, SourceErrorType.parseFailure);
      expect(result.canRetry, isTrue);
    });

    test('unknown 4Read error maps to unknown with retry', () {
      final result = mapToSourceError(
        Exception('Something weird'),
        source: SourceProvider.fourRead,
        stage: SourceStage.search,
      );
      expect(result.type, SourceErrorType.unknown);
      expect(result.canRetry, isTrue);
    });
  });

  group('mapToSourceError — Knigavuhe', () {
    test('blocked response maps to blocked', () {
      final result = mapToSourceError(
        Exception('blocked by Cloudflare'),
        source: SourceProvider.knigavuhe,
        stage: SourceStage.search,
      );
      expect(result.type, SourceErrorType.blocked);
      expect(result.canRetry, isTrue);
      expect(result.sourceUrl, isNotNull);
    });

    test('purchase/Litres maps to notFound', () {
      final result = mapToSourceError(
        Exception('only available for purchase on Litres'),
        source: SourceProvider.knigavuhe,
        stage: SourceStage.details,
      );
      expect(result.type, SourceErrorType.notFound);
      expect(result.canRetry, isFalse);
    });
  });

  group('mapToSourceError — YouTube', () {
    test('unavailable video maps to notFound', () {
      final result = mapToSourceError(
        Exception('VideoUnavailable'),
        source: SourceProvider.youtube,
        stage: SourceStage.stream,
      );
      expect(result.type, SourceErrorType.notFound);
      expect(result.canRetry, isFalse);
    });

    test('stream error maps to streamUnavailable', () {
      final result = mapToSourceError(
        Exception('Could not get stream manifest'),
        source: SourceProvider.youtube,
        stage: SourceStage.stream,
      );
      expect(result.type, SourceErrorType.streamUnavailable);
      expect(result.canRetry, isTrue);
    });
  });

  group('mapToSourceError — generic', () {
    test('TimeoutException maps to timeout with retry', () {
      final result = mapToSourceError(
        TimeoutException('timed out'),
        source: SourceProvider.librivox,
        stage: SourceStage.search,
      );
      expect(result.type, SourceErrorType.timeout);
      expect(result.canRetry, isTrue);
      expect(result.canSearchAlternatives, isTrue);
    });

    test('FormatException maps to parseFailure', () {
      final result = mapToSourceError(
        FormatException('bad'),
        source: SourceProvider.librivox,
        stage: SourceStage.details,
      );
      expect(result.type, SourceErrorType.parseFailure);
    });

    test('playback stage unknown error has no alt search', () {
      final result = mapToSourceError(
        Exception('weird'),
        source: SourceProvider.librivox,
        stage: SourceStage.playback,
      );
      expect(result.type, SourceErrorType.unknown);
      expect(result.canSearchAlternatives, isFalse);
    });
  });

  group('SourceError equality', () {
    test('identical errors are equal', () {
      const a = SourceError(
          source: SourceProvider.fourRead,
          stage: SourceStage.details,
          type: SourceErrorType.notFound,
          title: 'Not found', message: 'gone');
      const b = SourceError(
          source: SourceProvider.fourRead,
          stage: SourceStage.details,
          type: SourceErrorType.notFound,
          title: 'Not found', message: 'gone');
      expect(a, equals(b));
    });

    test('different errors are not equal', () {
      const a = SourceError(
          source: SourceProvider.fourRead,
          stage: SourceStage.details,
          type: SourceErrorType.notFound,
          title: 'Not found', message: 'gone');
      const b = SourceError(
          source: SourceProvider.knigavuhe,
          stage: SourceStage.details,
          type: SourceErrorType.notFound,
          title: 'Not found', message: 'gone');
      expect(a, isNot(equals(b)));
    });
  });
}
