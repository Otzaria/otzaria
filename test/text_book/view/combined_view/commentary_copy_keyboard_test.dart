import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../test_helpers/memory_cache_provider.dart';

/// issue #530 (ריגרסיה): Ctrl+C על בחירה במפרשים במצב "מפרשים מתחת" העתיק
/// ריק — ה-SelectionArea של המפרשים מקונן בתוך זה של הטקסט הראשי (עטוף ב-
/// SelectionContainer.disabled), וטיפול ההעתקה של ה-SelectionArea החיצוני לא
/// ראה את בחירת המפרשים. בחירה במפרשים חייבת להופיע בהעתקת המקלדת.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('Ctrl+C על בחירה במפרשים מתחת מפעיל את העתקת המפרשים', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): _FakeLibraryProvider(),
      },
      providers: [_FakeLibraryProvider()],
    );
    addTearDown(LibraryProviderManager.instance.resetForTesting);

    final link = Link(
      heRef: 'בראשית א',
      index1: 1,
      path2: 'מפרש בדיקה.txt',
      index2: 1,
      connectionType: 'COMMENTARY',
      targetCategoryId: 1,
      targetFileType: 'txt',
    );

    final state = TextBookLoaded(
      book: TextBook(title: 'ספר בדיקה'),
      showLeftPane: false,
      content: const ['שורה א', 'שורה ב'],
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
      visibleIndices: const [0, 1],
      selectedIndex: 0,
      selectedIndices: const {0},
      pinLeftPane: false,
      searchText: '',
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );

    final textBookBloc = _TestTextBookBloc(state);
    addTearDown(textBookBloc.close);
    final settingsBloc = _TestSettingsBloc(
      SettingsState.initial().copyWith(copyWithHeaders: 'book_name'),
    );
    addTearDown(settingsBloc.close);
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    addTearDown(personalNotesBloc.close);
    final syncController = SelectionSyncController();
    addTearDown(syncController.dispose);
    final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
    addTearDown(tab.dispose);

    // לוכד כתיבה ללוח דרך Clipboard.setData של Flutter (ברירת המחדל של
    // SelectableRegion) — כדי לוודא שלא ההעתקה הפנימית (הריקה) רצה.
    final clipboardCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardCalls.add(
            (call.arguments as Map<Object?, Object?>)['text']?.toString() ?? '',
          );
          return null;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CombinedView(
              data: const ['שורה א', 'שורה ב'],
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: true,
              selectionSyncController: syncController,
              tab: tab,
            ),
          ),
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => find
          .textContaining('פירוש לבדיקה', findRichText: true)
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.textContaining('פירוש לבדיקה', findRichText: true),
      findsWidgets,
      reason: 'כרטיס המפרשים לא נטען',
    );

    // בחירה אמיתית בכל הטקסט של המפרש (ה-SelectionArea הפנימי).
    final innerRegion = tester.state<SelectableRegionState>(
      find.descendant(
        of: _commentarySelectionAreaFinder(),
        matching: find.byType(SelectableRegion),
      ),
    );
    innerRegion.selectAll();
    await tester.pump();

    // הבחירה צריכה להתפרסם ב-controller כדי שטיפול ההעתקה החיצוני יראה אותה.
    final publishedText = syncController.activeSelectionText;
    expect(publishedText, isNotNull);
    expect(
      publishedText!.trim().isNotEmpty,
      isTrue,
      reason: 'בחירת המפרשים לא פורסמה ב-SelectionSyncController',
    );
    expect(publishedText, contains('פירוש לבדיקה'));

    // Ctrl+C — הפוקוס יושב על אזור הקריאה החיצוני (כמו במציאות אחרי
    // בחירה בספר), והבחירה אינה שם.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final snackbarTexts = _visibleSnackbarTexts(tester);
    debugPrint('הודעות Snackbar אחרי Ctrl+C: $snackbarTexts');

    // אסור שתופיע הודעת "אין טקסט נבחר" — הבחירה במפרשים קיימת.
    expect(
      snackbarTexts.contains(TextBookMessages.selectTextToCopy),
      isFalse,
      reason:
          'Ctrl+C ראה בחירה ריקה למרות שנבחר טקסט במפרשים '
          '(הודעה: $snackbarTexts)',
    );

    // ההעתקה צריכה לעבור דרך מסלול ההעתקה של המפרשים עד לכתיבה ללוח.
    // בטסט הלוח הפלאגיני אינו זמין: או שהודעת "הלוח אינו זמין" מופיעה,
    // או שהגישה ללוח זורקת (ערוץ פלאגין חסר) ומוצגת שגיאת העתקה — בשני
    // המקרים זהו סימן שההעתקה רצה עם הטקסט הנבחר ולא נעצרה על "אין טקסט".
    final copyPathReachedWrite =
        snackbarTexts.contains(CommonMessages.clipboardUnavailable) ||
        snackbarTexts.contains(CommonMessages.textCopyError);
    expect(
      copyPathReachedWrite,
      isTrue,
      reason: 'מסלול ההעתקה של המפרשים לא הופעל (הודעה: $snackbarTexts)',
    );

    // ניקוז טיימר הסגירה של ה-Snackbar כדי לא להשאיר טיימרים תלויים.
    await tester.pump(const Duration(seconds: 5));
  });
}

Finder _commentarySelectionAreaFinder() => find.byWidgetPredicate(
  (w) =>
      w is SelectionArea &&
      (w.key is ValueKey<String>) &&
      (w.key as ValueKey<String>).value.startsWith('commentary_list_'),
);

List<String> _visibleSnackbarTexts(WidgetTester tester) => find
    .descendant(
      of: find.byType(Overlay),
      matching: find.byType(Text),
    )
    .evaluate()
    .map((e) => (e.widget as Text).data ?? '')
    .where((t) => t.isNotEmpty)
    .toList();

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxTries = 80,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibraryProvider implements LibraryProvider {
  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'T';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    return const [];
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    return {'מפרש בדיקה|1|txt'};
  }

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async {
    return 'זהו פירוש לבדיקה עם טקסט שניתן לבחור ולהעתיק';
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    return title == 'מפרש בדיקה';
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return const {};
  }
}
