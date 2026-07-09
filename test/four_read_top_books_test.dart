import 'package:audiobookflow/resources/services/four_read/four_read_top_books_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FourReadTopBooksService.splitTitleAuthor', () {
    test('splits on last " - " (multiple separators)', () {
      const input = 'Мертве місто - Голос надії - Галина Романова';
      final (title, author) = FourReadTopBooksService.splitTitleAuthor(input);
      expect(title, 'Мертве місто - Голос надії');
      expect(author, 'Галина Романова');
    });

    test('standard single separator', () {
      const input = 'Терор - Ден Сіммонс';
      final (title, author) = FourReadTopBooksService.splitTitleAuthor(input);
      expect(title, 'Терор');
      expect(author, 'Ден Сіммонс');
    });

    test('no separator returns empty author', () {
      const input = 'Книга без автора';
      final (title, author) = FourReadTopBooksService.splitTitleAuthor(input);
      expect(title, 'Книга без автора');
      expect(author, '');
    });

    test('empty string returns empty title and author', () {
      const input = '';
      final (title, author) = FourReadTopBooksService.splitTitleAuthor(input);
      expect(title, '');
      expect(author, '');
    });
  });

  group('FourReadTopBooksService.parseTopBooksFromHtml', () {
    test('parses cards and normalizes relative urls', () {
      const html = '''
<div class="linek d-flex ai-center has-overlay card">
  <div class="linek__img img-fit-cover">
    <img src="/uploads/posts/2026-02/medium/cover1.jpg" alt="cover-1">
  </div>
  <div class="linek__desc flex-grow-1">
    <a href="https://4read.org/7237-den-simmons-teror.html">
      <div class="linek__title ws-nowrap">Терор - Ден Сіммонс</div>
    </a>
  </div>
</div>
<div class="linek d-flex ai-center has-overlay card">
  <div class="linek__img img-fit-cover">
    <img src="/uploads/posts/2026-01/medium/cover2.jpg" alt="cover-2">
  </div>
  <div class="linek__desc flex-grow-1">
    <a href="/6562-blekvud-eldzhernon-prokliatyi-ostriv.html">
      <div class="linek__title ws-nowrap">Проклятий острів - Елджернон Блеквуд</div>
    </a>
  </div>
</div>
''';

      final service = FourReadTopBooksService();
      final books = service.parseTopBooksFromHtml(html);

      expect(books.length, 2);
      expect(books[0].title, 'Терор');
      expect(books[0].author, 'Ден Сіммонс');
      expect(books[0].id, 'https://4read.org/7237-den-simmons-teror.html');
      expect(
        books[1].id,
        'https://4read.org/6562-blekvud-eldzhernon-prokliatyi-ostriv.html',
      );
      expect(
        books[1].lowQCoverImage,
        'https://4read.org/uploads/posts/2026-01/medium/cover2.jpg',
      );
    });

    test('returns empty list when no linek cards exist', () {
      final service = FourReadTopBooksService();
      final books =
          service.parseTopBooksFromHtml('<html><body>No cards</body></html>');
      expect(books, isEmpty);
    });
  });
}
