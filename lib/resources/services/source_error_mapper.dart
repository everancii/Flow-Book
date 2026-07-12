/// Converts provider-specific exceptions into [SourceError] models.
library;

import 'dart:async';
import 'dart:io';

import 'package:audiobookflow/resources/models/source_error.dart';

/// Maps a raw exception from any provider into a [SourceError].
SourceError mapToSourceError(
  Object error, {
  required SourceProvider source,
  required SourceStage stage,
}) {
  if (source == SourceProvider.fourRead) return _mapFourRead(error, stage);
  if (source == SourceProvider.knigavuhe) return _mapKnigavuhe(error, stage);
  if (source == SourceProvider.youtube) return _mapYouTube(error, stage);
  return _mapGeneric(error, source: source, stage: stage);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

bool _isNetworkError(Object error) {
  if (error is SocketException) return true;
  if (error is HttpException) return true;
  if (error is HandshakeException) return true;
  final msg = error.toString().toLowerCase();
  return msg.contains('socket') ||
      msg.contains('network') ||
      msg.contains('connection refused') ||
      msg.contains('connection reset') ||
      msg.contains('host is unreachable') ||
      msg.contains('no address associated');
}

bool _isTimeout(Object error) {
  if (error is TimeoutException) return true;
  if (error is SocketException) {
    return error.message.toLowerCase().contains('timed out');
  }
  final msg = error.toString().toLowerCase();
  return msg.contains('timeout') || msg.contains('timed out');
}

SourceError _buildNetwork(
  SourceProvider source,
  SourceStage stage,
  String providerName,
  String msg,
) {
  return SourceError(
    source: source,
    stage: stage,
    type: SourceErrorType.network,
    title: 'Cannot reach $providerName',
    message:
        'Flow Book could not connect to $providerName. '
        'Check your internet and try again.',
    canRetry: true,
    canSearchAlternatives: true,
    debugMessage: msg,
  );
}

SourceError _buildTimeout(
  SourceProvider source,
  SourceStage stage,
  String providerName,
  String msg,
) {
  return SourceError(
    source: source,
    stage: stage,
    type: SourceErrorType.timeout,
    title: '$providerName took too long',
    message: 'The request to $providerName timed out. Try again in a moment.',
    canRetry: true,
    canSearchAlternatives: true,
    debugMessage: msg,
  );
}

// ---------------------------------------------------------------------------
// 4Read
// ---------------------------------------------------------------------------

SourceError _mapFourRead(Object error, SourceStage stage) {
  final msg = error.toString();

  if (msg.contains('403') || msg.contains('Forbidden')) {
    return SourceError(
      source: SourceProvider.fourRead,
      stage: stage,
      type: SourceErrorType.loginRequired,
      title: '4Read login required',
      message:
          '4Read requires you to log in before you can access this content.',
      canRetry: false,
      canSearchAlternatives: true,
      sourceUrl: 'https://4read.org',
      debugMessage: msg,
    );
  }

  if (msg.contains('404') || msg.contains('Not Found')) {
    return SourceError(
      source: SourceProvider.fourRead,
      stage: stage,
      type: SourceErrorType.notFound,
      title: 'Audiobook not found',
      message: 'This audiobook is no longer available on 4Read.',
      canRetry: false,
      canSearchAlternatives: true,
      debugMessage: msg,
    );
  }

  if (_isNetworkError(error)) {
    return _buildNetwork(
        SourceProvider.fourRead, stage, '4Read', msg);
  }

  if (_isTimeout(error)) {
    return _buildTimeout(
        SourceProvider.fourRead, stage, '4Read', msg);
  }

  if (msg.contains('parse') || msg.contains('Parse')) {
    return SourceError(
      source: SourceProvider.fourRead,
      stage: stage,
      type: SourceErrorType.parseFailure,
      title: 'Could not read 4Read data',
      message:
          'The 4Read page structure may have changed. '
          'Try again or search another source.',
      canRetry: true,
      canSearchAlternatives: true,
      debugMessage: msg,
    );
  }

  return SourceError(
    source: SourceProvider.fourRead,
    stage: stage,
    type: SourceErrorType.unknown,
    title: '4Read error',
    message:
        'Something went wrong with 4Read. Try again or search another source.',
    canRetry: true,
    canSearchAlternatives: true,
    debugMessage: msg,
  );
}

// ---------------------------------------------------------------------------
// Knigavuhe
// ---------------------------------------------------------------------------

SourceError _mapKnigavuhe(Object error, SourceStage stage) {
  final msg = error.toString();

  if (msg.contains('blocked') || msg.contains('Blocked') ||
      msg.contains('challenge') || msg.contains('captcha')) {
    return SourceError(
      source: SourceProvider.knigavuhe,
      stage: stage,
      type: SourceErrorType.blocked,
      title: 'Knigavuhe access blocked',
      message:
          'Knigavuhe is blocking automated requests. '
          'You can open the page in your browser instead.',
      canRetry: true,
      canSearchAlternatives: true,
      sourceUrl: 'https://knigavuhe.org',
      debugMessage: msg,
    );
  }

  if (msg.contains('not available') || msg.contains('purchase') ||
      msg.contains('Litres')) {
    return SourceError(
      source: SourceProvider.knigavuhe,
      stage: stage,
      type: SourceErrorType.notFound,
      title: 'Not available for free streaming',
      message:
          'This audiobook is only available for purchase and cannot be streamed.',
      canRetry: false,
      canSearchAlternatives: true,
      debugMessage: msg,
    );
  }

  if (_isNetworkError(error)) {
    return _buildNetwork(
        SourceProvider.knigavuhe, stage, 'Knigavuhe', msg);
  }

  if (_isTimeout(error)) {
    return _buildTimeout(
        SourceProvider.knigavuhe, stage, 'Knigavuhe', msg);
  }

  return SourceError(
    source: SourceProvider.knigavuhe,
    stage: stage,
    type: SourceErrorType.unknown,
    title: 'Knigavuhe error',
    message:
        'Something went wrong with Knigavuhe. '
        'Try again or search another source.',
    canRetry: true,
    canSearchAlternatives: true,
    debugMessage: msg,
  );
}

// ---------------------------------------------------------------------------
// YouTube
// ---------------------------------------------------------------------------

SourceError _mapYouTube(Object error, SourceStage stage) {
  final msg = error.toString();

  if (msg.contains('VideoUnavailable') || msg.contains('unavailable') ||
      msg.contains('removed')) {
    return SourceError(
      source: SourceProvider.youtube,
      stage: stage,
      type: SourceErrorType.notFound,
      title: 'Video unavailable',
      message: 'This video has been removed or is not available.',
      canRetry: false,
      canSearchAlternatives: true,
      debugMessage: msg,
    );
  }

  if (msg.contains('stream') || msg.contains('Stream') ||
      msg.contains('manifest')) {
    return SourceError(
      source: SourceProvider.youtube,
      stage: stage,
      type: SourceErrorType.streamUnavailable,
      title: 'Stream unavailable',
      message:
          'Could not get a playable audio stream from YouTube. '
          'The video format may not be supported.',
      canRetry: true,
      canSearchAlternatives: true,
      debugMessage: msg,
    );
  }

  if (_isNetworkError(error)) {
    return _buildNetwork(
        SourceProvider.youtube, stage, 'YouTube', msg);
  }

  if (_isTimeout(error)) {
    return _buildTimeout(
        SourceProvider.youtube, stage, 'YouTube', msg);
  }

  return SourceError(
    source: SourceProvider.youtube,
    stage: stage,
    type: SourceErrorType.unknown,
    title: 'YouTube error',
    message:
        'Something went wrong with YouTube. '
        'Try again or search another source.',
    canRetry: true,
    canSearchAlternatives: true,
    debugMessage: msg,
  );
}

// ---------------------------------------------------------------------------
// Generic fallback
// ---------------------------------------------------------------------------

SourceError _mapGeneric(
  Object error, {
  required SourceProvider source,
  required SourceStage stage,
}) {
  final msg = error.toString();
  final allowAlt = stage == SourceStage.search || stage == SourceStage.details;

  if (_isNetworkError(error)) {
    return SourceError(
      source: source,
      stage: stage,
      type: SourceErrorType.network,
      title: 'Connection error',
      message:
          'Could not connect to the server. '
          'Check your internet and try again.',
      canRetry: true,
      canSearchAlternatives: allowAlt,
      debugMessage: msg,
    );
  }

  if (_isTimeout(error)) {
    return SourceError(
      source: source,
      stage: stage,
      type: SourceErrorType.timeout,
      title: 'Request timed out',
      message: 'The server took too long to respond. Try again.',
      canRetry: true,
      canSearchAlternatives: allowAlt,
      debugMessage: msg,
    );
  }

  if (error is FormatException) {
    return SourceError(
      source: source,
      stage: stage,
      type: SourceErrorType.parseFailure,
      title: 'Could not read data',
      message:
          'The response from the server was not in the expected format.',
      canRetry: true,
      canSearchAlternatives: allowAlt,
      debugMessage: msg,
    );
  }

  return SourceError(
    source: source,
    stage: stage,
    type: SourceErrorType.unknown,
    title: 'Something went wrong',
    message:
        'This source did not return playable audio. '
        'Try again or search another source.',
    canRetry: true,
    canSearchAlternatives: allowAlt,
    debugMessage: msg,
  );
}
