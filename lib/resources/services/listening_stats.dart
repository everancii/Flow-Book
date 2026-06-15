import 'package:hive/hive.dart';

class ListeningStats {
  static const String _boxName = 'listening_stats_box';
  late Box _box;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  int get totalListeningSeconds => _box.get('totalSeconds', defaultValue: 0);
  int get totalBooksFinished => _box.get('booksFinished', defaultValue: 0);
  int get totalSessions => _box.get('totalSessions', defaultValue: 0);
  String? get lastListeningDate => _box.get('lastDate');

  List<String> get listeningStreak {
    final streak = _box.get('streak', defaultValue: <String>[]) as List;
    return streak.cast<String>();
  }

  Future<void> recordSession(int seconds) async {
    final current = totalListeningSeconds;
    await _box.put('totalSeconds', current + seconds);
    await _box.put('totalSessions', totalSessions + 1);

    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _box.put('lastDate', today);

    final streak = listeningStreak;
    if (!streak.contains(today)) {
      streak.add(today);
      if (streak.length > 365) streak.removeAt(0);
      await _box.put('streak', streak);
    }
  }

  Future<void> recordBookFinished() async {
    await _box.put('booksFinished', totalBooksFinished + 1);
  }

  int get currentStreak {
    final streak = listeningStreak;
    if (streak.isEmpty) return 0;

    final today = DateTime.now();
    int count = 0;
    for (int i = 0; i < 365; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
      if (streak.contains(dateStr)) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  String get formattedTotalTime {
    final h = totalListeningSeconds ~/ 3600;
    final m = (totalListeningSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
