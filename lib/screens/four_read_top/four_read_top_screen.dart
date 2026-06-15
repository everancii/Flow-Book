import 'package:audiobookflow/resources/designs/app_circular_progress_indicator.dart';
import 'package:audiobookflow/resources/designs/app_colors.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_guard.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_open_telemetry.dart';
import 'package:audiobookflow/screens/four_read_top/bloc/four_read_top_bloc.dart';
import 'package:audiobookflow/widgets/low_and_high_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class FourReadTopScreen extends StatefulWidget {
  const FourReadTopScreen({super.key});

  @override
  State<FourReadTopScreen> createState() => _FourReadTopScreenState();
}

class _FourReadTopScreenState extends State<FourReadTopScreen> {
  late final FourReadTopBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = FourReadTopBloc()..add(FetchTopBooks());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            '4Read Top 100',
            style: GoogleFonts.ubuntu(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: BlocBuilder<FourReadTopBloc, FourReadTopState>(
          builder: (context, state) {
            if (state is FourReadTopLoading || state is FourReadTopInitial) {
              return const Center(child: AppCircularProgressIndicator());
            }
            if (state is FourReadTopError) {
              return _ErrorView(
                message: state.message,
                onRetry: () => _bloc.add(FetchTopBooks()),
              );
            }
            if (state is FourReadTopLoaded) {
              if (state.books.isEmpty) {
                return const _EmptyView();
              }
              return _BookList(books: state.books);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _BookList extends StatelessWidget {
  final List<Audiobook> books;
  const _BookList({required this.books});

  void _openBook(BuildContext context, Audiobook audiobook, int rank) {
    final guarded = FourReadOpenGuard.validateAndNormalizeAudiobook(
      audiobook,
      stage: 'top_books_list_tap',
    );
    if (!guarded.isValid) {
      final failureCode = guarded.failure?.code ?? 'unknown_failure';
      FourReadOpenTelemetry.validationFailure(
        stage: 'top_books_list_tap',
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
        stage: 'top_books_list_tap',
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
      stage: 'top_books_list_tap',
      audiobookId: normalized.id,
    );
    context.push(
      '/audiobook-details',
      extra: {
        'audiobook': normalized,
        'isDownload': false,
        'isYoutube': false,
        'isLocal': false,
        'isFourRead': true,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final rank = index + 1;
        return _BookTile(
          book: book,
          rank: rank,
          onTap: () => _openBook(context, book, rank),
        );
      },
    );
  }
}

class _BookTile extends StatelessWidget {
  final Audiobook book;
  final int rank;
  final VoidCallback onTap;

  const _BookTile({
    required this.book,
    required this.rank,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Rank badge
            SizedBox(
              width: 36,
              child: Text(
                '#$rank',
                style: GoogleFonts.ubuntu(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: rank <= 3
                      ? AppColors.primaryColor
                      : theme.textTheme.bodySmall?.color,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            // Cover thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 52,
                height: 72,
                child: LowAndHighImage(
                  lowQImage: book.lowQCoverImage,
                  highQImage: book.lowQCoverImage,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Title + Author
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: GoogleFonts.ubuntu(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((book.author ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      book.author ?? '',
                      style: GoogleFonts.ubuntu(
                        fontSize: 13,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                      maxLines: 1,
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.ubuntu(fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No books found.',
        style: GoogleFonts.ubuntu(fontSize: 16),
      ),
    );
  }
}
