import 'package:audiobookflow/resources/designs/app_colors.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_guard.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_telemetry.dart';
import 'package:audiobookflow/screens/search/bloc/search_bloc.dart';
import 'package:audiobookflow/utils/app_constants.dart';
import 'package:audiobookflow/widgets/low_and_high_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SearchAudiobook extends StatefulWidget {
  const SearchAudiobook({super.key});

  @override
  State<SearchAudiobook> createState() => _SearchAudiobookState();
}

class _SearchAudiobookState extends State<SearchAudiobook> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late SearchBloc searchBloc;

  SearchSourceSelection sourceSelection = SearchSourceSelection.all;
  bool isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    searchBloc = context.read<SearchBloc>();
    sourceSelection = searchBloc.lastSourceSelection;

    _scrollController.addListener(() {
      if (!_scrollController.hasClients || isLoadingMore) return;

      final atBottom = _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 24;
      final state = searchBloc.state;
      if (atBottom &&
          state is SearchSuccess &&
          state.hasMoreResults &&
          (state.audiobooks.isNotEmpty)) {
        setState(() => isLoadingMore = true);
        searchBloc.add(EventLoadMoreResults());
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _doSearch() {
    FocusScope.of(context).unfocus();
    final text = _searchController.text.trim();
    if (text.isEmpty) return;

    searchBloc.add(
      EventSearchIconClicked(
        text,
        sourceSelection: sourceSelection,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Search Audiobooks',
          style: GoogleFonts.ubuntu(
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade900 : Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                          decoration: InputDecoration(
                            hintText: _getHintText(),
                            hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _doSearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _doSearch,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryColor
                                    .withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.search,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _SourceChoiceChips(
                  selected: sourceSelection,
                  onChanged: (selection) {
                    setState(() => sourceSelection = selection);
                    if (_searchController.text.trim().isNotEmpty) {
                      _doSearch();
                    }
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose which source to search, or keep both selected.',
                  style: GoogleFonts.ubuntu(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: BlocConsumer<SearchBloc, SearchState>(
              listener: (context, state) {
                if (state is SearchFailure) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.errorMessage),
                      backgroundColor: Colors.red.shade300,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else if (state is SearchSuccess) {
                  setState(() => isLoadingMore = false);
                }
              },
              builder: (context, state) {
                if (state is SearchInitial) {
                  return const _EmptyPrompt();
                }
                if (state is SearchLoading && !isLoadingMore) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryColor,
                    ),
                  );
                }
                if (state is SearchSuccess) {
                  if (state.librivoxAudiobooks.isEmpty &&
                      state.youtubeAudiobooks.isEmpty &&
                      state.archiveOrgAudiobooks.isEmpty &&
                      state.fourReadAudiobooks.isEmpty &&
                      state.knigavuheAudiobooks.isEmpty) {
                    return _NoResultsState(query: searchBloc.lastQuery ?? '');
                  }

                  final slivers = <Widget>[];

                  if (state.librivoxAudiobooks.isNotEmpty) {
                    slivers.add(
                      _SectionHeader(
                        title: 'LibriVox',
                        count: state.librivoxAudiobooks.length,
                        icon: Icons.menu_book_rounded,
                        accentColor: AppColors.primaryColor,
                      ),
                    );
                    slivers.add(
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _SearchResultTile(
                            audiobook: state.librivoxAudiobooks[index],
                          ),
                          childCount: state.librivoxAudiobooks.length,
                        ),
                      ),
                    );
                  }

                  if (state.youtubeAudiobooks.isNotEmpty) {
                    slivers.add(
                      _SectionHeader(
                        title: 'YouTube',
                        count: state.youtubeAudiobooks.length,
                        icon: Icons.smart_display_rounded,
                        accentColor: Colors.red,
                      ),
                    );
                    slivers.add(
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _SearchResultTile(
                            audiobook: state.youtubeAudiobooks[index],
                          ),
                          childCount: state.youtubeAudiobooks.length,
                        ),
                      ),
                    );
                  }

                  if (state.archiveOrgAudiobooks.isNotEmpty) {
                    slivers.add(
                      _SectionHeader(
                        title: 'Archive.org',
                        count: state.archiveOrgAudiobooks.length,
                        icon: Icons.cloud_download_rounded,
                        accentColor: const Color(0xFF00897B),
                      ),
                    );
                    slivers.add(
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _SearchResultTile(
                            audiobook: state.archiveOrgAudiobooks[index],
                          ),
                          childCount: state.archiveOrgAudiobooks.length,
                        ),
                      ),
                    );
                  }

                  if (state.fourReadAudiobooks.isNotEmpty) {
                    slivers.add(
                      _SectionHeader(
                        title: '4Read',
                        count: state.fourReadAudiobooks.length,
                        icon: Icons.library_books_rounded,
                        accentColor: const Color(0xFFFF8A00),
                      ),
                    );
                    slivers.add(
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _SearchResultTile(
                            audiobook: state.fourReadAudiobooks[index],
                          ),
                          childCount: state.fourReadAudiobooks.length,
                        ),
                      ),
                    );
                  }

                  if (state.knigavuheAudiobooks.isNotEmpty) {
                    slivers.add(
                      _SectionHeader(
                        title: 'knigavuhe',
                        count: state.knigavuheAudiobooks.length,
                        icon: Icons.headphones_rounded,
                        accentColor: const Color(0xFF9C27B0),
                      ),
                    );
                    slivers.add(
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _SearchResultTile(
                            audiobook: state.knigavuheAudiobooks[index],
                          ),
                          childCount: state.knigavuheAudiobooks.length,
                        ),
                      ),
                    );
                  }

                  if (isLoadingMore) {
                    slivers.add(
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: slivers,
                  );
                }

                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getHintText() {
    switch (sourceSelection) {
      case SearchSourceSelection.librivox:
        return 'Search LibriVox...';
      case SearchSourceSelection.youtube:
        return 'Search YouTube...';
      case SearchSourceSelection.archiveOrg:
        return 'Search Archive.org...';
      case SearchSourceSelection.fourRead:
        return 'Search 4Read UA...';
      case SearchSourceSelection.knigavuhe:
        return 'Search knigavuhe RU...';
      case SearchSourceSelection.all:
        return 'Search all sources...';
    }
  }
}

