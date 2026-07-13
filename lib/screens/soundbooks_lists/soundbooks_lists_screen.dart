import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/screens/soundbooks_lists/bloc/soundbooks_lists_bloc.dart';
import 'package:audiobookflow/widgets/flow_loading_indicator.dart';
import 'package:audiobookflow/widgets/low_and_high_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

enum _ListTab { latest, popular, top100 }

class SoundBooksListsScreen extends StatefulWidget {
  const SoundBooksListsScreen({super.key});

  @override
  State<SoundBooksListsScreen> createState() => _SoundBooksListsScreenState();
}

class _SoundBooksListsScreenState extends State<SoundBooksListsScreen> {
  late final SoundBooksListsBloc _bloc;
  _ListTab _selectedTab = _ListTab.latest;

  @override
  void initState() {
    super.initState();
    _bloc = SoundBooksListsBloc()..add(FetchSoundBooksLists());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  List<Audiobook> _currentBooks(SoundBooksListsLoaded state) {
    switch (_selectedTab) {
      case _ListTab.latest:
        return state.latestBooks;
      case _ListTab.popular:
        return state.popularBooks;
      case _ListTab.top100:
        return state.topBooks;
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
            'Sound-Books UA',
            style: GoogleFonts.ubuntu(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TabButton(
                  label: 'Останні',
                  isSelected: _selectedTab == _ListTab.latest,
                  onTap: () => setState(() => _selectedTab = _ListTab.latest),
                ),
                _TabButton(
                  label: 'Популярні',
                  isSelected: _selectedTab == _ListTab.popular,
                  onTap: () => setState(() => _selectedTab = _ListTab.popular),
                ),
                _TabButton(
                  label: 'ТОП-100',
                  isSelected: _selectedTab == _ListTab.top100,
                  onTap: () => setState(() => _selectedTab = _ListTab.top100),
                ),
              ],
            ),
          ),
        ),
        body: BlocBuilder<SoundBooksListsBloc, SoundBooksListsState>(
          builder: (context, state) {
            if (state is SoundBooksListsLoading ||
                state is SoundBooksListsInitial) {
              return const Center(child: FlowLoadingIndicator());
            }
            if (state is SoundBooksListsError) {
              return _ErrorView(
                message: state.message,
                onRetry: () => _bloc.add(FetchSoundBooksLists()),
              );
            }
            if (state is SoundBooksListsLoaded) {
              final books = _currentBooks(state);
              if (books.isEmpty) {
                return Center(
                  child: Text(
                    'No books found',
                    style: GoogleFonts.ubuntu(fontSize: 16, color: Colors.grey),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                itemCount: books.length,
                itemBuilder: (context, index) =>
                    _BookTile(book: books[index]),
              );
            }
            return const SizedBox();
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF009688).withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF009688)
                  : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.ubuntu(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFF009688)
                  : Colors.grey.shade600,
            ),
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
            'isKnigavuhe': false,
            'isSoundBooks': true,
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
                  if ((book.author ?? '').isNotEmpty &&
                      book.author != 'Unknown') ...[
                    const SizedBox(height: 4),
                    Text(
                      book.author!,
                      style: GoogleFonts.ubuntu(
                        fontSize: 13,
                        color: const Color(0xFF009688),
                      ),
                    ),
                  ],
                  if (book.totalTime != null && book.totalTime!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Триває: ${book.totalTime}',
                      style: GoogleFonts.ubuntu(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                  if (book.description != null &&
                      book.description!.isNotEmpty) ...[
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
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.ubuntu(fontSize: 15)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF009688)),
            ),
          ],
        ),
      ),
    );
  }
}
