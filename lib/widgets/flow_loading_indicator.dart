import 'dart:async';

import 'package:audiobookflow/resources/designs/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A reusable loading indicator that gives the user real feedback instead of a
/// bare spinning circle.
///
/// It can show:
///  - a **determinate** ring with the percentage drawn in its centre, when the
///    backend can honestly report progress ([value] in 0.0–1.0);
///  - a **label** describing what is happening ("Searching…");
///  - a **detail** line ("3 of 5 sources");
///  - a **live elapsed timer** ("0:04") so the user can tell the app isn't
///    frozen when no numeric progress is possible ([showElapsed]).
///
/// Use [compact] for small inline placements (pagination rows, buttons) where
/// only the ring + a short label fit.
class FlowLoadingIndicator extends StatefulWidget {
  /// Progress fraction in 0.0–1.0. `null` renders an indeterminate spinner.
  final double? value;

  /// Primary description of the action in progress.
  final String? label;

  /// Secondary line (e.g. "3 of 5 sources", "Loading videos (page 2)").
  final String? detail;

  /// When true, shows a live `m:ss` timer that ticks every second.
  final bool showElapsed;

  /// Compact variant: smaller ring, no elapsed timer, suitable for inline rows.
  final bool compact;

  const FlowLoadingIndicator({
    super.key,
    this.value,
    this.label,
    this.detail,
    this.showElapsed = false,
    this.compact = false,
  });

  @override
  State<FlowLoadingIndicator> createState() => _FlowLoadingIndicatorState();
}

class _FlowLoadingIndicatorState extends State<FlowLoadingIndicator> {
  Timer? _timer;
  final DateTime _startedAt = DateTime.now();
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    if (!widget.showElapsed) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(_startedAt).inSeconds;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatElapsed(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(1, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final labelColor =
        isDark ? AppColors.darkTextColor : AppColors.textColor;
    final detailColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    final ringSize = widget.compact ? 32.0 : 56.0;
    final strokeWidth = widget.compact ? 3.0 : 4.0;

    Widget ring = SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: widget.value,
            strokeWidth: strokeWidth,
            color: AppColors.primaryColor,
            backgroundColor:
                widget.value != null
                    ? AppColors.primaryColor.withValues(alpha: 0.15)
                    : null,
          ),
          if (widget.value != null)
            Text(
              '${(widget.value!.clamp(0, 1) * 100).round()}%',
              style: GoogleFonts.ubuntu(
                fontSize: widget.compact ? 9 : 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryColor,
              ),
            ),
        ],
      ),
    );

    // Compact: ring + short label only (horizontal, for inline rows).
    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ring,
          if (widget.label != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.label!,
                style: GoogleFonts.ubuntu(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      );
    }

    // Full: centered column.
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ring,
        if (widget.label != null) ...[
          const SizedBox(height: 14),
          Text(
            widget.label!,
            style: GoogleFonts.ubuntu(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (widget.detail != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.detail!,
            style: GoogleFonts.ubuntu(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: detailColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (widget.showElapsed) ...[
          const SizedBox(height: 6),
          Text(
            _formatElapsed(_elapsedSeconds),
            style: GoogleFonts.ubuntu(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: detailColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );
  }
}
