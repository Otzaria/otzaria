import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';

import '../../../test_helpers/fake_commentary_library_provider.dart';
import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';
import '../../../test_helpers/stub_text_book_bloc.dart';

/// issue #5925 — אובדן פוקוס החלון (מעבר לחלון אחר ב-Windows) שומר את הבחירה
/// בתצוגה הראשית מאז #1585, אבל ניקה אותה בחלונית המפרשים, בחלונית הקישורים
/// ובצורת הדף. מעבר פוקוס לרכיב אחר *בתוך* האפליקציה ממשיך לנקות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    BookProtectionRepository.instance.debugRepositoryFor = (_) async => null;
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
  });

  tearDown(() {
    BookProtectionRepository.instance.debugReset();
    LibraryProviderManager.instance.resetForTesting();
  });

  Future<void> pumpPane(
    WidgetTester tester,
    Widget pane,
    FocusNode otherFocus,
  ) async {
    final textBookBloc = StubTextBookBloc(_loadedState());
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final personalNotesBloc = StubPersonalNotesBloc(
      const PersonalNotesState(
        isLoading: false,
        bookId: 'ספר בדיקה',
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        filteredLocatedNotes: [],
        filteredMissingNotes: [],
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      await textBookBloc.close();
      await settingsBloc.close();
      await personalNotesBloc.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            ],
            child: Scaffold(
              body: Column(
                children: [
                  Focus(focusNode: otherFocus, child: const SizedBox.shrink()),
                  Expanded(child: pane),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder regionOf(String text) => find
      .ancestor(
        of: find.textContaining(text).first,
        matching: find.byType(SelectableRegion),
      )
      .first;

  String selectedIn(WidgetTester tester, String text) => [
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
      find.descendant(
        of: regionOf(text),
        matching: find.byWidgetPredicate((w) => w is RichText),
      ),
    ))
      for (final selection in paragraph.selections)
        selection.textInside(
          paragraph.text.toPlainText(includeSemanticsLabels: false),
        ),
  ].join();

  // גרירה על הטקסט ממקדת את אזור הבחירה (כמו אצל המשתמש), ואז "בחר הכל".
  Future<void> select(WidgetTester tester, String text) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.textContaining(text).first),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(-15, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(kDoubleTapTimeout);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<SelectableRegionState>(),
      same(tester.state<SelectableRegionState>(regionOf(text))),
      reason: 'גרירה על הטקסט ממקדת את אזור הבחירה',
    );
    tester
        .state<SelectableRegionState>(regionOf(text))
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pumpAndSettle();
  }

  void windowFocus(WidgetTester tester, ViewFocusState state) {
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: state,
        direction: ViewFocusDirection.undefined,
      ),
    );
  }

  Future<void> expectKeptOnWindowBlur(
    WidgetTester tester,
    String text,
    FocusNode otherFocus,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await select(tester, text);
    final selected = selectedIn(tester, text);
    expect(selected, isNotEmpty, reason: 'הגרירה בוחרת טקסט');

    windowFocus(tester, ViewFocusState.unfocused);
    await tester.pumpAndSettle();
    expect(
      selectedIn(tester, text),
      selected,
      reason: 'מעבר לחלון אחר אינו מנקה את הבחירה',
    );

    windowFocus(tester, ViewFocusState.focused);
    await tester.pumpAndSettle();
    expect(selectedIn(tester, text), selected, reason: 'גם בחזרה לחלון');

    otherFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(
      selectedIn(tester, text),
      isEmpty,
      reason: 'פוקוס לרכיב אחר באפליקציה ממשיך לנקות את הבחירה',
    );
  }

  testWidgets('חלונית המפרשים: מעבר לחלון אחר שומר את הבחירה', (tester) async {
    final otherFocus = FocusNode();
    addTearDown(otherFocus.dispose);
    await pumpPane(
      tester,
      CommentaryListBase(
        openBookCallback: (_) {},
        fontSize: 18,
        showSearch: false,
        shrinkWrap: false,
      ),
      otherFocus,
    );
    await expectKeptOnWindowBlur(tester, 'זהו פירוש', otherFocus);
  });

  testWidgets('צורת הדף: מעבר לחלון אחר שומר את הבחירה במפרש', (tester) async {
    final otherFocus = FocusNode();
    addTearDown(otherFocus.dispose);
    await pumpPane(
      tester,
      SimpleTextViewer(
        content: const ['פירוש ארוך של המפרש על השורה הראשונה בספר'],
        fontSize: 18,
        openBookCallback: (_) {},
        isMainText: false,
        bookTitle: 'מפרש בדיקה',
        notesRepository: _FakeNotesRepository(),
      ),
      otherFocus,
    );
    await expectKeptOnWindowBlur(tester, 'פירוש ארוך', otherFocus);
  });

  testWidgets('חלונית הקישורים: מעבר לחלון אחר שומר את הבחירה', (tester) async {
    CommentaryService.seedEraCache({'ספר מקושר': CommentaryEra.other});
    addTearDown(CommentaryService.clearEraCache);
    final link = _ContentLink(
      heRef: 'ספר מקושר, א',
      index1: 1,
      path2: 'ספר מקושר',
      index2: 1,
      connectionType: LinkTypes.mesoratHashas,
      content: 'תוכן הקישור לבדיקת שמירת הבחירה',
    );
    final otherFocus = FocusNode();
    addTearDown(otherFocus.dispose);
    await pumpPane(
      tester,
      LinksListView(
        displayProfile: TextDisplayProfile.defaults,
        links: [link],
        chipSourceLinks: [link],
        openBookTitle: 'ספר בדיקה',
        selectedLinkTypes: const {},
        onSelectedLinkTypesChanged: (_) {},
        openBookCallback: (_) {},
        fontSize: 16,
      ),
      otherFocus,
    );
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await expectKeptOnWindowBlur(tester, 'תוכן הקישור', otherFocus);
  });
}

class _ContentLink extends Link {
  _ContentLink({
    required super.heRef,
    required super.index1,
    required super.path2,
    required super.index2,
    required super.connectionType,
    required this._content,
  });

  final String _content;

  @override
  Future<String> get content => Future.value(_content);

  @override
  Future<String> get displayReference => Future.value(fallbackDisplayReference);
}

class _FakeNotesRepository implements PersonalNotesRepository {
  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) async {
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    content: const ['שורה א'],
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
    searchText: '',
  );
}
