import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_telemetry.dart';
import 'package:audiobookflow/utils/app_constants.dart';

enum FourReadOpenFailureType { validation, runtime }

class FourReadOpenValidationFailure {
  final String code;
  final String message;

  const FourReadOpenValidationFailure({
    required this.code,
    required this.message,
  });
}

class FourReadOpenGuardResult {
  final Audiobook? audiobook;
  final FourReadOpenValidationFailure? failure;
  final List<String> fallbackFields;

  const FourReadOpenGuardResult._({
    required this.audiobook,
    required this.failure,
    required this.fallbackFields,
  });

  bool get isValid => failure == null && audiobook != null;

  factory FourReadOpenGuardResult.success(
    Audiobook audiobook, {
    List<String> fallbackFields = const [],
  }) {
    return FourReadOpenGuardResult._(
      audiobook: audiobook,
      failure: null,
      fallbackFields: fallbackFields,
    );
  }

  factory FourReadOpenGuardResult.failure(
      FourReadOpenValidationFailure failure) {
    return FourReadOpenGuardResult._(
      audiobook: null,
      failure: failure,
      fallbackFields: const [],
    );
  }
}

class FourReadOpenGuard {
  static const String _defaultCoverImage = 'https://4read.org/favicon.ico';

  // Required for open flow: canonical article URL for playlist/page fetch.
  static FourReadOpenValidationFailure? validateArticleUrl(String rawId) {
    final normalized = normalizeArticleUrl(rawId);
    if (normalized == null) {
      return const FourReadOpenValidationFailure(
        code: 'missing_or_invalid_article_url',
        message: 'This 4Read title is missing a valid article URL.',
      );
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.isAbsolute) {
      return const FourReadOpenValidationFailure(
        code: 'invalid_article_url_format',
        message: 'This 4Read title has an invalid article URL.',
      );
    }

    final host = uri.host.toLowerCase();
    if (!host.contains('4read.org')) {
      return const FourReadOpenValidationFailure(
        code: 'unsupported_source_host',
        message: 'This title is not recognized as a 4Read source.',
      );
    }

    if (uri.path.isEmpty || uri.path == '/') {
      return const FourReadOpenValidationFailure(
        code: 'missing_article_path',
        message: 'This 4Read title does not include a valid article path.',
      );
    }

    return null;
  }

  static String? normalizeArticleUrl(String rawId) {
    final trimmed = rawId.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }

    if (trimmed.startsWith('/')) {
      return 'https://4read.org$trimmed';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    if (!uri.hasScheme) {
      return 'https://4read.org/${trimmed.replaceFirst(RegExp(r'^/+'), '')}';
    }

    return trimmed;
  }

  static FourReadOpenGuardResult validateAndNormalizeAudiobook(
    Audiobook input, {
    required String stage,
  }) {
    if (input.origin != AppConstants.fourReadDirName) {
      return FourReadOpenGuardResult.success(input);
    }

    final normalizedId = normalizeArticleUrl(input.id);
    final failure = validateArticleUrl(input.id);
    if (failure != null || normalizedId == null) {
      final resolvedFailure = failure ??
          const FourReadOpenValidationFailure(
            code: 'invalid_article_url',
            message:
                'This 4Read title cannot be opened because URL is invalid.',
          );
      FourReadOpenTelemetry.validationFailure(
        stage: stage,
        reason: resolvedFailure.code,
        audiobookId: input.id,
      );
      return FourReadOpenGuardResult.failure(resolvedFailure);
    }

    final fallbackFields = <String>[];
    String fallbackOrValue(String? value, String fallback, String field) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
      fallbackFields.add(field);
      FourReadOpenTelemetry.fallbackApplied(
        stage: stage,
        field: field,
        audiobookId: normalizedId,
      );
      return fallback;
    }

    final normalized = input.copyWith(
      id: normalizedId,
      title: fallbackOrValue(input.title, 'Unknown title', 'title'),
      author: fallbackOrValue(input.author, 'Unknown', 'author'),
      description:
          input.description?.trim().isNotEmpty == true ? input.description : '',
      lowQCoverImage: fallbackOrValue(
          input.lowQCoverImage, _defaultCoverImage, 'lowQCoverImage'),
      language: fallbackOrValue(input.language, 'uk', 'language'),
      origin: AppConstants.fourReadDirName,
    );

    return FourReadOpenGuardResult.success(
      normalized,
      fallbackFields: fallbackFields,
    );
  }
}
