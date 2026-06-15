import 'dart:convert';
import 'dart:io';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/download/download_manager.dart';
import 'package:path_provider/path_provider.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final DownloadManager _downloadManager = DownloadManager();

  Future<void> _openDownloadFolder() async {
    try {
      final directory = await getExternalStorageDirectory();
      final downloadsPath = '${directory?.path}/downloads';
      final downloadsDir = Directory(downloadsPath);

      if (!await downloadsDir.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Downloads folder does not exist yet.')),
          );
        }
        return;
      }

      AppLogger.debug('Attempting to open downloads folder: $downloadsPath');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Downloads folder: $downloadsPath (Manual navigation may be required)')),
        );
      }
    } catch (e) {
      AppLogger.debug("Error opening download folder: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open download folder: $e')),
        );
      }
    }
  }

  Future<void> _handleItemDeletion(
      BuildContext context, String audiobookId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$title"?', style: GoogleFonts.ubuntu()),
        content: const Text(
            'This will remove the downloaded files from your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // cancelDownload now handles both file cleanup and Hive status removal.
      _downloadManager.cancelDownload(audiobookId);
      
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('"$title" has been deleted.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Downloads',
          style: GoogleFonts.ubuntu(
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: _openDownloadFolder,
            tooltip: 'Open Downloads Folder',
          ),
        ],
        elevation: 1,
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box('download_status_box').listenable(),
        builder: (context, Box<dynamic> box, _) {
          final allStatuses = box.values
              .whereType<Map<dynamic, dynamic>>()
              .toList();

          allStatuses.sort((a, b) {
            final DateTime? dateA = a['downloadDate'] != null
                ? DateTime.tryParse(a['downloadDate'])
                : null;
            final DateTime? dateB = b['downloadDate'] != null
                ? DateTime.tryParse(b['downloadDate'])
                : null;
            if (dateA != null && dateB != null) {
              return dateB.compareTo(dateA);
            }
            return (a['audiobookTitle'] as String? ?? "")
                .compareTo(b['audiobookTitle'] as String? ?? "");
          });

          final activeDownloads = allStatuses
              .where((status) =>
                  (status['isDownloading'] == true ||
                      status['isPaused'] == true) &&
                  status['isCompleted'] != true &&
                  status['error'] == null)
              .toList();
          final erroredDownloads = allStatuses
              .where((status) =>
                  status['error'] != null && status['isCompleted'] != true)
              .toList();
          final completedDownloads = allStatuses
              .where((status) =>
                  status['isCompleted'] == true && status['error'] == null)
              .toList();

          if (allStatuses.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 20),
                  Text(
                    'No Downloads Yet',
                    style: GoogleFonts.ubuntu(
                      fontSize: 20,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Books you download will appear here.',
                    style: GoogleFonts.lato(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              if (activeDownloads.isNotEmpty) ...[
                _buildSectionHeader('Active Downloads', activeDownloads.length,
                    context, Icons.download_outlined),
                ...activeDownloads.map((status) {
                  final String audiobookId = status['audiobookId'] as String;
                  return _buildDownloadItem(
                    context,
                    status,
                    onCancel: () =>
                        _downloadManager.cancelDownload(audiobookId),
                  );
                }),
                const SizedBox(height: 16),
              ],
              if (erroredDownloads.isNotEmpty) ...[
                _buildSectionHeader('Failed Downloads', erroredDownloads.length,
                    context, Icons.warning_amber_outlined,
                    headerColor: Colors.red.shade300),
                ...erroredDownloads.map((status) => _buildDownloadItem(
                    context, status,
                    onDelete: () => _handleItemDeletion(
                        context,
                        status['audiobookId'] as String,
                        status['audiobookTitle'] as String),
                    onRetry: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Retry for "${status['audiobookTitle']}" not yet implemented.')),
                      );
                    })),
                const SizedBox(height: 16),
              ],
              if (completedDownloads.isNotEmpty) ...[
                _buildSectionHeader('Completed', completedDownloads.length,
                    context, Icons.check_circle_outline),
                ...completedDownloads.map((status) => _buildDownloadItem(
                      context,
                      status,
                      onDelete: () => _handleItemDeletion(
                          context,
                          status['audiobookId'] as String,
                          status['audiobookTitle'] as String),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, int count, BuildContext context, IconData icon,
      {Color? headerColor}) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(icon,
              color: headerColor ??
                  (isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700),
              size: 20),
          const SizedBox(width: 10),
          Text(
            title,
            style: GoogleFonts.ubuntu(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: headerColor ??
                  (isDarkMode ? Colors.grey.shade300 : Colors.grey.shade800),
            ),
          ),
          const SizedBox(width: 8),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (headerColor ??
                        (isDarkMode
                            ? Colors.grey.shade700
                            : Colors.grey.shade300))
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color:
                      isDarkMode ? Colors.grey.shade200 : Colors.grey.shade800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openDownloadedAudiobook(
      BuildContext context, String audiobookId, String audiobookTitle) async {
    try {
      Directory? extDir;
      try {
        extDir = await getExternalStorageDirectory();
      } catch (_) {}
      final appDir = extDir ?? await getApplicationDocumentsDirectory();
      final metadataFile =
          File('${appDir.path}/downloads/$audiobookId/audiobook.txt');

      late final Audiobook audiobook;

      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        audiobook =
            Audiobook.fromMap(jsonDecode(content) as Map<String, dynamic>);
      } else {
        AppLogger.debug(
            'Warning: Metadata file not found for $audiobookId. Playing with minimal data.');
        audiobook = Audiobook.fromMap({
          'id': audiobookId,
          'title': audiobookTitle,
          'origin': 'download',
        });
      }

      AppLogger.debug('Playing downloaded audiobook: ${audiobook.title}');
      if (!mounted) return;
      this.context.push(
        '/audiobook-details',
        extra: {
          'audiobook': audiobook,
          'isDownload': true,
          'isYoutube': false,
          'isLocal': false,
        },
      );
    } catch (e) {
      AppLogger.debug('Error preparing to play audiobook $audiobookId: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Error playing: ${e.toString()}')),
      );
    }
  }

  Widget _buildDownloadItem(
    BuildContext context,
    Map<dynamic, dynamic> status, {
    VoidCallback? onCancel,
    VoidCallback? onDelete,
    VoidCallback? onRetry,
  }) {
    final String audiobookId = status['audiobookId'] as String;
    final String audiobookTitle = status['audiobookTitle'] as String;
    final bool isDownloading = status['isDownloading'] == true &&
        status['isCompleted'] != true &&
        status['error'] == null &&
        status['isPaused'] != true;
    final bool isPaused = status['isPaused'] == true &&
        status['isCompleted'] != true &&
        status['error'] == null;
    final bool isCompleted =
        status['isCompleted'] == true && status['error'] == null;
    final String? errorMessage = status['error'] as String?;
    final bool hasError = errorMessage != null;
    final double progress = (status['progress'] as num?)?.toDouble() ?? 0.0;

    final String? downloadDateStr = status['downloadDate'] as String?;
    String formattedDate = '';
    if (downloadDateStr != null) {
      try {
        formattedDate =
            DateFormat('MMM d, yyyy').format(DateTime.parse(downloadDateStr));
      } catch (_) {}
    }

    // Determine icon and color based on state
    IconData itemIcon;
    Color itemIconColor;
    Color progressColor = Theme.of(context).colorScheme.primary;

    if (isDownloading) {
      itemIcon = Icons.arrow_downward;
      itemIconColor = Theme.of(context).colorScheme.primary;
    } else if (isPaused) {
      itemIcon = Icons.pause_circle_outline;
      itemIconColor = Colors.orange.shade600;
      progressColor = Colors.orange.shade600;
    } else if (isCompleted) {
      itemIcon = Icons.check_circle_outline;
      itemIconColor = Colors.green.shade600;
    } else if (hasError) {
      itemIcon = Icons.error_outline;
      itemIconColor = Theme.of(context).colorScheme.error;
    } else {
      itemIcon = Icons.description_outlined;
      itemIconColor = Colors.grey.shade500;
    }

    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: itemIconColor.withValues(alpha: 0.15),
                child: Icon(itemIcon, color: itemIconColor, size: 26),
              ),
              title: Text(
                audiobookTitle,
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: (isDownloading || isPaused)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor:
                                  progressColor.withValues(alpha: 0.2),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(progressColor),
                              minHeight: 5,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            isPaused
                                ? 'Paused at ${(progress * 100).toInt()}%'
                                : '${(progress * 100).toInt()}%',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : hasError
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'Error: $errorMessage',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : isCompleted
                          ? Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                'Downloaded on $formattedDate',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 12),
                              ),
                            )
                          : null,
              onTap: isCompleted
                  ? () => _openDownloadedAudiobook(
                      context, audiobookId, audiobookTitle)
                  : null,
              trailing: _buildTrailingActions(
                context: context,
                isDownloading: isDownloading,
                isPaused: isPaused,
                isCompleted: isCompleted,
                hasError: hasError,
                onCancel: onCancel,
                onDelete: onDelete,
                onRetry: onRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailingActions({
    required BuildContext context,
    required bool isDownloading,
    required bool isPaused,
    required bool isCompleted,
    required bool hasError,
    VoidCallback? onCancel,
    VoidCallback? onDelete,
    VoidCallback? onRetry,
  }) {
    List<Widget> actions = [];

    if ((isDownloading || isPaused) && onCancel != null) {
      actions.add(IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: onCancel,
          color: Theme.of(context).colorScheme.error));
    }

    if ((isCompleted || hasError) && onDelete != null) {
      actions.add(IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: onDelete,
          color: Theme.of(context).colorScheme.error));
    }
    if (hasError && onRetry != null) {
      actions.add(IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Retry',
          onPressed: onRetry,
          color: Colors.blueAccent));
    }

    if (actions.isEmpty) {
      return const SizedBox(width: 48);
    }

    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }
}
