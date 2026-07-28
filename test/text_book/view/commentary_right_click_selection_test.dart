import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

// שני היבטים של באג לחיצה ימנית במפרשים בצד ובכרטיסיית המפרשים:
// (1) פוקוס — ה-Listener שעוטף את רשימת המפרשים (מעל ה-ProgressiveScroll שהוא
//     אב ל-SelectionArea) מיקד את ProgressiveScroll בכל pointer-down כולל ימני,
//     וגזל פוקוס מ-SelectableRegion — כך שההדגשה נמחקה. התיקון מגדר את
//     ה-onPointerDown לדלג בלחיצה ימנית (kSecondaryButton).
// (2) העתקה — פעולת "העתק" קראה את הטקסט הנבחר בזמן הלחיצה (כבר null אחרי
//     שהבחירה שוחררה) במקום בזמן בניית התפריט. התיקון לוכד snapshot בבנייה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late _TestTextBookBloc textBookBloc;
  late _TestSettingsBloc settingsBloc;

  setUp(() {
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
    textBookBloc = _TestTextBookBloc(_loadedState());
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
  });

  tearDown(() async {
    await textBookBloc.close();
    await settingsBloc.close();
    LibraryProviderManager.instance.resetForTesting();
  });

  testWidgets(
    'ה-Listener הממקד קיים ומחובר מעל ProgressiveScroll (חוזה מבני לגארד)',
    (tester) async {
      await _pump(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
      );

      // ה-Listener הממקד הוא אב-קדמון של ProgressiveScroll (הוא עוטף את
      // ה-AppFutureBuilder שמכיל אותו) — לכן find.ancestor ולא find.descendant.
      final guards = tester
          .widgetList<Listener>(
            find.ancestor(
              of: find.byType(ProgressiveScroll),
              matching: find.byType(Listener),
            ),
          )
          .where(
            (l) =>
                l.behavior == HitTestBehavior.translucent &&
                l.onPointerDown != null,
          )
          .toList();
      expect(
        guards,
        isNotEmpty,
        reason: 'ה-Listener הממקד חייב להתקיים כדי שהגארד יחול עליו',
      );

      // מריצים את ה-callback האמיתי בלחיצה ימנית. עם התיקון הוא חוזר מוקדם ואינו
      // ממקד; אם הגארד יוסר, requestFocus ימקד את ProgressiveScroll ו-hasPrimaryFocus
      // יהפוך true — כך הרגרסיה נתפסת.
      final focusNode = tester
          .widget<ProgressiveScroll>(find.byType(ProgressiveScroll))
          .focusNode!;
      for (final guard in guards) {
        guard.onPointerDown!(
          PointerDownEvent(
            position: const Offset(100, 100),
            buttons: kSecondaryButton,
            kind: PointerDeviceKind.mouse,
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(
        focusNode.hasPrimaryFocus,
        isFalse,
        reason: 'לחיצה ימנית לא תופסת פוקוס ראשי ב-ProgressiveScroll',
      );
    },
  );

  // בודק את הפרדיקט של קוד הייצור עצמו (לא דמה) בשני הכיוונים: ימני לא ממקד,
  // שאר הכפתורים כן. מימוש שיפסיק למקד בכל לחיצה יפיל את בדיקת השמאלי.
  test('shouldFocusScrollOnPointerDown: ממקד בכל כפתור פרט לימני', () {
    expect(
      shouldFocusScrollOnPointerDown(kPrimaryButton),
      isTrue,
      reason: 'שמאלי ממקד — אחרת גלילת החיצים נשברת',
    );
    expect(
      shouldFocusScrollOnPointerDown(kMiddleMouseButton),
      isTrue,
      reason: 'אמצעי ממקד',
    );
    expect(
      shouldFocusScrollOnPointerDown(kSecondaryButton),
      isFalse,
      reason: 'ימני לא ממקד — אחרת הבחירה נמחקת',
    );
    // buttons הוא bitmask: לחיצה משולבת שכוללת ימני לא צריכה למקד.
    expect(
      shouldFocusScrollOnPointerDown(kPrimaryButton | kSecondaryButton),
      isFalse,
      reason: 'שמאלי+ימני יחד כולל ביט ימני — לא ממקד',
    );
  });

  group('לכידת טקסט נבחר בתפריט ההקשר', () {
    Link makeLink() => Link(
      heRef: 'רש"י על בראשית א:א',
      index1: 1,
      path2: 'אוצריא/תנך/פירושים/רשי.txt',
      index2: 1,
      connectionType: 'commentary',
    );

    testWidgets(
      'תפריט שנבנה עם טקסט נבחר: enabled ומעתיק גם אחרי איפוס המקור החי',
      (tester) async {
        // ה-listenable שהפאנל האמיתי מעביר ל-menuBuilder.
        final savedText = ValueNotifier<String?>('קטע מסומן להעתקה');
        addTearDown(savedText.dispose);
        String? copiedText;

        late List<AppContextMenuEntry> entries;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                // הלכידה דרך helper הייצור האמיתי: מחיקת ה-snapshot ממנו תגרום
                // לקריאה חיה (null אחרי האיפוס) ותפיל את הבדיקה.
                final savedTextAtBuild = captureSelectedTextForMenu(savedText);
                entries = ContextMenuUtils.buildCommentaryContextMenu(
                  context: context,
                  link: makeLink(),
                  openBookCallback: (_) {},
                  fontSize: 18,
                  removeNikud: false,
                  removePunctuation: false,
                  savedSelectedText: savedTextAtBuild,
                  onCopySelected: () => copiedText = savedTextAtBuild,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final copyEntry = entries.firstWhere((e) => e.label == 'העתק');
        expect(
          copyEntry.enabled,
          isTrue,
          reason: 'בזמן הבנייה יש טקסט נבחר — "העתק" חייב להיות פעיל',
        );

        // לחיצה ימנית שחררה את הבחירה: המקור החי מתאפס לפני שנלחץ "העתק".
        savedText.value = null;

        copyEntry.onTap!();
        expect(
          copiedText,
          'קטע מסומן להעתקה',
          reason: 'ההעתקה חייבת להשתמש בטקסט שנלכד בבנייה, לא בערך המנוקה',
        );
      },
    );

    // בדיקה ישירה של helper הלכידה: לוכד את הערך בזמן הקריאה ואינו רגיש
    // לשינויים מאוחרים של ה-listenable.
    test('captureSelectedTextForMenu לוכד את הערך הנוכחי בלבד', () {
      final saved = ValueNotifier<String?>('לפני');
      addTearDown(saved.dispose);

      final snapshot = captureSelectedTextForMenu(saved);
      saved.value = null;

      expect(
        snapshot,
        'לפני',
        reason: 'ה-snapshot חייב להישאר יציב אחרי שהמקור החי השתנה',
      );
    });

    testWidgets('טקסט נבחר ריק/רווחים בלבד — פריט "העתק" מושבת', (
      tester,
    ) async {
      for (final blank in <String?>[null, '', '   ']) {
        late List<AppContextMenuEntry> entries;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                entries = ContextMenuUtils.buildCommentaryContextMenu(
                  context: context,
                  link: makeLink(),
                  openBookCallback: (_) {},
                  fontSize: 18,
                  removeNikud: false,
                  removePunctuation: false,
                  savedSelectedText: blank,
                  onCopySelected: () {},
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final copyEntry = entries.firstWhere((e) => e.label == 'העתק');
        expect(
          copyEntry.enabled,
          isFalse,
          reason: 'טקסט "${blank ?? 'null'}" אינו בחירה תקפה',
        );
      }
    });
  });

  group('פריט "דווח על טעות בספר"', () {
    Link officialLink() => Link(
      heRef: 'רש"י על בראשית א:א',
      index1: 1,
      path2: 'אוצריא/תנך/פירושים/רשי.txt',
      index2: 1,
      connectionType: 'commentary',
    );

    Link userLink() => Link(
      heRef: 'הערה אישית',
      index1: 1,
      path2: 'ספר אישי.txt',
      index2: 1,
      connectionType: 'commentary',
      targetIsUserBook: true,
    );

    Future<List<AppContextMenuEntry>> pumpMenu(
      WidgetTester tester,
      Link link,
    ) async {
      late List<AppContextMenuEntry> entries;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              entries = ContextMenuUtils.buildCommentaryContextMenu(
                context: context,
                link: link,
                openBookCallback: (_) {},
                fontSize: 18,
                removeNikud: false,
                removePunctuation: false,
                savedSelectedText: null,
                onCopySelected: () {},
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return entries;
    }

    testWidgets('מוצג עבור מפרש רשמי', (tester) async {
      final entries = await pumpMenu(tester, officialLink());
      expect(
        entries.any((e) => e.label == 'דווח על טעות בספר'),
        isTrue,
        reason: 'מפרש רשמי — חייב להיות ניתן לדווח עליו',
      );
    });

    testWidgets('מוסתר עבור ספר משתמש', (tester) async {
      final entries = await pumpMenu(tester, userLink());
      expect(
        entries.any((e) => e.label == 'דווח על טעות בספר'),
        isFalse,
        reason: 'ספר משתמש — אין למי לדווח, הפריט מוסתר',
      );
    });
  });

  group('commentaryReportArgs — מיפוי מפרש לפרמטרי דיווח', () {
    Link commentaryLink() => Link(
      heRef: 'רש"י על בראשית א:א',
      index1: 1,
      path2: 'אוצריא/תנך/פירושים/רשי.txt',
      index2: 42,
      connectionType: 'commentary',
      targetCategoryId: 7,
      targetFileType: 'txt',
    );

    test('הדיווח מופנה לספר המפרש, לאינדקס ולתוכן שלו', () {
      final args = ContextMenuUtils.commentaryReportArgs(
        link: commentaryLink(),
        rawContent: '<b>תוכן המפרש</b>',
        savedSelectedText: null,
      );

      expect(
        args.book.title,
        'רשי',
        reason: 'הספר המדווח הוא המפרש (path2), לא הספר הראשי',
      );
      expect(args.book.categoryId, 7);
      expect(args.book.fileType, 'txt');
      expect(args.book.isUserBook, isFalse);
      expect(args.bookTitle, 'רשי');
      expect(
        args.lineIndex,
        41,
        reason: 'index2 הוא 1-based; האינדקס לדיווח הוא index2-1',
      );
      expect(args.content, const [
        '<b>תוכן המפרש</b>',
      ], reason: 'reportContent הוא תוכן המפרש הגולמי (שורה בודדת)');
    });

    test('ללא בחירה — selectedText הוא כל פסקת המפרש (ללא HTML)', () {
      final args = ContextMenuUtils.commentaryReportArgs(
        link: commentaryLink(),
        rawContent: '<b>תוכן</b> המפרש',
        savedSelectedText: '   ',
      );

      expect(
        args.selectedText,
        'תוכן המפרש',
        reason: 'בחירה ריקה/רווחים — נופלים לכל הפסקה, מנוקה מ-HTML',
      );
    });

    test('עם בחירה — selectedText הוא הטקסט שסומן', () {
      final args = ContextMenuUtils.commentaryReportArgs(
        link: commentaryLink(),
        rawContent: '<b>תוכן</b> המפרש',
        savedSelectedText: 'קטע מסומן',
      );

      expect(args.selectedText, 'קטע מסומן');
      expect(args.content, const [
        '<b>תוכן</b> המפרש',
      ], reason: 'התוכן המדווח נשאר פסקת המפרש המלאה גם כשיש בחירה');
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required TextBookBloc textBookBloc,
  required SettingsBloc settingsBloc,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: CommentaryListBase(
            openBookCallback: (_) {},
            fontSize: 18,
            showSearch: true,
            shrinkWrap: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
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
    return 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';
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
