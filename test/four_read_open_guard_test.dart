import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_guard.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FourReadOpenGuard', () {
    test('normalizes relative id and preserves valid open payload', () {
      final input = Audiobook.fromMap({
        'id': '/book/some-story.html',
        'title': 'Some Story',
        'author': 'Author',
        'description': 'desc',
        'lowQCoverImage': 'https://4read.org/covers/some.jpg',
        'language': 'uk',
        'origin': AppConstants.fourReadDirName,
      });

      final result = FourReadOpenGuard.validateAndNormalizeAudiobook(
        input,
        stage: 'unit_test',
      );

      expect(result.isValid, isTrue);
      expect(result.audiobook, isNotNull);
      expect(
        result.audiobook!.id,
        'https://4read.org/book/some-story.html',
      );
      expect(result.fallbackFields, isEmpty);
    });

    test('fails when id is empty', () {
      final input = Audiobook.fromMap({
        'id': '',
        'title': 'Some Story',
        'origin': AppConstants.fourReadDirName,
      });

      final result = FourReadOpenGuard.validateAndNormalizeAudiobook(
        input,
        stage: 'unit_test',
      );

      expect(result.isValid, isFalse);
      expect(result.failure, isNotNull);
      expect(result.failure!.code, 'missing_or_invalid_article_url');
    });

    test('applies defaults for optional fields', () {
      final input = Audiobook.fromMap({
        'id': 'https://4read.org/book/story.html',
        'title': 'Story',
        'author': '',
        'description': null,
        'lowQCoverImage': '',
        'language': '',
        'origin': AppConstants.fourReadDirName,
      });

      final result = FourReadOpenGuard.validateAndNormalizeAudiobook(
        input,
        stage: 'unit_test',
      );

      expect(result.isValid, isTrue);
      expect(result.audiobook!.author, 'Unknown');
      expect(result.audiobook!.language, 'uk');
      expect(result.audiobook!.lowQCoverImage, 'https://4read.org/favicon.ico');
      expect(result.fallbackFields, contains('author'));
      expect(result.fallbackFields, contains('language'));
      expect(result.fallbackFields, contains('lowQCoverImage'));
    });

    test('does not alter non-4read source', () {
      final input = Audiobook.fromMap({
        'id': 'abc123',
        'title': 'LibriVox Story',
        'origin': 'librivox',
      });

      final result = FourReadOpenGuard.validateAndNormalizeAudiobook(
        input,
        stage: 'unit_test',
      );

      expect(result.isValid, isTrue);
      expect(result.audiobook!.id, 'abc123');
      expect(result.fallbackFields, isEmpty);
    });
  });
}
