import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/text_book/text_book_repository.dart';

class _StubRepository extends Mock implements TextBookRepository {
  List<Link> links = const [];
  Object? error;
  TextBook? book;
  int? start;
  int? end;
  List<String>? titles;

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    this.book = book;
    start = startIndex;
    end = endIndex;
    titles = targetBookTitles?.toList();
    if (error != null) throw error!;
    return links;
  }
}

Link _link(int index1) => Link(
  heRef: 'ref',
  index1: index1,
  path2: 'target',
  index2: 1,
  connectionType: 'COMMENTARY',
  targetSource: BookSource.attached('lib-a'),
);

void main() {
  final book = TextBook(
    id: 3,
    title: 'book',
    categoryId: 9,
    source: BookSource.attached('lib-a'),
  );

  test('uses the reader links repository for the selected range', () async {
    final repository = _StubRepository()..links = [_link(2)];

    final links = await loadPrintRangeLinks(
      book,
      startIndex: 1,
      endIndex: 4,
      targetBookTitles: const ['target'],
      fallback: const [],
      repository: repository,
    );

    expect(links.single.targetSource, BookSource.attached('lib-a'));
    expect(repository.book, same(book));
    expect(repository.start, 1);
    expect(repository.end, 4);
    expect(repository.titles, ['target']);
  });

  test('falls back to the given links when loading fails', () async {
    final fallback = [_link(7)];
    final repository = _StubRepository()..error = StateError('closed');

    final links = await loadPrintRangeLinks(
      book,
      startIndex: 0,
      endIndex: 1,
      targetBookTitles: const [],
      fallback: fallback,
      repository: repository,
    );

    expect(links, same(fallback));
  });
}
