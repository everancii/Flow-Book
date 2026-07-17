import 'package:audiobookflow/resources/designs/theme_notifier.dart';
import 'package:audiobookflow/screens/home/widgets/favourite_section.dart';
import 'package:audiobookflow/screens/setting/listening_stats_screen.dart';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:audiobookflow/utils/app_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../resources/latest_version_fetch.dart';
import '../../resources/models/latest_version_fetch_model.dart';
import '../../utils/version_compare.dart';
import 'widgets/history_section.dart';
import 'widgets/update_prompt_dialog.dart';
import 'widgets/app_bar_actions.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final LatestVersionFetch _latestVersionFetch = LatestVersionFetch();
  String currentVersion = '';
  bool _knigavuheEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadVersionAndCheck();
    _readKnigavuheSetting();
    AppEvents.searchSourcesChanged.stream.listen((_) {
      if (mounted) _readKnigavuheSetting();
    });
  }

  void _readKnigavuheSetting() {
    final box = Hive.box('settings');
    final sources = List<String>.from(
      box.get('enabledSearchSources',
          defaultValue: ['librivox', 'youtube', 'archiveOrg', 'fourRead', 'soundbooks']),
    );
    setState(() {
      _knigavuheEnabled = sources.contains('knigavuhe');
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadVersionAndCheck() async {
    try {
      final info = await PlatformAssetBundle().load('assets/version.json');
      currentVersion = String.fromCharCodes(info.buffer.asUint8List()).trim();
    } catch (e) {
      AppLogger.debug('Failed to load version from assets: $e');
    }
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    final result = await _latestVersionFetch.getLatestVersion();

    result.fold(
      (error) => AppLogger.debug(error),
      (latestVersionModel) async {
        if (latestVersionModel.latestVersion != null &&
            compareVersions(latestVersionModel.latestVersion!, currentVersion) >
                0) {
          _showUpdatePrompt(latestVersionModel);
        }
      },
    );
  }

  void _showUpdatePrompt(LatestVersionFetchModel versionModel) {
    showDialog(
      context: context,
      builder: (BuildContext context) => UpdatePromptDialog(
        currentVersion: currentVersion,
        newVersion: versionModel.latestVersion!,
        changelogs: versionModel.changelogs,
        onUpdate: () async {
          Navigator.of(context).pop();
          await _downloadAndInstallUpdate(versionModel);
        },
      ),
    );
  }

  Future<void> _downloadAndInstallUpdate(
    LatestVersionFetchModel versionModel,
  ) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloading update...')),
    );

    try {
      await _latestVersionFetch.downloadAndInstallUpdate(versionModel);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening Android installer...')),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      final message = e.code == 'INSTALL_PERMISSION_REQUIRED'
          ? 'Allow Flow Book to install updates, then tap Update again.'
          : e.message ?? 'Could not install the update.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Flow Book',
          style: GoogleFonts.ubuntu(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ListeningStatsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Listening Stats',
          ),
          AppBarActions(
            themeNotifier: themeNotifier,
            onSettingsPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 290),
              child: const HistorySection(),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildTop100Spotlight(context),
          ),
          if (_knigavuheEnabled)
            SliverToBoxAdapter(
              child: _buildKnigavuheSpotlight(context),
            ),
          SliverToBoxAdapter(
            child: _buildSoundBooksSpotlight(context),
          ),
          SliverToBoxAdapter(
            child: FavouriteSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildTop100Spotlight(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/four_read_top'),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8A00), Color(0xFFFFB347)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40FF8A00),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x22FFFFFF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.emoji_events,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '4Read Top 100',
                          style: GoogleFonts.ubuntu(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Discover the highest-rated audiobooks in one tap',
                          style: GoogleFonts.ubuntu(
                            color: const Color(0xFFFDF2E8),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKnigavuheSpotlight(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/knigavuhe_lists'),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF9C27B0), Color(0xFFBA68C8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x409C27B0),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x22FFFFFF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.headphones,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Knigavuhe RU',
                          style: GoogleFonts.ubuntu(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'New, popular, and top-rated Russian audiobooks',
                          style: GoogleFonts.ubuntu(
                            color: const Color(0xFFF3E5F5),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSoundBooksSpotlight(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/soundbooks_lists'),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF009688), Color(0xFF4DB6AC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40009688),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x22FFFFFF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.record_voice_over,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sound-Books UA',
                          style: GoogleFonts.ubuntu(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Latest, popular, and Top-100 Ukrainian audiobooks',
                          style: GoogleFonts.ubuntu(
                            color: const Color(0xFFE0F2F1),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
