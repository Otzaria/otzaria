import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/link_processing.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);
}

/// סופר קריאות של [targetSource] — טעינת הדורות קוראת אותו פעם לכל קישור.
class _CountingLink extends Link {
  _CountingLink(int index1, String target, {String type = 'reference'})
    : super(
        heRef: '$target $index1',
        index1: index1,
        path2: target,
        index2: 1,
        connectionType: type,
      );

  int sourceReads = 0;

  @override
  BookSource get targetSource {
    sourceReads++;
    return super.targetSource;
  }
}

List<_CountingLink> _batch(
  int from,
  int count, {
  String type = 'reference',
}) => [
  for (var i = 0; i < count; i++) _CountingLink(from + i, 'ספר $i', type: type),
];

int _reads(List<_CountingLink> links) =>
    links.fold(0, (sum, link) => sum + link.sourceReads);

void _reset(List<_CountingLink> links) {
  for (final link in links) {
    link.sourceReads = 0;
  }
}

/// הקריאות שעיבוד הקישורים עצמו (מיזוג ומיון) מבצע, בלי טעינת הדורות.
Future<({int existing, int incoming})> _processingReads() async {
  final existing = _batch(1, 40);
  final incoming = _batch(100, 40);
  await processLinksForState(
    existingLinks: existing,
    incomingLinks: incoming,
    replaceExisting: false,
    visibleIndices: const [0],
    selectedIndices: const {},
  );
  return (existing: _reads(existing), incoming: _reads(incoming));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TextBookBloc bloc;
  late TextBook book;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    book = TextBook(title: 'ספר בדיקה');
    bloc = TextBookBloc(
      repository: _FakeTextBookRepository(),
      initialState: TextBookInitial.named(book, 10, true, const []),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
    bloc.emit(
      TextBookLoaded(
        book: book,
        content: List<String>.generate(500, (i) => 'שורה $i'),
        fontSize: 20,
        showLeftPane: false,
        showSplitView: false,
        activeCommentators: const [],
        commentatorGroups: const [],
        availableCommentators: const [],
        links: const [],
        linksByLine: const {},
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: const [0],
        pinLeftPane: false,
        searchText: '',
        scrollController: ItemScrollController(),
        positionsListener: ItemPositionsListener.create(),
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  Future<void> addLinks(List<Link> links) async {
    bloc.add(UpdateLinks(links));
    await bloc.stream.firstWhere(
      (s) => s is TextBookLoaded && s.links.toSet().containsAll(links),
    );
    await pumpEventQueue();
  }

  test('טעינת חלון קישורים אינה טוענת מחדש את דורות הקישורים שכבר נצברו '
      '(perf: הלולאה גדלה עם כל הספר)', () async {
    final baseline = await _processingReads();
    final existing = _batch(1, 40);
    await addLinks(existing);
    _reset(existing);

    await addLinks(_batch(100, 40));

    expect(_reads(existing), baseline.existing);
  });

  test('דורות הקישורים החדשים נטענים, ומפרשים מסוננים', () async {
    final baseline = await _processingReads();
    await addLinks(_batch(1, 40));
    final incoming = _batch(100, 40);
    final commentaries = _batch(200, 5, type: 'commentary');

    await addLinks([...incoming, ...commentaries]);

    expect(_reads(incoming), baseline.incoming + incoming.length);
    expect(_reads(commentaries), baseline.incoming ~/ 40 * commentaries.length);
  });
}
