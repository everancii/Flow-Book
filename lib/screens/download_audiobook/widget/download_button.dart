import 'package:audiobookflow/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/services/download/download_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audiobookflow/utils/permission_helper.dart';
import 'dart:convert';
import 'dart:io';

class DownloadButton extends StatefulWidget {
  final Audiobook audiobook;
  final List<AudiobookFile> audiobookFiles;

  const DownloadButton({
    super.key,
    required this.audiobook,
    required this.audiobookFiles,
  });

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  final DownloadManager _downloadManager = DownloadManager();
  double _progress = 0;
  bool _isDownloading = false;
  bool _isDownloaded = false;

  /// Replaces characters not valid in directory names (e.g. 4read URLs used as IDs)
  static String _safeDirectoryName(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.]'), '_');

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  void _loadInitialState() {
    final safeId = _safeDirectoryName(widget.audiobook.id);
    _progress = _downloadManager.getProgress(safeId);
    _isDownloading = _downloadManager.isDownloading(safeId);
    _isDownloaded = _downloadManager.isDownloaded(safeId);
  }

  Future<void> _handleNotificationPermission(BuildContext context) async {
    try {
      // Try to get notification permission, but don't block download if denied
      await PermissionHelper.handleDownloadPermissionWithDialog(context);

      // Start download regardless of permission result
      // (notifications just won't show if permission denied)
      await _startDownload();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startDownload() async {
    if (!mounted) return;

    setState(() {
      _isDownloading = true;
    });

    // Convert AudiobookFile list to the required map format
    final List<Map<String, dynamic>> files = widget.audiobookFiles
        .map((file) => {
              'title': file.title,
              'url': file.url,
            })
        .toList();

    try {
      // we will save audiobook and files in the
      Directory? extDir;
      try {
        extDir = await getExternalStorageDirectory();
      } catch (_) {}
      final appDir = extDir ?? await getApplicationDocumentsDirectory();

      // Create parent downloads directory if it doesn't exist
      final downloadsDir = Directory('${appDir.path}/downloads');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final downloadDir = Directory(
          '${appDir.path}/downloads/${_safeDirectoryName(widget.audiobook.id)}');
      if (!await downloadDir.exists()) {
        await downloadDir.create();
      }
      // Now create a file name audiobook.txt and save the audiobook details
      final audiobookFile = File('${downloadDir.path}/audiobook.txt');
      // Create a modified copy of the audiobook with origin set to 'download'
      final modifiedAudiobook =
          Map<String, dynamic>.from(widget.audiobook.toMap())
            ..['origin'] = 'download';
      await audiobookFile.writeAsString(jsonEncode(modifiedAudiobook));

      // Now create a file name files.txt and save the audiobook files
      final filesFile = File('${downloadDir.path}/files.txt');
      await filesFile.writeAsString(
        jsonEncode(files),
      );

      await _downloadManager.downloadAudiobook(
        _safeDirectoryName(widget.audiobook.id),
        widget.audiobook.title,
        files,
        (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
        (completed) {
          if (!mounted) return;

          setState(() {
            _isDownloading = false;
            _isDownloaded = completed;
          });

          if (completed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Download completed: ${widget.audiobook.title}'),
              ),
            );
          }
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isDownloading = false;
      });

      AppLogger.debug(e.toString());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDownloaded) {
      return IconButton(
        onPressed: () => context.push('/download'),
        icon: const Icon(
          Icons.cloud_done_outlined,
          size: 26,
        ),
      );
    } else if (_isDownloading) {
      return GestureDetector(
        onTap: () => context.push('/download'),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                value: _progress,
                strokeWidth: 2.5,
              ),
            ),
            Text(
              '${(_progress * 100).toInt()}%',
              style: GoogleFonts.ubuntu(
                fontSize: 8,
              ),
            ),
          ],
        ),
      );
    }

    return IconButton(
      onPressed: () => _handleNotificationPermission(context),
      icon: const Icon(
        Icons.cloud_download_outlined,
        size: 26,
      ),
    );
  }
}
