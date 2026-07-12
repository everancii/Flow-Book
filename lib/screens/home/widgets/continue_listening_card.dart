/// A prominent card shown at the top of Home that lets the user
/// resume their last audiobook with one tap.
library;

import 'package:audiobookflow/resources/models/source_error.dart';
import 'package:audiobookflow/resources/services/resume_listening_service.dart';
import 'package:audiobookflow/widgets/source_recovery_panel.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

typedef ResumeCallback = void Function(ResumeState state);
typedef ErrorActionCallback = void Function(SourceRecoveryAction action);

class ContinueListeningCard extends StatelessWidget {
  const ContinueListeningCard({
    super.key,
    required this.state,
    required this.onPlay,
    this.error,
    this.onErrorAction,
  });

  final ResumeState? state;
  final SourceError? error;
  final ResumeCallback onPlay;
  final ErrorActionCallback? onErrorAction;

  @override
  Widget build(BuildContext context) {
    if (state == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF4CAF50)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x401B5E20),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    _buildCover(state!),
                    const SizedBox(width: 14),
                    Expanded(child: _buildInfo(state!)),
                    const SizedBox(width: 8),
                    _buildPlayButton(),
                  ],
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SourceRecoveryPanel(
                    error: error!,
                    onAction: onErrorAction ?? (_) {},
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(ResumeState s) {
    final url = s.audiobook.lowQCoverImage;
    if (url.isEmpty) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0x22FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.headphones, color: Colors.white, size: 28),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(url,
          width: 60, height: 60, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.headphones,
                color: Colors.white, size: 28),
          )),
    );
  }

  Widget _buildInfo(ResumeState s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Continue Listening',
            style: GoogleFonts.ubuntu(
                color: const Color(0xFFA5D6A7),
                fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(s.audiobook.title,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ubuntu(
                color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        if (s.currentChapterTitle != null)
          Text(s.currentChapterTitle!,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.ubuntu(
                  color: const Color(0xFFC8E6C9),
                  fontSize: 13, fontWeight: FontWeight.w400)),
        const SizedBox(height: 4),
        _buildSourceChip(s.source),
      ],
    );
  }

  Widget _buildSourceChip(String source) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_sourceLabel(source),
          style: GoogleFonts.ubuntu(
              color: Colors.white, fontSize: 11,
              fontWeight: FontWeight.w500)),
    );
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'librivox': return 'LibriVox';
      case 'youtube': return 'YouTube';
      case 'fourRead':
      case 'four_read': return '4Read';
      case 'knigavuhe': return 'Knigavuhe';
      case 'download': return 'Downloaded';
      case 'local': return 'Local';
      default: return source.isNotEmpty ? source : 'Unknown';
    }
  }

  Widget _buildPlayButton() {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: state != null ? () => onPlay(state!) : null,
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Icon(Icons.play_arrow_rounded,
              color: Color(0xFF1B5E20), size: 28),
        ),
      ),
    );
  }
}
