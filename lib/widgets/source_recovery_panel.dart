/// Reusable recovery panel shown when a source failure occurs.
library;

import 'package:audiobookflow/resources/models/source_error.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Callback signature for recovery action taps.
typedef RecoveryActionCallback = void Function(SourceRecoveryAction action);

class SourceRecoveryPanel extends StatelessWidget {
  const SourceRecoveryPanel({
    super.key,
    required this.error,
    required this.onAction,
  });

  final SourceError error;
  final RecoveryActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _backgroundColor(error.type),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor(error.type), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_iconForType(error.type),
                color: _iconColor(error.type), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(error.title,
                  style: GoogleFonts.ubuntu(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _textColor(error.type))),
            ),
          ]),
          const SizedBox(height: 10),
          Text(error.message,
              style: GoogleFonts.ubuntu(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: _textColor(error.type).withValues(alpha: 0.85),
                  height: 1.4)),
          const SizedBox(height: 16),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _buildActions(context)),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final actions = <SourceRecoveryAction>[];
    if (error.canRetry) {
      actions.add(const SourceRecoveryAction(
          type: RecoveryActionType.retry, label: 'Retry'));
    }
    if (error.canSearchAlternatives) {
      actions.add(const SourceRecoveryAction(
          type: RecoveryActionType.searchAlternatives,
          label: 'Search other sources'));
    }
    if (error.type == SourceErrorType.loginRequired) {
      actions.add(SourceRecoveryAction(
          type: RecoveryActionType.login,
          label: 'Login',
          sourceUrl: error.sourceUrl));
    }
    if (error.type == SourceErrorType.blocked && error.sourceUrl != null) {
      actions.add(SourceRecoveryAction(
          type: RecoveryActionType.openSourcePage,
          label: 'Open in browser',
          sourceUrl: error.sourceUrl));
    }

    return actions.map((action) {
      final isPrimary = action.type == RecoveryActionType.retry;
      return ActionChip(
        label: Text(action.label,
            style: GoogleFonts.ubuntu(
                fontSize: 13,
                fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
                color:
                    isPrimary ? Colors.white : _iconColor(error.type))),
        backgroundColor:
            isPrimary ? _iconColor(error.type) : Colors.transparent,
        side: isPrimary
            ? null
            : BorderSide(
                color: _iconColor(error.type).withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        onPressed: () => onAction(action),
      );
    }).toList();
  }

  // ── Color helpers ──────────────────────────────────────────────────

  static Color _backgroundColor(SourceErrorType type) {
    switch (type) {
      case SourceErrorType.loginRequired:
        return const Color(0xFFFFF8E1);
      case SourceErrorType.blocked:
        return const Color(0xFFFBE9E7);
      case SourceErrorType.notFound:
        return const Color(0xFFF5F5F5);
      case SourceErrorType.network:
      case SourceErrorType.timeout:
        return const Color(0xFFE3F2FD);
      default:
        return const Color(0xFFFFF3E0);
    }
  }

  static Color _borderColor(SourceErrorType type) {
    switch (type) {
      case SourceErrorType.loginRequired:
        return const Color(0xFFFFE082);
      case SourceErrorType.blocked:
        return const Color(0xFFFFAB91);
      case SourceErrorType.notFound:
        return const Color(0xFFE0E0E0);
      case SourceErrorType.network:
      case SourceErrorType.timeout:
        return const Color(0xFF90CAF9);
      default:
        return const Color(0xFFFFCC80);
    }
  }

  static Color _iconColor(SourceErrorType type) {
    switch (type) {
      case SourceErrorType.loginRequired:
        return const Color(0xFFF57F17);
      case SourceErrorType.blocked:
        return const Color(0xFFD84315);
      case SourceErrorType.notFound:
        return const Color(0xFF757575);
      case SourceErrorType.network:
      case SourceErrorType.timeout:
        return const Color(0xFF1565C0);
      default:
        return const Color(0xFFE65100);
    }
  }

  static Color _textColor(SourceErrorType type) {
    switch (type) {
      case SourceErrorType.loginRequired:
        return const Color(0xFF4E342E);
      case SourceErrorType.blocked:
        return const Color(0xFFBF360C);
      case SourceErrorType.notFound:
        return const Color(0xFF424242);
      case SourceErrorType.network:
      case SourceErrorType.timeout:
        return const Color(0xFF0D47A1);
      default:
        return const Color(0xFF3E2723);
    }
  }

  static IconData _iconForType(SourceErrorType type) {
    switch (type) {
      case SourceErrorType.network:
        return Icons.wifi_off_rounded;
      case SourceErrorType.timeout:
        return Icons.timer_off_rounded;
      case SourceErrorType.notFound:
        return Icons.search_off_rounded;
      case SourceErrorType.blocked:
        return Icons.block_rounded;
      case SourceErrorType.loginRequired:
        return Icons.lock_outline_rounded;
      case SourceErrorType.streamUnavailable:
        return Icons.stream_rounded;
      case SourceErrorType.parseFailure:
        return Icons.broken_image_rounded;
      case SourceErrorType.storage:
        return Icons.storage_rounded;
      case SourceErrorType.unsupported:
        return Icons.not_interested_rounded;
      case SourceErrorType.unknown:
        return Icons.help_outline_rounded;
    }
  }
}
