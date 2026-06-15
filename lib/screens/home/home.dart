import 'package:audiobookflow/resources/designs/theme_notifier.dart';
import 'package:audiobookflow/screens/home/widgets/favourite_section.dart';
import 'package:audiobookflow/screens/setting/listening_stats_screen.dart';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:audiobookflow/utils/permission_helper.dart';

import '../../resources/latest_version_fetch.dart';
import '../../resources/models/latest_version_fetch_model.dart';
import 'widgets/history_section.dart';
import 'widgets/update_prompt_dialog.dart';
import 'widgets/app_bar_actions.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  // Update & version
  final LatestVersionFetch _latestVersionFetch = LatestVersionFetch();
  final String currentVersion = "3.0.0";

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    final result = await _latestVersionFetch.getLatestVersion();

    result.fold(
      (error) => AppLogger.debug(error),
      (latestVersionModel) async {
        if (latestVersionModel.latestVersion != null &&
            latestVersionModel.latestVersion!.compareTo(currentVersion) > 0) {
          await _handleUpdateAvailable(latestVersionModel);
        }
      },
    );
  }

  Future<void> _handleUpdateAvailable(
    LatestVersionFetchModel versionModel,
  ) async {
    final permissionGranted =
        await PermissionHelper.handleUpdatePermission(context);

    if (permissionGranted) {
      _proceedWithUpdate(versionModel);
    }
  }

  Future<void> _proceedWithUpdate(
    LatestVersionFetchModel versionModel,
  ) async {
    final existingApk =
        await _latestVersionFetch.getApkPath(versionModel.latestVersion!);

    if (existingApk != null) {
      _showUpdatePrompt(versionModel);
    } else {
      final success =
          await _latestVersionFetch.downloadUpdate(versionModel.latestVersion!);
      if (success) {
        _showUpdatePrompt(versionModel);
      }
    }
  }

  void _showUpdatePrompt(LatestVersionFetchModel versionModel) {
    showDialog(
      context: context,
      builder: (BuildContext context) => UpdatePromptDialog(
        currentVersion: currentVersion,
        newVersion: versionModel.latestVersion!,
        changelogs: versionModel.changelogs ?? [],
        onUpdate: () =>
            _latestVersionFetch.installUpdate(versionModel.latestVersion!),
      ),
    );
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
          // --- Recently Played section ---
          SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 290),
              child: const HistorySection(),
            ),
          ),
          // --- 4Read Top 100 spotlight ---
          SliverToBoxAdapter(
            child: _buildTop100Spotlight(context),
          ),
          // --- Knigavuhe spotlight ---
          SliverToBoxAdapter(
            child: _buildKnigavuheSpotlight(context),
          ),
          // --- Favourite section ---
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
}