class _SearchResultTile extends StatelessWidget {
  final Audiobook audiobook;

  const _SearchResultTile({
    required this.audiobook,
  });

  bool get _isYoutube => audiobook.origin == AppConstants.youtubeDirName;
  bool get _isFourRead => audiobook.origin == AppConstants.fourReadDirName;
  bool get _isKnigavuhe => audiobook.origin == AppConstants.knigavuheDirName;
  bool get _isPlaylist => _isYoutube && audiobook.id.length != 11;

  @override
  Widget build(BuildContext context) {
    final sourceColor = _isYoutube
        ? Colors.red.shade700
        : _isFourRead
            ? const Color(0xFFFF8A00)
            : _isKnigavuhe
                ? const Color(0xFF9C27B0)
                : AppColors.primaryColor;
    final sourceLabel = _isPlaylist
        ? 'Playlist'
        : _isYoutube
            ? 'YouTube'
            : _isFourRead
                ? '4Read'
                : _isKnigavuhe
                    ? 'Knigavuhe'
                    : 'LibriVox';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        leading: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LowAndHighImage(
                lowQImage: audiobook.lowQCoverImage,
                highQImage: audiobook.lowQCoverImage,
                width: 60,
                height: 60,
              ),
            ),
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: sourceColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isPlaylist
                          ? Icons.queue_music
                          : _isYoutube
                              ? Icons.play_arrow_rounded
                              : Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 10,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      sourceLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        title: Text(
          audiobook.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                audiobook.author ?? 'Unknown',
                style: TextStyle(color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              _SourceBadge(
                label: sourceLabel,
                accentColor: sourceColor,
              ),
            ],
          ),
        ),
        onTap: () {
          if (_isFourRead) {
            final guarded = FourReadOpenGuard.validateAndNormalizeAudiobook(
              audiobook,
              stage: 'search_tile_tap',
            );
            if (!guarded.isValid) {
              final failureCode = guarded.failure?.code ?? 'unknown_failure';
              FourReadOpenTelemetry.validationFailure(
                stage: 'search_tile_tap',
                reason: failureCode,
                audiobookId: audiobook.id,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'This 4Read title cannot be opened right now. Please retry or choose another title.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            final normalized = guarded.audiobook;
            if (normalized == null) {
              FourReadOpenTelemetry.validationFailure(
                stage: 'search_tile_tap',
                reason: 'normalized_audiobook_missing',
                audiobookId: audiobook.id,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'This 4Read title cannot be opened right now. Please retry or choose another title.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            FourReadOpenTelemetry.openAttempt(
              stage: 'search_tile_tap',
              audiobookId: normalized.id,
            );
            context.push(
              '/audiobook-details',
              extra: {
                'audiobook': normalized,
                'isDownload': false,
                'isYoutube': false,
                'isYoutubeSearch': false,
                'isLocal': false,
                'isFourRead': true,
              },
            );
            return;
          }

          context.push(
            '/audiobook-details',
            extra: {
              'audiobook': audiobook,
              'isDownload': false,
              'isYoutube': _isYoutube,
              'isYoutubeSearch': _isYoutube,
              'isLocal': false,
              'isFourRead': _isFourRead,
              'isKnigavuhe': _isKnigavuhe,
            },
          );
        },
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String label;
  final Color accentColor;

  const _SourceBadge({
    required this.label,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accentColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color accentColor;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.ubuntu(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceChoiceChips extends StatelessWidget {
  final SearchSourceSelection selected;
  final ValueChanged<SearchSourceSelection> onChanged;

  const _SourceChoiceChips({
    required this.selected,
    required this.onChanged,
  });

  static const Map<SearchSourceSelection, String> _sourceKeys = {
    SearchSourceSelection.librivox: 'librivox',
    SearchSourceSelection.youtube: 'youtube',
    SearchSourceSelection.archiveOrg: 'archiveOrg',
    SearchSourceSelection.fourRead: 'fourRead',
    SearchSourceSelection.knigavuhe: 'knigavuhe',
  };

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('settings');
    final enabledSources = List<String>.from(
      box.get('enabledSearchSources',
          defaultValue: ['librivox', 'youtube', 'archiveOrg', 'fourRead', 'knigavuhe']),
    );

    final chips = <Widget>[
      _chip(
        label: 'All',
        icon: Icons.layers_rounded,
        value: SearchSourceSelection.all,
        accentColor: AppColors.primaryColor,
      ),
    ];

    for (final entry in _sourceKeys.entries) {
      if (enabledSources.contains(entry.value)) {
        chips.add(const SizedBox(width: 8));
        chips.add(_chip(
          label: _sourceLabels[entry.value] ?? entry.value,
          icon: _sourceIcons[entry.value] ?? Icons.source,
          value: entry.key,
          accentColor: _sourceColors[entry.value] ?? AppColors.primaryColor,
        ));
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 4),
      child: Row(children: chips),
    );
  }

  static const Map<String, String> _sourceLabels = {
    'librivox': 'LibriVox',
    'youtube': 'YouTube',
    'archiveOrg': 'Archive.org',
    'fourRead': '4Read',
    'knigavuhe': 'Knigavuhe',
  };

  static const Map<String, IconData> _sourceIcons = {
    'librivox': Icons.menu_book_rounded,
    'youtube': Icons.smart_display_rounded,
    'archiveOrg': Icons.cloud_download_rounded,
    'fourRead': Icons.library_books_rounded,
    'knigavuhe': Icons.headphones_rounded,
  };

  static const Map<String, Color> _sourceColors = {
    'librivox': AppColors.primaryColor,
    'youtube': Colors.red,
    'archiveOrg': Color(0xFF00897B),
    'fourRead': Color(0xFFFF8A00),
    'knigavuhe': Color(0xFF9C27B0),
  };

  Widget _chip({
    required String label,
    required IconData icon,
    required SearchSourceSelection value,
    required Color accentColor,
  }) {
    final sel = selected == value;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: sel ? Colors.white : accentColor),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: sel,
      onSelected: (_) => onChanged(value),
      selectedColor: accentColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(color: sel ? Colors.white : accentColor),
      side: BorderSide(color: accentColor.withValues(alpha: 0.3)),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_rounded,
            size: 72,
            color: AppColors.primaryColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Search LibriVox, YouTube, and 4Read',
            style: GoogleFonts.ubuntu(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Find free audiobooks, lectures, and stories in one place',
            style: GoogleFonts.ubuntu(
              fontSize: 13,
              color: Colors.grey.shade400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  final String query;

  const _NoResultsState({
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No results found',
            style: GoogleFonts.ubuntu(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          if (query.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'for "$query"',
              style: GoogleFonts.ubuntu(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
