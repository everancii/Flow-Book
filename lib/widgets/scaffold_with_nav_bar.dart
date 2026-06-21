import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:audiobookflow/widgets/mini_audio_player.dart';
import 'package:audiobookflow/widgets/global_loading_overlay.dart';
import 'package:provider/provider.dart';
import 'package:audiobookflow/resources/services/audio_handler_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audiobookflow/resources/services/my_audio_handler.dart';

class ScaffoldWithNavBar extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const ScaffoldWithNavBar(this.navigationShell, {super.key});

  @override
  State<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends State<ScaffoldWithNavBar> {
  late Box<dynamic> playingAudiobookDetailsBox;
  late Stream<BoxEvent> _boxEventStream;

  @override
  void initState() {
    super.initState();
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');
    _boxEventStream = playingAudiobookDetailsBox.watch();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BoxEvent>(
      stream: _boxEventStream,
      builder: (context, snapshot) {
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final handler = context.select<AudioHandlerProvider, MyAudioHandler>((p) => p.audioHandler);

        // one BottomNavigationBar instance to reuse
        final navBar = BottomNavigationBar(
          showSelectedLabels: false,
          showUnselectedLabels: false,
          selectedFontSize: 0,
          unselectedFontSize: 0,
          type: BottomNavigationBarType.fixed,
          unselectedItemColor: Colors.grey,
          selectedItemColor: const Color.fromRGBO(204, 119, 34, 1),
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
            //BottomNavigationBarItem(icon: Icon(Icons.favorite), label: ''),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: ''),
            BottomNavigationBarItem(icon: Icon(Icons.download), label: ''),
          ],
          currentIndex: widget.navigationShell.currentIndex,
          onTap: _onTap,
        );

        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          initialData: handler.playbackState.value,
          builder: (context, snapshot) {
            final st = snapshot.data;
            final isLoading = st?.processingState == AudioProcessingState.loading;

            if (playingAudiobookDetailsBox.isEmpty) {
              return Scaffold(
                body: GlobalLoadingOverlay(
                  isLoading: isLoading,
                  child: widget.navigationShell,
                ),
                bottomNavigationBar: keyboardOpen ? null : navBar,
              );
            }

            return Scaffold(
              body: GlobalLoadingOverlay(
                isLoading: isLoading,
                child: MiniAudioPlayer(
                  playingAudiobookDetailsBox: playingAudiobookDetailsBox,
                  navigationShell: widget.navigationShell,
                  bottomNavigationBar: navBar,
                  bottomNavBarSize: const NavigationBarThemeData().height ?? 70,
                  isKeyboardOpen: keyboardOpen,
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }
}
