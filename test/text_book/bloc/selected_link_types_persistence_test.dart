// שמירת סינון סוגי הקישורים בהגדרות.
// ON_BOOK ("על <הספר הפתוח>") אינו נשמר: תוויתו נגזרת מהספר הפתוח, ובספר אחר
// הוא היה מסנן "על <ספר אחר>" בלי שהמשתמש ביקש זאת.
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  String? savedTypes() =>
      Settings.getValue<String>(SettingsRepository.keySelectedLinkTypes);

  Future<TextBookBloc> loadedBloc({String bookTitle = 'ברכות'}) async {
    final bloc = TextBookBloc(
      repository: _FakeTextBookRepository(),
      initialState: TextBookInitial.named(
        TextBook(title: bookTitle),
        0,
        false,
        const [],
        searchMode: SearchMode.exact,
        showPageShapeView: false,
      ),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    await bloc.stream.firstWhere((state) => state is TextBookLoaded);
    await pumpEventQueue();
    return bloc;
  }

  Future<Set<String>> applyFilter(
    TextBookBloc bloc,
    Set<String> types,
  ) async {
    bloc.add(UpdateLinkTypeFilter(types));
    // השמירה להגדרות היא unawaited — ממתינים לניקוז תור האירועים.
    await pumpEventQueue();
    return (bloc.state as TextBookLoaded).selectedLinkTypes;
  }

  test('סוגי קישור רגילים נשמרים בהגדרות', () async {
    final bloc = await loadedBloc();

    await applyFilter(bloc, {LinkTypes.einMishpat, LinkTypes.quotation});

    expect(savedTypes(), contains(LinkTypes.einMishpat));
    expect(savedTypes(), contains(LinkTypes.quotation));

    await bloc.close();
  });

  test('ON_BOOK פעיל במצב אך אינו נשמר בהגדרות', () async {
    final bloc = await loadedBloc();

    final effective = await applyFilter(bloc, {
      LinkTypes.onBookKey,
      LinkTypes.einMishpat,
    });

    // הסינון פעיל בספר הפתוח...
    expect(effective, contains(LinkTypes.onBookKey));
    // ...אך לא נשמר לספר הבא.
    expect(savedTypes(), isNot(contains(LinkTypes.onBookKey)));
    expect(savedTypes(), contains(LinkTypes.einMishpat));

    await bloc.close();
  });

  test('בחירת ON_BOOK בלבד שומרת מחרוזת ריקה = הצג הכל', () async {
    final bloc = await loadedBloc();

    await applyFilter(bloc, {LinkTypes.onBookKey});

    expect(savedTypes(), isEmpty);

    await bloc.close();
  });

  test('ספר חדש אינו יורש את הצ׳יפ "על <הספר הפתוח>"', () async {
    final first = await loadedBloc(bookTitle: 'בבא בתרא');
    await applyFilter(first, {LinkTypes.onBookKey, LinkTypes.mesoratHashas});
    await first.close();

    final second = await loadedBloc(bookTitle: 'ברכות');
    final state = second.state as TextBookLoaded;

    expect(state.selectedLinkTypes, isNot(contains(LinkTypes.onBookKey)));
    expect(state.selectedLinkTypes, contains(LinkTypes.mesoratHashas));

    await second.close();
  });

  test('ערך ON_BOOK שנשמר בגרסה קודמת מנוקה בטעינה', () async {
    await Settings.setValue(
      SettingsRepository.keySelectedLinkTypes,
      '${LinkTypes.onBookKey},${LinkTypes.quotation}',
    );

    final bloc = await loadedBloc();
    final state = bloc.state as TextBookLoaded;

    expect(state.selectedLinkTypes, {LinkTypes.quotation});

    await bloc.close();
  });
}

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async =>
      List.generate(10, (index) => 'שורה $index').join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    final lines = List.generate(10, (index) => 'שורה $index');
    final start = startLine.clamp(0, lines.length - 1);
    final end = endLine.clamp(start, lines.length - 1);
    return BookContentRange(
      startLine: start,
      endLine: end,
      totalLines: lines.length,
      lines: lines.sublist(start, end + 1),
    );
  }
}
