import 'package:audiobookflow/utils/app_logger.dart';

class FourReadOpenTelemetry {
  static const String _tag = 'FourReadOpen';

  static void openAttempt({required String stage, String? audiobookId}) {
    AppLogger.info(
      'event=four_read_open_attempt source=4read stage=$stage audiobook_id=${_safe(audiobookId)}',
      _tag,
    );
  }

  static void validationFailure({
    required String stage,
    required String reason,
    String? audiobookId,
  }) {
    AppLogger.warning(
      'event=four_read_open_failure source=4read failure_type=validation stage=$stage reason=$reason audiobook_id=${_safe(audiobookId)}',
      _tag,
    );
  }

  static void runtimeFailure({
    required String stage,
    required Object error,
    String? audiobookId,
  }) {
    AppLogger.error(
      'event=four_read_open_failure source=4read failure_type=runtime stage=$stage audiobook_id=${_safe(audiobookId)} error=${_safe(error.toString())}',
      _tag,
    );
  }

  static void fallbackApplied({
    required String stage,
    required String field,
    String? audiobookId,
  }) {
    AppLogger.info(
      'event=four_read_open_fallback source=4read stage=$stage field=$field audiobook_id=${_safe(audiobookId)}',
      _tag,
    );
  }

  static String _safe(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return 'unknown';
    return v.replaceAll(RegExp(r'\s+'), '_');
  }
}
