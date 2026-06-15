import 'package:audiobookflow/widgets/low_and_high_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:audiobookflow/resources/designs/app_colors.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_guard.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_telemetry.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audiobookflow/widgets/rating_widget.dart';

class AudiobookItem extends StatelessWidget {
  final Audiobook audiobook;
  final double width;
  final double height;
  final void Function()? onLongPressed;

  const AudiobookItem({
    super.key,
    required this.audiobook,
    this.width = 175.0,
    this.height = 250.0,
    this.onLongPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Ink(
      width: width,
      height: height,
      child: Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(8),
          ),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(
            Radius.circular(8),
          ),
          splashColor: AppColors.primaryColor,
          splashFactory: InkRipple.splashFactory,
          onLongPress: onLongPressed,
          onTap: () {
            if (audiobook.origin == AppConstants.fourReadDirName) {
              final guarded = FourReadOpenGuard.validateAndNormalizeAudiobook(
                audiobook,
                stage: 'audiobook_item_tap',
              );
              if (!guarded.isValid) {
                final failureCode = guarded.failure?.code ?? 'unknown_failure';
                FourReadOpenTelemetry.validationFailure(
                  stage: 'audiobook_item_tap',
                  reason: failureCode,
                  audiobookId: audiobook.id,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'This 4Read title cannot be opened right now. Please retry or choose another title.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              final normalized = guarded.audiobook;
              if (normalized == null) {
                FourReadOpenTelemetry.validationFailure(
                  stage: 'audiobook_item_tap',
                  reason: 'normalized_audiobook_missing',
                  audiobookId: audiobook.id,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'This 4Read title cannot be opened right now. Please retry or choose another title.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              FourReadOpenTelemetry.openAttempt(
                stage: 'audiobook_item_tap',
                audiobookId: normalized.id,
              );
              context.push(
                '/audiobook-details',
                extra: {
                  'audiobook': normalized,
                  'isDownload': false,
                  'isYoutube': false,
                  'isLocal': false,
                  'isFourRead': true,
                },
              );
              return;
            }

            context.push(
              '/audiobook-details',
              extra: {
                'audiobook': audiobook,
                'isDownload': audiobook.origin == 'download',
                'isYoutube': audiobook.origin == 'youtube',
                'isLocal': audiobook.origin == 'local',
                'isFourRead': audiobook.origin == AppConstants.fourReadDirName,
              },
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                    child: LowAndHighImage(
                      lowQImage: audiobook.lowQCoverImage,
                      highQImage: audiobook.lowQCoverImage,
                      width: width,
                      height: width,
                    ),
                  ),
                  if (audiobook.origin == AppConstants.youtubeDirName &&
                      audiobook.id.length != 11)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.queue_music,
                                color: Colors.white, size: 11),
                            const SizedBox(width: 3),
                            Text(
                              'Playlist',
                              style: GoogleFonts.ubuntu(
                                textStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(
                  bottom: 8,
                  left: 8,
                  right: 8,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: width,
                      child: Text(
                        audiobook.title,
                        style: GoogleFonts.ubuntu(
                          textStyle: const TextStyle(
                            overflow: TextOverflow.ellipsis,
                            fontSize: 14,
                          ),
                        ),
                        maxLines: 1,
                      ),
                    ),
                    Text(
                      audiobook.author ?? 'Unknown',
                      style: GoogleFonts.ubuntu(
                        textStyle: const TextStyle(
                          overflow: TextOverflow.ellipsis,
                          fontSize: 12,
                        ),
                      ),
                      maxLines: 1,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RatingWidget(
                          rating: audiobook.rating ?? 0,
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.audiotrack,
                              size: 16,
                            ),
                            const SizedBox(
                              width: 5,
                            ),
                            Text(
                              audiobook.language ?? 'N/A',
                              style: GoogleFonts.ubuntu(
                                textStyle: const TextStyle(
                                  overflow: TextOverflow.ellipsis,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
