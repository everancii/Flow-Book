import 'package:audiobookflow/resources/designs/app_colors.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_audiobook_notifier.dart';
import 'package:audiobookflow/widgets/audiobook_item.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class FourReadImportsSection extends StatefulWidget {
  const FourReadImportsSection({super.key});

  @override
  State<FourReadImportsSection> createState() => _FourReadImportsSectionState();
}

class _FourReadImportsSectionState extends State<FourReadImportsSection> {
  @override
  void initState() {
    super.initState();
    // Removed automatic fetch on startup
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLightMode = theme.brightness == Brightness.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '4Read Imports',
                style: GoogleFonts.ubuntu(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isLightMode
                      ? AppColors.textColor
                      : AppColors.darkTextColor,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/four_read_top'),
                    icon: const Icon(
                      Icons.emoji_events_outlined,
                      color: Color(0xFFFF8A00),
                      size: 20,
                    ),
                    label: Text(
                      'Top 100',
                      style: GoogleFonts.ubuntu(
                        fontSize: 14,
                        color: const Color(0xFFFF8A00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      FourReadAudiobookNotifier().refresh();
                    },
                    child: const Icon(
                      Icons.refresh,
                      color: Color(0xFFFF8A00),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 250,
          child: Consumer<FourReadAudiobookNotifier>(
            builder: (context, notifier, child) {
              if (notifier.isLoading) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (notifier.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Error loading 4Read imports',
                        style: GoogleFonts.ubuntu(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final audiobooks = notifier.audiobooks;

              if (audiobooks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.library_books_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No 4Read imports yet',
                        style: GoogleFonts.ubuntu(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Import books from 4Read to see them here',
                        style: GoogleFonts.ubuntu(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                itemCount: audiobooks.length,
                itemBuilder: (context, index) {
                  final audiobook = audiobooks[index];
                  return AudiobookItem(
                    audiobook: audiobook,
                    width: 175,
                    height: 250,
                    onLongPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: Text(
                              'Delete Audiobook',
                              style: GoogleFonts.ubuntu(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            content: Text(
                              'Are you sure you want to delete "${audiobook.title}"? This action cannot be undone.',
                              style: GoogleFonts.ubuntu(),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.ubuntu(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();

                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );

                                  final success =
                                      await FourReadAudiobookNotifier()
                                          .deleteAudiobook(audiobook.id);

                                  if (context.mounted) {
                                    Navigator.of(context).pop();

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? 'Audiobook deleted successfully'
                                              : 'Failed to delete audiobook',
                                          style: GoogleFonts.ubuntu(),
                                        ),
                                        backgroundColor:
                                            success ? Colors.green : Colors.red,
                                      ),
                                    );
                                  }
                                },
                                child: Text(
                                  'Delete',
                                  style: GoogleFonts.ubuntu(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
