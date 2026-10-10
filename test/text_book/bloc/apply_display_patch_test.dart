import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);
}

/// ApplyDisplayPatch כותב עקיפה לחריץ של התצוגה הפעילה בלבד, וClearDisplayOverrides
/// מנקה את כולן.
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
      initialState: TextBookInitial.named(book, 0, true, const []),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
  });

  tearDown(() => bloc.close());

  TextBookLoaded seed({bool pageShape = false}) => TextBookLoaded(
    book: book,
    content: const ['שורה א'],
    fontSize: 20,
    showLeftPane: true,
    showSplitView: false,
    showPageShapeView: pageShape,
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
  );

  blocTest<TextBookBloc, TextBookState>(
    'טלאי על הגוף מסתיר ניקוד בגוף ובמפרשים (ירושה)',
    build: () => bloc,
    seed: seed,
    act: (bloc) => bloc.add(
      const ApplyDisplayPatch(
        target: TextTarget.body,
        patch: TextDisplayPatch(nikud: MarkVisibility.hide),
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.removeNikud, 'גוף', isTrue)
          .having((s) => s.commentaryRemoveNikud, 'מפרשים', isTrue),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'טלאי על המפרשים אינו משנה את הגוף',
    build: () => bloc,
    seed: seed,
    act: (bloc) => bloc.add(
      const ApplyDisplayPatch(
        target: TextTarget.commentary,
        patch: TextDisplayPatch(punctuation: MarkVisibility.hide),
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.removePunctuation, 'גוף', isFalse)
          .having((s) => s.commentaryRemovePunctuation, 'מפרשים', isTrue),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'בצורת הדף הטלאי נכתב לחריץ צורת הדף בלבד',
    build: () => bloc,
    seed: () => seed(pageShape: true),
    act: (bloc) => bloc.add(
      const ApplyDisplayPatch(
        target: TextTarget.body,
        patch: TextDisplayPatch(teamim: TeamimVisibility.hide),
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.bodyDisplayProfile.removeTeamim, 'צורת הדף', isTrue)
          .having(
            (s) => s
                .displayProfile(target: TextTarget.body, view: TextView.regular)
                .removeTeamim,
            'רגילה',
            isFalse,
          ),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'טלאי ריק אינו פולט state',
    build: () => bloc,
    seed: seed,
    act: (bloc) => bloc.add(
      const ApplyDisplayPatch(
        target: TextTarget.body,
        patch: TextDisplayPatch.empty,
      ),
    ),
    expect: () => const <TextBookState>[],
  );

  blocTest<TextBookBloc, TextBookState>(
    'ClearDisplayOverrides מחזיר לברירת המחדל',
    build: () => bloc,
    seed: () => seed().copyWith(removeNikud: true),
    act: (bloc) => bloc.add(const ClearDisplayOverrides()),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.removeNikud, 'ניקוד', isFalse)
          .having((s) => s.displayOverrides.isEmpty, 'עקיפות', isTrue),
    ],
  );
}
