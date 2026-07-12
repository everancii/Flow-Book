/// Shared source error model for provider and playback failures.
///
/// Every source failure in the app should be converted into a [SourceError]
/// near the provider boundary so the UI can show a consistent recovery panel.
library;

import 'package:meta/meta.dart';

@immutable
class SourceError {
  const SourceError({
    required this.source,
    required this.stage,
    required this.type,
    required this.title,
    required this.message,
    this.canRetry = false,
    this.canSearchAlternatives = false,
    this.sourceUrl,
    this.debugMessage,
  });

  /// Which audiobook provider produced this error.
  final SourceProvider source;

  /// What operation was being attempted when the failure occurred.
  final SourceStage stage;

  /// Classification of the failure kind.
  final SourceErrorType type;

  /// Short user-facing title shown in the recovery panel header.
  final String title;

  /// Plain user-facing explanation of what happened.
  final String message;

  /// Whether the Retry action should be offered.
  final bool canRetry;

  /// Whether "Search other sources" should be offered.
  final bool canSearchAlternatives;

  /// Optional URL for opening the provider page or login screen.
  final String? sourceUrl;

  /// Developer-facing detail for logs only — never shown to the user.
  final String? debugMessage;

  @override
  String toString() =>
      'SourceError($source/$stage/$type: $title — $message'
      '${debugMessage != null ? ' [$debugMessage]' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceError &&
          source == other.source &&
          stage == other.stage &&
          type == other.type &&
          title == other.title &&
          message == other.message &&
          canRetry == other.canRetry &&
          canSearchAlternatives == other.canSearchAlternatives &&
          sourceUrl == other.sourceUrl;

  @override
  int get hashCode => Object.hash(
        source,
        stage,
        type,
        title,
        message,
        canRetry,
        canSearchAlternatives,
        sourceUrl,
      );
}

/// Known audiobook source providers.
enum SourceProvider {
  librivox,
  fourRead,
  knigavuhe,
  youtube,
  local,
  unknown,
}

/// Operations that can fail.
enum SourceStage {
  search,
  list,
  details,
  stream,
  playback,
  login,
  update,
  download,
}

/// Failure classification.
enum SourceErrorType {
  network,
  notFound,
  blocked,
  loginRequired,
  streamUnavailable,
  parseFailure,
  unsupported,
  timeout,
  storage,
  unknown,
}

/// Describes a single user-facing action available after a source failure.
@immutable
class SourceRecoveryAction {
  const SourceRecoveryAction({
    required this.type,
    required this.label,
    this.audiobookTitle,
    this.sourceUrl,
  });

  /// The kind of action.
  final RecoveryActionType type;

  /// User-facing button label.
  final String label;

  /// Optional title used by [RecoveryActionType.searchAlternatives] to
  /// prefill the search query.
  final String? audiobookTitle;

  /// Optional URL used by [RecoveryActionType.openSourcePage].
  final String? sourceUrl;
}

/// The set of supported recovery actions.
enum RecoveryActionType {
  retry,
  resumeCached,
  searchAlternatives,
  login,
  openSourcePage,
  updateApp,
}
