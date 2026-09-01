import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);
}

Link _link(int index1, String target) => Link(
  heRef: '$target $index1',
  index1: index1,
  path2: target,
  index2: 1,
  connectionType: 'commentary',
);

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
  });

  tearDown(() async {
    await bloc.close();
  });

  test(
    'אצוות UpdateLinks סמוכות אינן דורסות זו את זו — אצווה גדולה (מסלול '
    'isolate) שמסתיימת אחרי אצווה קטנה (מסלול סינכרוני) שמרה בעבר רק את '
    'עצמה, והקישורים שאבדו לא נטענו שוב (issue #1095)',
    () async {
      bloc.emit(
        TextBookLoaded(
          book: book,
          content: List<String>.generate(500, (i) => 'שורה $i'),
          fontSize: 20,
          showLeftPane: false,
          showSplitView: false,
          activeCommentators: const ['רש"י'],
          commentatorGroups: const [],
          availableCommentators: const ['רש"י'],
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

      // מעל 250 קישורים — processLinksForState עובר למסלול Isolate.run האיטי.
      final bigBatch = List<Link>.generate(300, (i) => _link(i + 1, 'רש"י'));
      const smallTargetLine = 400;
      final smallBatch = [_link(smallTargetLine, 'רש"י')];

      bloc.add(UpdateLinks(bigBatch));
      bloc.add(UpdateLinks(smallBatch));

      await Future<void>.delayed(const Duration(seconds: 2));

      final state = bloc.state as TextBookLoaded;
      expect(state.links, hasLength(301));
      expect(state.linksByLine[smallTargetLine], isNotNull);
      expect(state.linksByLine[1], isNotNull);
    },
  );
}
