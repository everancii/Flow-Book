import 'dart:io';

import 'package:audiobookflow/resources/designs/theme_notifier.dart';
import 'package:audiobookflow/resources/designs/themes.dart';
import 'package:audiobookflow/resources/services/download/download_manager.dart';
import 'package:audiobookflow/resources/services/update_data_backup_service.dart';
import 'package:audiobookflow/resources/services/youtube/youtube_audiobook_notifier.dart';
import 'package:audiobookflow/resources/services/youtube/webview_keep_alive_provider.dart';
import 'package:audiobookflow/screens/recommendation/recommendation_screen.dart';
import 'package:audiobookflow/screens/setting/settings.dart';
import 'package:back_button_interceptor/back_button_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/screens/audiobook_details/audiobook_details.dart';
import 'package:audiobookflow/screens/audiobook_details/bloc/audiobook_details_bloc.dart';
import 'package:audiobookflow/screens/audiobook_player/audiobook_player.dart';
import 'package:audiobookflow/screens/four_read_top/four_read_top_screen.dart';
import 'package:audiobookflow/screens/knigavuhe_lists/knigavuhe_lists_screen.dart';
import 'package:audiobookflow/screens/download_audiobook/downloads_page.dart';
import 'package:audiobookflow/screens/genre_audiobooks/genre_audiobooks.dart';
import 'package:audiobookflow/screens/home/home.dart';
import 'package:audiobookflow/screens/search/bloc/search_bloc.dart';
import 'package:audiobookflow/screens/search/search_audiobook.dart';
import 'package:audiobookflow/resources/services/audio_handler_provider.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_audiobook_notifier.dart';
import 'package:audiobookflow/utils/app_logger.dart';

import 'package:audiobookflow/widgets/scaffold_with_nav_bar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initHive();

  await AppLogger.initialize();

  final audioHandlerProvider = AudioHandlerProvider();
  final weSlideController = WeSlideController();
  final themeNotifier = ThemeNotifier();
  final youtubeAudiobookNotifier = YoutubeAudiobookNotifier();
  final fourReadAudiobookNotifier = FourReadAudiobookNotifier();
  final webViewKeepAliveProvider = WebViewKeepAliveProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => audioHandlerProvider),
        ChangeNotifierProvider(create: (_) => weSlideController),
        ChangeNotifierProvider(create: (_) => themeNotifier),
        ChangeNotifierProvider(create: (_) => youtubeAudiobookNotifier),
        ChangeNotifierProvider(create: (_) => fourReadAudiobookNotifier),
        ChangeNotifierProvider(create: (_) => webViewKeepAliveProvider),
      ],
      child: const MyApp(),
    ),
  );

  // Initialize AFTER the first frame so UI shows immediately.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    audioHandlerProvider.initialize();
  });

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
}

int isRecommendScreen = 0;

Future<void> initHive() async {
  final documentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(documentDir.path);
  await Hive.openBox('favourite_audiobooks_box');
  await Hive.openBox('download_status_box');
  await Hive.openBox('playing_audiobook_details_box');
  await Hive.openBox('theme_mode_box');
  await Hive.openBox('history_of_audiobook_box');
  await Hive.openBox('recommened_audiobooks_box');
  await Hive.openBox('dual_mode_box'); // 0 = audiobook home, 1 = podcast home
  await Hive.openBox('language_prefs_box');
  await Hive.openBox('bookmarks_box');
  await Hive.openBox('listening_stats_box');
  await Hive.openBox('four_read_auth');
  await Hive.openBox('settings');
  Box recommendedAudiobooksBox = Hive.box('recommened_audiobooks_box');

  isRecommendScreen = 0;

  await UpdateDataBackupService.restoreMissingDataAfterUpdate();

  DownloadManager().cleanStaleStatuses();
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _sectionNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Create router once per app, using isRecommendScreen set by initHive().
  late final GoRouter _router = _buildRouter();

  GoRouter _buildRouter() {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation:
          isRecommendScreen == 1 ? '/recommendation_screen' : '/home',
      routes: [
        GoRoute(
          path: '/recommendation_screen',
          name: 'recommendation_screen',
          builder: (context, state) => const RecommendationScreen(),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              ScaffoldWithNavBar(navigationShell),
          branches: [
            StatefulShellBranch(
              navigatorKey: _sectionNavigatorKey,
              routes: [
                GoRoute(
                  path: '/home',
                  name: 'home',
                  builder: (context, state) => const Home(),
                ),
                GoRoute(
                  path: '/settings',
                  name: 'settings',
                  builder: (context, state) => const Settings(),
                ),
                GoRoute(
                  path: '/genre_audiobooks',
                  name: 'genre_audiobooks',
                  builder: (context, state) {
                    return GenreAudiobooksScreen(
                      genre: state.extra as String,
                    );
                  },
                ),
                GoRoute(
                  path: '/audiobook-details',
                  builder: (context, state) {
                    final extras = state.extra as Map<String, dynamic>;
                    final audiobook = extras['audiobook'] as Audiobook;
                    final isDownload = extras['isDownload'] as bool;
                    final isYoutube = extras['isYoutube'] as bool;
                    final isLocal = extras['isLocal'] as bool;
                    final isYoutubeSearch =
                        extras['isYoutubeSearch'] as bool? ?? false;
                    final isFourRead = extras['isFourRead'] as bool? ?? false;
                    final isKnigavuhe = extras['isKnigavuhe'] as bool? ?? false;
                    return AudiobookDetails(
                      audiobook: audiobook,
                      isDownload: isDownload,
                      isYoutube: isYoutube,
                      isLocal: isLocal,
                      isYoutubeSearch: isYoutubeSearch,
                      isFourRead: isFourRead,
                      isKnigavuhe: isKnigavuhe,
                    );
                  },
                ),
                GoRoute(
                  path: '/player',
                  name: 'player',
                  builder: (context, state) => const AudiobookPlayer(),
                ),
                GoRoute(
                  path: '/four_read_top',
                  name: 'four_read_top',
                  builder: (context, state) => const FourReadTopScreen(),
                ),
                GoRoute(
                  path: '/knigavuhe_lists',
                  name: 'knigavuhe_lists',
                  builder: (context, state) => const KnigavuheListsScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/search',
                  name: 'search',
                  builder: (context, state) => const SearchAudiobook(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/download',
                  name: 'download',
                  builder: (context, state) => const DownloadsPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  bool _backButtonInterceptor(bool stopDefaultButtonEvent, RouteInfo info) {
    AppLogger.debug(
        'initialized back button interceptor', 'BackButtonInterceptor');
    WeSlideController weSlideController =
        Provider.of<WeSlideController>(context, listen: false);
    if (weSlideController.isOpened) {
      AppLogger.debug('closing', 'BackButtonInterceptor');
      weSlideController.hide();
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    BackButtonInterceptor.add(_backButtonInterceptor);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, _) {
        return MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (context) => AudiobookDetailsBloc(),
            ),
            BlocProvider(
              create: (context) => SearchBloc(),
            ),
          ],
          child: MaterialApp.router(
            title: 'Flow Book',
            theme: themeNotifier.getThemeData(),
            themeMode: themeNotifier.themeMode,
            routerConfig: _router,
            debugShowCheckedModeBanner: false,
          ),
        );
      },
    );
  }
}
