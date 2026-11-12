import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_changes.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

import '../../test_helpers/fake_commentary_library_provider.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

/// רשימת המפרשים (גם בצורת הדף) שומרת את הערות כל מפרש פעם אחת לכל הקטעים.
/// רגרסיה: הערה שנמחקה מחלונית ההערות המשיכה להיות מודגשת ברשימה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late StubTextBookBloc textBookBloc;
  late _TestSettingsBloc settingsBloc;
  late Map<String, List<PersonalNote>> store;
  late List<String> loads;

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): FakeCommentaryLibraryProvider(),
      },
      providers: [FakeCommentaryLibraryProvider()],
    );
    textBookBloc = StubTextBookBloc(_loadedState());
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
    store = {
      'מפרש בדיקה': [_note()],
    };
    loads = [];
  });

  tearDown(() async {
    await textBookBloc.close();
    await settingsBloc.close();
    LibraryProviderManager.instance.resetForTesting();
  });

  Widget harness({bool showList = true}) => MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<TextBookBloc>.value(value: textBookBloc),
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
      ],
      child: Scaffold(
        body: SizedBox(
          height: 600,
          width: 500,
          child: showList
              ? CommentaryListBase(
                  openBookCallback: (_) {},
                  fontSize: 18,
                  showSearch: false,
                  shrinkWrap: false,
                  personalNotesLoader: (bookId, {categoryId}) async {
                    loads.add(bookId);
                    return List.of(store[bookId] ?? const []);
                  },
                )
              : const SizedBox(),
        ),
      ),
    ),
  );

  Finder markedCommentary() => find.byWidgetPredicate(
    (w) =>
        w is SmartTextWidget &&
        w.text.contains('פירוש') &&
        w.text.contains('otzaria://note'),
  );

  Future<void> notify(WidgetTester tester, String bookId) async {
    PersonalNotesChanges.notify(bookId);
    await tester.pumpAndSettle();
  }

  testWidgets('הערה שנמחקה במקום אחר מסירה את ההדגשה מהמפרש', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(markedCommentary(), findsOneWidget, reason: 'תנאי מוקדם');

    store['מפרש בדיקה'] = [];
    await notify(tester, 'מפרש בדיקה');

    expect(markedCommentary(), findsNothing);
  });

  testWidgets('הערה שנוספה במקום אחר מסומנת במפרש', (tester) async {
    store['מפרש בדיקה'] = [];
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(markedCommentary(), findsNothing);

    store['מפרש בדיקה'] = [_note()];
    await notify(tester, 'מפרש בדיקה');

    expect(markedCommentary(), findsOneWidget);
  });

  testWidgets('שינוי בספר שאינו מוצג ברשימה אינו טוען הערות מחדש', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    final loadsBefore = loads.length;

    await notify(tester, 'ספר אחר');

    expect(loads, hasLength(loadsBefore));
    expect(markedCommentary(), findsOneWidget);
  });

  testWidgets('רשימה שנסגרה מפסיקה להאזין לשינויים', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness(showList: false));
    final loadsBefore = loads.length;
    await notify(tester, 'מפרש בדיקה');

    expect(loads, hasLength(loadsBefore));
  });
}

PersonalNote _note() {
  final now = DateTime(2026, 10, 4);
  return PersonalNote(
    id: '1',
    bookId: 'מפרש בדיקה',
    lineNumber: 1,
    displayTitle: 'שורה',
    lastKnownLineNumber: 1,
    status: PersonalNoteStatus.located,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

TextBookLoaded _loadedState() {
  final link = Link(
    heRef: 'בראשית א',
    index1: 1,
    path2: 'מפרש בדיקה.txt',
    index2: 1,
    connectionType: 'COMMENTARY',
    targetCategoryId: 1,
    targetFileType: 'txt',
  );

  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['גוף הפסוק'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const ['מפרש בדיקה'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה'],
    links: [link],
    visibleLinks: const [],
    linksByLine: {
      1: [link],
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
  );
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
