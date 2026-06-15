import 'package:hive/hive.dart';

class Bookmark {
  final String audiobookId;
  final int trackIndex;
  final int positionMs;
  final String? note;
  final DateTime createdAt;

  Bookmark({
    required this.audiobookId,
    required this.trackIndex,
    required this.positionMs,
    this.note,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'audiobookId': audiobookId,
        'trackIndex': trackIndex,
        'positionMs': positionMs,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Bookmark.fromMap(Map<dynamic, dynamic> map) => Bookmark(
        audiobookId: map['audiobookId'] as String,
        trackIndex: map['trackIndex'] as int,
        positionMs: map['positionMs'] as int,
        note: map['note'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  String get timeLabel {
    final d = Duration(milliseconds: positionMs);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class BookmarkService {
  static const String _boxName = 'bookmarks_box';

  Box get _box => Hive.box(_boxName);

  List<Bookmark> getBookmarks(String audiobookId) {
    final raw = _box.get(audiobookId, defaultValue: []) as List;
    return raw.map((e) => Bookmark.fromMap(e)).toList()
      ..sort((a, b) {
        final trackCmp = a.trackIndex.compareTo(b.trackIndex);
        return trackCmp != 0 ? trackCmp : a.positionMs.compareTo(b.positionMs);
      });
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    final existing = getBookmarks(bookmark.audiobookId);
    existing.add(bookmark);
    await _box.put(
      bookmark.audiobookId,
      existing.map((b) => b.toMap()).toList(),
    );
  }

  Future<void> removeBookmark(String audiobookId, int index) async {
    final existing = getBookmarks(audiobookId);
    if (index >= 0 && index < existing.length) {
      existing.removeAt(index);
      await _box.put(
        audiobookId,
        existing.map((b) => b.toMap()).toList(),
      );
    }
  }

  bool hasBookmarkAt(String audiobookId, int trackIndex, int positionMs,
      {int toleranceMs = 5000}) {
    return getBookmarks(audiobookId).any((b) =>
        b.trackIndex == trackIndex &&
        (b.positionMs - positionMs).abs() < toleranceMs);
  }
}
