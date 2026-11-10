import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import '../../test_helpers/fake_commentary_library_provider.dart';
import '../../test_helpers/memory_cache_provider.dart';

AppContextMenuIconAction iconAction(
  List<AppContextMenuEntry> entries,
  String label,
) => entries.first.iconRowActions!.firstWhere((a) => a.label == label);

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
        ): FakeCommentaryLibraryProvider(),
      },
      providers: [FakeCommentaryLibraryProvider()],
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
      targetCategoryId: 42,
      targetBookId: 907,
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
                  displayProfile: TextDisplayProfile.defaults,
                  savedSelectedText: savedTextAtBuild,
                  onCopySelected: () => copiedText = savedTextAtBuild,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final copyEntry = iconAction(entries, 'העתקה');
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
                  displayProfile: TextDisplayProfile.defaults,
                  savedSelectedText: blank,
                  onCopySelected: () {},
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final copyEntry = iconAction(entries, 'העתקה');
        expect(
          copyEntry.enabled,
          isFalse,
          reason: 'טקסט "${blank ?? 'null'}" אינו בחירה תקפה',
        );
      }
    });

    testWidgets('שורת אייקונים: חיפוש, העתקה, הערה וקישור ישיר', (
      tester,
    ) async {
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
                displayProfile: TextDisplayProfile.defaults,
                savedSelectedText: 'קטע מסומן',
                onCopySelected: () {},
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        entries.first.iconRowActions!.map((action) => action.label),
        ['חיפוש', 'העתקה', 'הערה', 'קישור'],
      );
      expect(entries.last.label, 'דווח על טעות בספר');
      final children = iconAction(entries, 'קישור').submenuBuilder!();
      expect(
        children.map((entry) => entry.label),
        containsAll(<String>[
          'העתק קישור למקטע זה',
          'העתק קישור עם הדגשת המקטע',
          'העתק קישור עם הדגשת הטקסט',
        ]),
      );
    });

    testWidgets('הקישור נבנה לפי targetBookId ולא לפי targetCategoryId', (
      tester,
    ) async {
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
                displayProfile: TextDisplayProfile.defaults,
                savedSelectedText: null,
                onCopySelected: () {},
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      iconAction(entries, 'קישור').submenuBuilder!().first.onTap!();
      await tester.pump();

      expect(copied, 'otzaria://open/book/907?index=0');
    });

    testWidgets('בלי targetBookId אין אייקון "קישור"', (tester) async {
      late List<AppContextMenuEntry> entries;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              entries = ContextMenuUtils.buildCommentaryContextMenu(
                context: context,
                link: Link(
                  heRef: 'הערה אישית',
                  index1: 1,
                  path2: 'ספר אישי.txt',
                  index2: 1,
                  connectionType: 'commentary',
                  targetCategoryId: 42,
                  targetSource: BookSource.user,
                ),
                openBookCallback: (_) {},
                fontSize: 18,
                displayProfile: TextDisplayProfile.defaults,
                savedSelectedText: null,
                onCopySelected: () {},
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        entries.first.iconRowActions!.map((action) => action.label),
        isNot(contains('קישור')),
      );
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
      targetSource: BookSource.user,
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
                displayProfile: TextDisplayProfile.defaults,
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

    test('מפרש בשורה אחת: השורה הגולמית מוצמדת לאינדקס של ספר המפרש', () {
      final args = ContextMenuUtils.commentaryReportArgs(
        link: commentaryLink(),
        rawContent: '<b>תוכן</b> המפרש',
      );
      expect(args.reportLine, '<b>תוכן</b> המפרש');
      const snapshot = ReportSourceSnapshot(
        bookId: 3,
        lineIndex: 41,
        heRef: null,
        originalLine: '<b>תוכן</b> המפרש',
      );
      expect(
        ErrorReportHelper.isSourceConsistentWithContent(
          snapshot,
          args.content,
          reportLine: args.reportLine,
        ),
        isTrue,
        reason: 'בלי reportLine הבדיקה השוותה ל-content[41] ברשימה של שורה אחת',
      );
      expect(
        ErrorReportHelper.isSourceConsistentWithContent(
          const ReportSourceSnapshot(
            bookId: 3,
            lineIndex: 41,
            heRef: null,
            originalLine: 'שורה אחרת ב-DB',
          ),
          args.content,
          reportLine: args.reportLine,
        ),
        isFalse,
      );
    });

    test('קישור-טווח: אין שורה גולמית יחידה — אין מסלול הצעת תיקון', () {
      final link = Link(
        heRef: 'רש"י על בראשית א:א',
        index1: 1,
        path2: 'אוצריא/תנך/פירושים/רשי.txt',
        index2: 42,
        index2End: 44,
        connectionType: 'commentary',
      );
      final args = ContextMenuUtils.commentaryReportArgs(
        link: link,
        rawContent: 'א<br>ב<br>ג',
      );
      expect(args.reportLine, isNull);
      expect(
        ErrorReportHelper.isSourceConsistentWithContent(
          const ReportSourceSnapshot(
            bookId: 3,
            lineIndex: 41,
            heRef: null,
            originalLine: 'א',
          ),
          args.content,
          reportLine: args.reportLine,
        ),
        isFalse,
      );
    });
  });

  for (final (key, shortcut) in [
    (LogicalKeyboardKey.keyR, null),
    (LogicalKeyboardKey.arrowUp, 'ctrl+shift+arrowup'),
    (LogicalKeyboardKey.arrowDown, 'ctrl+shift+arrowdown'),
  ]) {
    testWidgets('קיצור ${key.keyLabel} מדווח על בחירה במפרש (issue #2678)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      ShortcutHelper.isMacForTesting = false;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        ShortcutHelper.isMacForTesting = null;
      });
      final previous = Settings.getValue<String>(
        ShortcutValidator.reportErrorKey,
      );
      await Settings.setValue(
        ShortcutValidator.reportErrorKey,
        shortcut,
      );
      addTearDown(
        () => Settings.setValue(ShortcutValidator.reportErrorKey, previous),
      );
      final bookKeys = <LogicalKeyboardKey>[];
      await _pump(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
        onBookKey: (e) {
          if (e is KeyDownEvent) bookKeys.add(e.logicalKey);
        },
      );
      final modifier = ShortcutHelper.usesMacModifiers
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      Future<void> pressReport() async {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
      }

      await tester.tap(find.textContaining('זהו פירוש'));
      await tester.pump(kDoubleTapTimeout);
      await pressReport();
      expect(bookKeys, contains(key), reason: 'בלי בחירה');

      bookKeys.clear();
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await pressReport();
      expect(
        bookKeys,
        isNot(contains(key)),
        reason: 'הדיווח נפתח על המפרש, ולא על הספר הראשי שמסביב',
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required TextBookBloc textBookBloc,
  required SettingsBloc settingsBloc,
  ValueChanged<KeyEvent>? onBookKey,
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
          // כמו ה-KeyboardListener של מסך הספר שמעל חלונית המפרשים.
          body: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: onBookKey ?? (_) {},
            child: CommentaryListBase(
              openBookCallback: (_) {},
              fontSize: 18,
              showSearch: true,
              shrinkWrap: false,
            ),
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
