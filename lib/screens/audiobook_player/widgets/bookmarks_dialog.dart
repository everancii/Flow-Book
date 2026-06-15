import 'package:audiobookflow/resources/services/bookmark_service.dart';
import 'package:audiobookflow/resources/services/my_audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BookmarksDialog extends StatefulWidget {
  final MyAudioHandler audioHandler;
  final String audiobookId;
  final String audiobookTitle;

  const BookmarksDialog({
    super.key,
    required this.audioHandler,
    required this.audiobookId,
    required this.audiobookTitle,
  });

  @override
  State<BookmarksDialog> createState() => _BookmarksDialogState();
}

class _BookmarksDialogState extends State<BookmarksDialog> {
  final BookmarkService _bookmarkService = BookmarkService();
  List<Bookmark> _bookmarks = [];

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  void _loadBookmarks() {
    setState(() {
      _bookmarks = _bookmarkService.getBookmarks(widget.audiobookId);
    });
  }

  Future<void> _addBookmark() async {
    final currentIndex = widget.audioHandler.currentIndex ?? 0;
    final position = widget.audioHandler.position.inMilliseconds;

    final noteController = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Bookmark', style: GoogleFonts.ubuntu()),
        content: TextField(
          controller: noteController,
          decoration: InputDecoration(
            hintText: 'Add a note (optional)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, noteController.text),
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (note != null) {
      await _bookmarkService.addBookmark(Bookmark(
        audiobookId: widget.audiobookId,
        trackIndex: currentIndex,
        positionMs: position,
        note: note.isEmpty ? null : note,
      ));
      _loadBookmarks();
    }
  }

  void _seekToBookmark(Bookmark bookmark) {
    if (bookmark.trackIndex != widget.audioHandler.currentIndex) {
      widget.audioHandler.skipToQueueItem(bookmark.trackIndex);
    }
    widget.audioHandler.seek(Duration(milliseconds: bookmark.positionMs));
    Navigator.pop(context);
  }

  Future<void> _deleteBookmark(int index) async {
    await _bookmarkService.removeBookmark(widget.audiobookId, index);
    _loadBookmarks();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Bookmarks',
              style: GoogleFonts.ubuntu(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add_circle, color: Colors.deepOrange),
            onPressed: _addBookmark,
            tooltip: 'Add bookmark at current position',
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _bookmarks.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_border, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'No bookmarks yet',
                      style: GoogleFonts.ubuntu(color: Colors.grey),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tap + to save your current position',
                      style: GoogleFonts.ubuntu(
                          fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _bookmarks.length,
                itemBuilder: (context, index) {
                  final bookmark = _bookmarks[index];
                  return ListTile(
                    leading: Icon(Icons.bookmark, color: Colors.deepOrange),
                    title: Text(
                      'Track ${bookmark.trackIndex + 1} — ${bookmark.timeLabel}',
                      style: GoogleFonts.ubuntu(fontWeight: FontWeight.w600),
                    ),
                    subtitle: bookmark.note != null
                        ? Text(bookmark.note!,
                            style: GoogleFonts.ubuntu(fontSize: 12))
                        : null,
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteBookmark(index),
                    ),
                    onTap: () => _seekToBookmark(bookmark),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    );
  }
}
