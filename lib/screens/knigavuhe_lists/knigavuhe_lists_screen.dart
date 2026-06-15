import 'package:audiobookflow/resources/designs/app_colors.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/screens/knigavuhe_lists/bloc/knigavuhe_lists_bloc.dart';
import 'package:audiobookflow/widgets/low_and_high_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

enum _ListTab { newBooks, popular, rating }

class KnigavuheListsScreen extends StatefulWidget {
  const KnigavuheListsScreen({super.key});

  @override
  State<KnigavuheListsScreen> createState() => _KnigavuheListsScreenState();
}

class _KnigavuheListsScreenState extends State<KnigavuheListsScreen> {
  late final KnigavuheListsBloc _bloc;
  _ListTab _selectedTab = _ListTab.newBooks;
  String _selectedPeriod = 'alltime';

  static const _periods = {
    'today': 'Day',
    'week': 'Week',
    'month': 'Month',
    'alltime': 'All Time',
  };

  @override
  void initState() {
    super.initState();
    _bloc = KnigavuheListsBloc()..add(FetchKnigavuheLists());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  void _onPeriodChanged(String period) {
    setState(() => _selectedPeriod = period);
    _bloc.add(FetchKnigavuheLists(period: period));
  }

  List<Audiobook> _currentBooks(KnigavuheListsLoaded state) {
    switch (_selectedTab) {
      case _ListTab.newBooks:
        return state.newBooks;
      case _ListTab.popular:
        return state.popularBooks;
      case _ListTab.rating:
        return state.ratingBooks;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            'Knigavuhe RU',
            style: GoogleFonts.ubuntu(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(100),
            child: Column(
              children: [
                // Tabs
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TabButton(
                      label: 'Новинки',
                      isSelected: _selectedTab == _ListTab.newBooks,
                      onTap: () => setState(() => _selectedTab = _ListTab.newBooks),
                    ),
                    _TabButton(
                      label: 'Популярные',
                      isSelected: _selectedTab == _ListTab.popular,
                      onTap: () => setState(() => _selectedTab = _ListTab.popular),
                    ),
                    _TabButton(
                      label: 'Рейтинг',
                      isSelected: _selectedTab == _ListTab.rating,
                      onTap: () => setState(() => _selectedTab = _ListTab.rating),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Period filters
                if (_selectedTab != _ListTab.newBooks)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _periods.entries.map((entry) {
                      final isSelected = _selectedPeriod == entry.key;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(entry.value, style: const TextStyle(fontSize: 12)),
                          selected: isSelected,
                          onSelected: (_) => _onPeriodChanged(entry.key),
                          selectedColor: AppColors.primaryColor,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[600],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        body: BlocBuilder<KnigavuheListsBloc, KnigavuheListsState>(
          builder: (context, state) {
            if (state is KnigavuheListsLoading || state is KnigavuheListsInitial) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primaryColor));
            }
            if (state is KnigavuheListsError) {
              return _ErrorView(
                message: state.message,
                onRetry: () => _bloc.add(FetchKnigavuheLists(period: _selectedPeriod)),
              );
            }
            if (state is KnigavuheListsLoaded) {
              final books = _currentBooks(state);
              if (books.isEmpty) {
                return const Center(child: Text('No books found'));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: books.length,
                itemBuilder: (context, index) {
                  return _BookTile(book: books[index]);
                },
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.primaryColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.ubuntu(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.primaryColor : Colors.grey[600],
          ),
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final Audiobook book;
  const _BookTile({required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        context.push(
          '/audiobook-details',
          extra: {
            'audiobook': book,
            'isDownload': false,
            'isYoutube': false,
            'isLocal': false,
            'isFourRead': false,
            'isKnigavuhe': true,
          },
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 110,
                child: LowAndHighImage(
                  lowQImage: book.lowQCoverImage,
                  highQImage: book.lowQCoverImage,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: GoogleFonts.ubuntu(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((book.author ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      book.author!,
                      style: GoogleFonts.ubuntu(
                        fontSize: 13,
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ],
                  if (book.description != null && book.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      book.description!,
                      style: GoogleFonts.ubuntu(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: GoogleFonts.ubuntu(fontSize: 15)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryColor),
            ),
          ],
        ),
      ),
    );
  }
}
