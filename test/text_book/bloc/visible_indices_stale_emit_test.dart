import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// `UpdateVisibleIndecies` מצלם את ה-state בכניסה למטפל. כל `await` בדרך
/// ל-emit מאפשר לאירוע אחר לפלוט מצב חדש, וה-emit של הצילום המיושן דורס אותו —
/// כך חלונית הצד נשארה פתוחה בטלפון אחרי ניווט מעץ הניווט.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('סגירת חלונית הצד מיד אחרי עדכון הגלילה לא נדרסת', () async {
    final bloc = await _loadedBloc(showLeftPane: true);

    bloc.add(const UpdateVisibleIndecies([12, 13, 14]));
    bloc.add(const ToggleLeftPane(false));

    await _waitFor(
      () {
        final state = bloc.state;
        return state is TextBookLoaded && state.visibleIndices.first == 12;
      },
      description: 'visibleIndices התעדכנו ל-12',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final state = bloc.state as TextBookLoaded;
    expect(
      state.showLeftPane,
      isFalse,
      reason:
          'ToggleLeftPane נפלט אחרי הצילום — אסור שה-emit של הגלילה ידרוס אותו',
    );
    expect(state.visibleIndices, [12, 13, 14]);

    await bloc.close();
  });

  test('שינוי גודל הגופן מיד אחרי עדכון הגלילה לא נדרס', () async {
    final bloc = await _loadedBloc(showLeftPane: false);

    final before = (bloc.state as TextBookLoaded).fontSize;

    bloc.add(const UpdateVisibleIndecies([12, 13, 14]));
    bloc.add(UpdateFontSize(before + 8));

    await _waitFor(
      () {
        final state = bloc.state;
        return state is TextBookLoaded && state.visibleIndices.first == 12;
      },
      description: 'visibleIndices התעדכנו ל-12',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final state = bloc.state as TextBookLoaded;
    expect(
      state.fontSize,
      before + 8,
      reason:
          'UpdateFontSize נפלט אחרי הצילום — אסור שה-emit של הגלילה ידרוס אותו',
    );
    expect(state.visibleIndices, [12, 13, 14]);

    await bloc.close();
  });

  test(
    'בלי בחירה וחלונית הניווט סגורה, הקישורים עוקבים אחרי הגלילה (issue #2036)',
    () async {
      final bloc = await _loadedBloc(showLeftPane: false);
      await _waitFor(
        () => (bloc.state as TextBookLoaded).links.isNotEmpty,
        description: 'טעינת קישורים',
      );

      bloc.add(const UpdateVisibleIndecies([12, 13, 14]));
      await _waitFor(
        () => (bloc.state as TextBookLoaded).visibleIndices.first == 12,
        description: 'visibleIndices התעדכנו ל-12',
      );

      final state = bloc.state as TextBookLoaded;
      expect(
        state.visibleLinks.map((link) => link.index1).toSet(),
        {13, 14, 15},
        reason:
            'הרשימה חייבת להציג את קישורי השורות שעל המסך, לא של מיקום קודם',
      );

      await bloc.close();
    },
  );
}

Future<TextBookBloc> _loadedBloc({required bool showLeftPane}) async {
  final bloc = TextBookBloc(
    repository: _TwoSectionRepository(),
    initialState: TextBookInitial.named(
      TextBook(title: 'ספר בדיקה'),
      10,
      showLeftPane,
      const [],
      searchMode: SearchMode.exact,
      showPageShapeView: false,
    ),
  );

  bloc.add(
    const LoadContent(
      fontSize: 20,
      showSplitView: false,
      removeNikud: false,
      loadCommentators: false,
    ),
  );

  await _waitFor(
    () => bloc.state is TextBookLoaded,
    description: 'מצב טעון',
  );
  return bloc;
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$description not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Repository עם TOC של שני סעיפים: "סעיף א" משורה 5, "סעיף ב" משורה 10.
class _TwoSectionRepository extends TextBookRepository {
  _TwoSectionRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async {
    return List.generate(40, (i) => 'שורה $i').join('\n');
  }

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    final lines = List.generate(40, (i) => 'שורה $i');
    final ns = startLine.clamp(0, lines.length - 1);
    final ne = endLine.clamp(ns, lines.length - 1);
    return BookContentRange(
      startLine: ns,
      endLine: ne,
      totalLines: lines.length,
      lines: lines.sublist(ns, ne + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async {
    return [
      TocEntry(text: 'סעיף א', index: 5, level: 1),
      TocEntry(text: 'סעיף ב', index: 10, level: 1),
    ];
  }

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => [
    // קישור "reference" לכל שורה (index1 הוא 1-based).
    for (var i = startIndex; i <= endIndex; i++)
      Link(
        heRef: 'מקור $i',
        index1: i + 1,
        path2: 'ספר $i.txt',
        index2: 1,
        connectionType: 'reference',
      ),
  ];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
}
