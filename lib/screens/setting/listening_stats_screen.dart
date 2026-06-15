import 'package:audiobookflow/resources/services/listening_stats.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ListeningStatsScreen extends StatefulWidget {
  const ListeningStatsScreen({super.key});

  @override
  State<ListeningStatsScreen> createState() => _ListeningStatsScreenState();
}

class _ListeningStatsScreenState extends State<ListeningStatsScreen> {
  final ListeningStats _stats = ListeningStats();

  @override
  void initState() {
    super.initState();
    _stats.init();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Listening Stats', style: GoogleFonts.ubuntu()),
        backgroundColor: isDark ? Colors.grey[850] : Colors.white,
      ),
      body: FutureBuilder(
        future: Future.value(),
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _StatCard(
                  icon: Icons.headphones,
                  label: 'Total Listening Time',
                  value: _stats.formattedTotalTime,
                  color: Colors.deepOrange,
                ),
                const SizedBox(height: 16),
                _StatCard(
                  icon: Icons.local_fire_department,
                  label: 'Current Streak',
                  value: '${_stats.currentStreak} days',
                  color: Colors.amber,
                ),
                const SizedBox(height: 16),
                _StatCard(
                  icon: Icons.book,
                  label: 'Books Finished',
                  value: '${_stats.totalBooksFinished}',
                  color: Colors.green,
                ),
                const SizedBox(height: 16),
                _StatCard(
                  icon: Icons.play_circle,
                  label: 'Total Sessions',
                  value: '${_stats.totalSessions}',
                  color: Colors.blue,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.ubuntu(fontSize: 15),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.ubuntu(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
