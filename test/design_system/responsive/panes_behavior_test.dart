// התנהגות חלוניות צד (AdaptiveSidePane) ופיצול: גרירה, מעבר רחב/צר, נעיצה.
// בדיקות רגרסיה להתנהגות חלוניות הצד והפיצול (סבב ה-QA ב-17.11.2026).
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/view/reading_tabs_side_panel.dart';
import 'package:otzaria/navigation/view/vertical_reading_tab_strip.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/theme/app_motion.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/side_pane_specs.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_tabs_bloc.dart';

/// חלונית צד בצד ימין (centerEnd), עם רוחב ש"הורה" מחזיק כמו במסכי הקורא.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.width,
    this.paneWidth = 300,
    this.minMain = 520,
    this.maxPane,
    this.autoHandle = false,
    this.floatOver = false,
    this.onClose,
    this.modes,
    this.resizeEnds,
  });

  final double width;
  final double paneWidth;
  final double minMain;
  final double? maxPane;
  final bool autoHandle;
  final bool floatOver;
  final VoidCallback? onClose;
  final List<bool>? modes;
  final List<double>? resizeEnds;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late double paneWidth = widget.paneWidth;
  bool isOpen = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: widget.width,
              height: 700,
              child: AdaptiveSidePane(
                isOpen: isOpen,
                paneWidth: paneWidth,
                minMainContentWidth: widget.minMain,
                minPaneWidth: 200,
                maxPaneWidth: widget.maxPane,
                isResizable: true,
                floatOverContent: widget.floatOver,
                autoHandleResponsiveVisibility: widget.autoHandle,
                onClose: () {
                  widget.onClose?.call();
                  setState(() => isOpen = false);
                },
                onOpen: () {
                  setState(() => isOpen = true);
                },
                onPaneWidthChanged: (w) => setState(() => paneWidth = w),
                onPaneResizeEnd: () => widget.resizeEnds?.add(paneWidth),
                onLayoutModeChanged: widget.modes?.add,
                mainContent: const SizedBox.expand(key: ValueKey('main')),
                paneContent: const Text('pane'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double get width => paneWidth;

  void setOpen(bool value) => setState(() => isOpen = value);
}

void main() {
  void setWindow(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('גרירה לא מפילה את החלונית ל-overlay', () {
    testWidgets('גרירה רחבה מדי נעצרת ברוחב שמשאיר את minMainContentWidth', (
      tester,
    ) async {
      setWindow(tester, 1100);
      final modes = <bool>[];
      final ends = <double>[];
      await tester.pumpWidget(
        _Harness(width: 1100, maxPane: 700, modes: modes, resizeEnds: ends),
      );
      await tester.pumpAndSettle();
      expect(modes.last, isTrue, reason: 'מתחילים במצב דחיקה');

      // ימין = חלונית; גרירה שמאלה מרחיבה אותה. 400 פיקסל = 700, מעבר לתקרה.
      await tester.drag(
        find.byType(ResizableDragHandle),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      final state = tester.state<_HarnessState>(find.byType(_Harness));
      // 1100 - 520 (תוכן) - 22 (רווחים) = 558
      expect(state.width, 558);
      expect(ends, [558]);
      expect(
        modes.last,
        isTrue,
        reason: 'אחרי שחרור החלונית עדיין דוחקת את התוכן, לא שכבה',
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('main'))).width,
        greaterThanOrEqualTo(520),
      );
    });

    testWidgets('עם autoHandle הגרירה לא סוגרת את החלונית', (tester) async {
      setWindow(tester, 800);
      var closed = 0;
      await tester.pumpWidget(
        _Harness(
          width: 800,
          autoHandle: true,
          minMain: 320,
          maxPane: 500,
          onClose: () => closed++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(ResizableDragHandle),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      expect(closed, 0);
      expect(find.text('pane'), findsOneWidget);
      final state = tester.state<_HarnessState>(find.byType(_Harness));
      expect(state.width, 800 - 320 - 22);
    });

    testWidgets('ללא maxPaneWidth התקרה נגזרת מהרוחב הפנוי', (tester) async {
      setWindow(tester, 1000);
      final modes = <bool>[];
      await tester.pumpWidget(_Harness(width: 1000, modes: modes));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(ResizableDragHandle),
        const Offset(-900, 0),
      );
      await tester.pumpAndSettle();

      final state = tester.state<_HarnessState>(find.byType(_Harness));
      expect(state.width, 1000 - 520 - 22);
      expect(modes.last, isTrue);
    });

    testWidgets('חלונית שצפה מעל התוכן נחתכת באותה תקרה', (tester) async {
      setWindow(tester, 1000);
      final modes = <bool>[];
      await tester.pumpWidget(
        _Harness(width: 1000, floatOver: true, modes: modes),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(ResizableDragHandle),
        const Offset(-900, 0),
      );
      await tester.pumpAndSettle();

      final state = tester.state<_HarnessState>(find.byType(_Harness));
      expect(state.width, lessThanOrEqualTo(1000 - 520));
    });
  });

  group('מעבר רחב-צר-רחב עם חלונית נעוצה (שלב 3, סעיפים 3, 5, 13)', () {
    testWidgets('הנעיצה, הפתיחות והרוחב השמור נשמרים בצמצום ובהרחבה', (
      tester,
    ) async {
      setWindow(tester, 1100);
      final modes = <bool>[];
      await tester.pumpWidget(_Harness(width: 1100, modes: modes));
      await tester.pumpAndSettle();
      final state = tester.state<_HarnessState>(find.byType(_Harness));
      expect(modes.last, isTrue);

      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(_Harness(width: 700, modes: modes));
        await tester.pumpAndSettle();
        expect(modes.last, isFalse, reason: 'חלון צר: שכבה');
        expect(state.isOpen, isTrue, reason: 'החלונית לא נסגרת בצמצום');
        expect(state.width, 300, reason: 'הרוחב השמור לא משתנה');
        expect(find.text('pane'), findsOneWidget);

        await tester.pumpWidget(_Harness(width: 1100, modes: modes));
        await tester.pumpAndSettle();
        expect(modes.last, isTrue, reason: 'חלון רחב: דחיקה שוב');
        expect(state.isOpen, isTrue);
        expect(state.width, 300);
        expect(
          tester.getSize(find.byKey(const ValueKey('main'))).width,
          greaterThanOrEqualTo(520),
        );
      }
    });

    testWidgets('גרירה לגבולות: מינימום ומקסימום, ושניהם שמישים', (
      tester,
    ) async {
      setWindow(tester, 1100);
      await tester.pumpWidget(_Harness(width: 1100, maxPane: 420));
      await tester.pumpAndSettle();
      final state = tester.state<_HarnessState>(find.byType(_Harness));
      final handle = find.byType(ResizableDragHandle);

      await tester.drag(handle, const Offset(-900, 0));
      await tester.pumpAndSettle();
      expect(state.width, 420);

      await tester.drag(handle, const Offset(900, 0));
      await tester.pumpAndSettle();
      expect(state.width, 200);
      // אחרי הגרירה לקצה הידית עדיין במקומה וניתנת לגרירה.
      expect(find.byType(ResizableDragHandle), findsOneWidget);
    });

    testWidgets('שינוי גודל החלון באמצע גרירה: התקרה לפי הרוחב החדש', (
      tester,
    ) async {
      setWindow(tester, 1100);
      await tester.pumpWidget(_Harness(width: 1100));
      await tester.pumpAndSettle();
      final state = tester.state<_HarnessState>(find.byType(_Harness));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ResizableDragHandle)),
      );
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();

      // החלון מצטמצם בזמן שהאצבע עדיין על הידית.
      await tester.pumpWidget(_Harness(width: 900));
      await gesture.moveBy(const Offset(-600, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(state.width, lessThanOrEqualTo(900 - 520 - 22));
      expect(state.isOpen, isTrue);
    });

    testWidgets('פתיחה וסגירה מרובות בין רוחבים לא משאירות מצב תקוע', (
      tester,
    ) async {
      setWindow(tester, 1100);
      await tester.pumpWidget(_Harness(width: 1100));
      await tester.pumpAndSettle();
      final state = tester.state<_HarnessState>(find.byType(_Harness));

      for (final width in [1100.0, 500.0, 1100.0, 300.0, 1100.0]) {
        await tester.pumpWidget(_Harness(width: width));
        state.setOpen(false);
        await tester.pumpAndSettle();
        state.setOpen(true);
        await tester.pumpAndSettle();
        expect(state.isOpen, isTrue);
        expect(find.text('pane'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('שחזור פריסה אחרי הפעלה מחדש (שלב 10, סעיף 20)', () {
    setUp(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    testWidgets('הרוחבים נשמרים אחרי גרירה ונטענים ב"הפעלה" חדשה', (
      tester,
    ) async {
      setWindow(tester, 1100);
      final saved = <Future<void>>[];
      final ends = <double>[];
      await tester.pumpWidget(_Harness(width: 1100, resizeEnds: ends));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ResizableDragHandle),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      expect(ends, isNotEmpty);

      // אתחול ברירות המחדל בהפעלה ראשונה (loadSettings), ואז שמירה כמו
      // onPaneResizeEnd במסכי הקורא.
      final repository = SettingsRepository();
      await tester.runAsync(repository.loadSettings);
      saved
        ..add(repository.updateSidebarWidth(ends.last))
        ..add(repository.updateCommentaryPaneWidth(ends.last - 40))
        ..add(repository.updateReadingTabsColumnWidth(260))
        ..add(repository.updateFacetFilteringWidth(310));
      await tester.runAsync(() => Future.wait(saved));

      // "הפעלה מחדש": מופע חדש של המאגר, וחלון חדש.
      final restored = (await tester.runAsync(
        () => SettingsRepository().loadSettings(),
      ))!;
      expect(restored['sidebarWidth'], ends.last);
      expect(restored['commentaryPaneWidth'], ends.last - 40);
      expect(restored['readingTabsColumnWidth'], 260);
      expect(restored['facetFilteringWidth'], 310);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _Harness(width: 1100, paneWidth: restored['sidebarWidth'] as double),
      );
      await tester.pumpAndSettle();
      final state = tester.state<_HarnessState>(find.byType(_Harness));
      expect(state.width, ends.last);
    });
  });

  group('פתיחה אוטומטית של חלונית הניווט לפי המקום', () {
    setUp(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      await Settings.setValue('key-default-sidebar-open', true);
      await Settings.setValue('key-pin-sidebar', false);
    });

    test('קורא טקסט: ב-700 החלונית לא נפתחת כשכבה על הספר, ב-900 כן', () {
      expect(shouldAutoOpenReadingLeftPane(screenWidth: 700), isFalse);
      expect(shouldAutoOpenReadingLeftPane(screenWidth: 819), isFalse);
      expect(shouldAutoOpenReadingLeftPane(screenWidth: 900), isTrue);
    });

    test('PDF דורש פחות מקום לתוכן, ולכן נפתחת כבר ב-700', () {
      expect(
        shouldAutoOpenReadingLeftPane(
          screenWidth: 700,
          minMainContentWidth: SidePaneSpecs.pdfReaderNav.minMainContentWidth,
        ),
        isTrue,
      );
    });

    test('מסך צר נשאר סגור גם כשהתוכן קטן (חוזה הטלפון)', () {
      expect(
        shouldAutoOpenReadingLeftPane(
          screenWidth: 411,
          minMainContentWidth: SidePaneSpecs.pdfReaderNav.minMainContentWidth,
        ),
        isFalse,
      );
    });

    test('רוחב שמור גדול מזיז את הסף', () async {
      await Settings.setValue('key-sidebar-width', 500.0);
      expect(shouldAutoOpenReadingLeftPane(screenWidth: 1000), isFalse);
      expect(shouldAutoOpenReadingLeftPane(screenWidth: 1100), isTrue);
    });

    test('נעיצה: נפתחת רק כשהיא נדחסת, ובקשה מפורשת נשארת פתוחה', () async {
      await Settings.setValue('key-pin-sidebar', true);
      await Settings.setValue('key-default-sidebar-open', false);
      expect(
        resolveInitialReadingLeftPaneVisibility(
          explicitOpen: false,
          screenWidth: 700,
        ),
        isFalse,
      );
      expect(
        resolveInitialReadingLeftPaneVisibility(
          explicitOpen: false,
          screenWidth: 1400,
        ),
        isTrue,
      );
      expect(
        resolveInitialReadingLeftPaneVisibility(
          explicitOpen: true,
          screenWidth: 700,
        ),
        isTrue,
      );
    });
  });

  group('גרירה בפריסה הצרה', () {
    testWidgets(
      'חלונית סגורה: הידית השקופה אינה תחנת פוקוס ולא נחשפת לקורא מסך',
      (
        tester,
      ) async {
        setWindow(tester, 420);
        await tester.pumpWidget(_Harness(width: 420, maxPane: 700));
        await tester.pumpAndSettle();
        final handle = find.byType(ResizableDragHandle);
        expect(handle, findsOneWidget);
        expect(
          find
              .ancestor(of: handle, matching: find.byType(ExcludeFocus))
              .evaluate()
              .map((e) => (e.widget as ExcludeFocus).excluding),
          everyElement(isFalse),
          reason: 'חלונית פתוחה: הידית נגישה במקלדת',
        );

        tester.state<_HarnessState>(find.byType(_Harness)).setOpen(false);
        await tester.pumpAndSettle();

        expect(
          find
              .ancestor(of: handle, matching: find.byType(ExcludeFocus))
              .evaluate()
              .map((e) => (e.widget as ExcludeFocus).excluding),
          contains(true),
          reason: 'חלונית סגורה: אין עצירת Tab סמויה על הידית',
        );
        expect(
          find
              .ancestor(of: handle, matching: find.byType(ExcludeSemantics))
              .evaluate()
              .map((e) => (e.widget as ExcludeSemantics).excluding),
          contains(true),
        );
      },
    );

    testWidgets('רוחב שמור גדול מהחלון: גרירה פנימה מקטינה מיד', (
      tester,
    ) async {
      setWindow(tester, 420);
      await tester.pumpWidget(
        _Harness(width: 420, paneWidth: 600, maxPane: 700),
      );
      await tester.pumpAndSettle();
      // רוחב מוצג: 420 - 2*10 = 400, אך הערך הפנימי 600.
      final handle = find.byType(ResizableDragHandle);
      expect(handle, findsOneWidget);

      // ימין = חלונית; גרירה ימינה מצמצמת אותה.
      await tester.drag(handle, const Offset(60, 0));
      await tester.pumpAndSettle();

      final state = tester.state<_HarnessState>(find.byType(_Harness));
      expect(
        state.width,
        lessThan(400),
        reason: 'הערך הנשמר חייב להיות קטן ממה שנראה על המסך, לא אזור מת',
      );
    });
  });

  group(
    'ידית שינוי גודל נגישה במקלדת ובקורא מסך',
    () {
      testWidgets('חצים מזיזים את הידית ומשמרים את הרוחב בסיום כמו גרירה', (
        tester,
      ) async {
        setWindow(tester, 1100);
        final ends = <double>[];
        await tester.pumpWidget(_Harness(width: 1100, resizeEnds: ends));
        await tester.pumpAndSettle();
        final state = tester.state<_HarnessState>(find.byType(_Harness));
        expect(state.width, 300);

        // הידית היא הרכיב היחיד שאפשר למקד.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        // החלונית בימין: הזזת הידית שמאלה מרחיבה אותה.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(state.width, 300 + kResizeHandleKeyboardStep);
        expect(ends, [300 + kResizeHandleKeyboardStep]);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(state.width, 300);
        expect(ends.length, 2);
      });

      testWidgets('קורא מסך: מחוון עם פעולות הגדלה והקטנה', (tester) async {
        setWindow(tester, 1100);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(_Harness(width: 1100));
        await tester.pumpAndSettle();

        final handle = find.descendant(
          of: find.byType(ResizableDragHandle),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.slider == true,
          ),
        );
        expect(
          tester.getSemantics(handle),
          isSemantics(
            isSlider: true,
            isFocusable: true,
            hasIncreaseAction: true,
            hasDecreaseAction: true,
          ),
        );

        final state = tester.state<_HarnessState>(find.byType(_Harness));
        _performSemantic(tester, handle, SemanticsAction.increase);
        await tester.pumpAndSettle();
        expect(state.width, 300 + kResizeHandleKeyboardStep);
        _performSemantic(tester, handle, SemanticsAction.decrease);
        expect(state.width, 300);
        semantics.dispose();
        expect(state.width, 300);
      });

      testWidgets('הזזה במקלדת מכבדת את תקרת הרוחב הפנוי', (tester) async {
        setWindow(tester, 1100);
        await tester.pumpWidget(_Harness(width: 1100, paneWidth: 550));
        await tester.pumpAndSettle();
        final state = tester.state<_HarnessState>(find.byType(_Harness));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pumpAndSettle();
        }
        expect(state.width, 1100 - 520 - 22);
      });
    },
  );

  group('שער רוחב לפיצול', () {
    setUp(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    PdfBookTab leaf(String title) => PdfBookTab(
      book: PdfBook(title: title, path: '/tmp/$title.pdf'),
      pageNumber: 1,
    );

    Future<TabsBloc> blocWith(List<OpenedTab> tabs) async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      addTearDown(bloc.close);
      bloc.add(ReplaceAllTabs(tabs, 0));
      await bloc.stream.firstWhere((s) => s.tabs.length == tabs.length);
      return bloc;
    }

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    test('אזור קריאה צר: "ספר מלווה" נפתח ככרטיסייה ולא כפיצול', () async {
      final bloc = await blocWith([leaf('א')]);
      reportReadingAreaWidth(bloc, 200);

      bloc.add(OpenTabInSidePane(leaf('ב')));
      await settle();

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.tabs.whereType<CombinedTab>(), isEmpty);
      expect(bloc.state.currentTab?.title, 'ב');
    });

    test('אזור קריאה רחב: הפיצול נוצר כרגיל', () async {
      final bloc = await blocWith([leaf('א')]);
      reportReadingAreaWidth(bloc, 1000);

      bloc.add(OpenTabInSidePane(leaf('ב')));
      await bloc.stream.firstWhere((s) => s.tabs.any((t) => t is CombinedTab));

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.tabs.single, isA<CombinedTab>());
    });

    test('אזור קריאה צר: "הצג לצד" לא ממזג את שני הטאבים', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([a, b]);
      reportReadingAreaWidth(bloc, 200);

      bloc.add(CreateCombinedTab(rightTab: a, leftTab: b));
      await settle();

      expect(bloc.state.tabs, [same(a), same(b)]);
    });

    // ספר מלווה נפתח אוטומטית כפיצול בכל פתיחת כרטיסייה (withCompanionPane),
    // ולכן גם הוא עובר בשער.
    Future<TabsBloc> blocWithCompanion(List<String> asked) async {
      final bloc = TabsBloc(
        repository: _FakeTabsRepository(),
        withCompanion: (tab) async {
          asked.add(tab.title);
          return CombinedTab(rightTab: tab, leftTab: leaf('מלווה'));
        },
      );
      addTearDown(bloc.close);
      return bloc;
    }

    test('אזור קריאה צר: ספר מלווה לא נפתח מפוצל', () async {
      final asked = <String>[];
      final bloc = await blocWithCompanion(asked);
      reportReadingAreaWidth(bloc, 200);

      bloc.add(AddTab(leaf('א')));
      await settle();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.tabs.single, isA<PdfBookTab>());
      expect(asked, isEmpty, reason: 'לא מחפשים מלווה כשאין מקום לו');
    });

    test('אזור קריאה רחב: ספר מלווה נפתח מפוצל כרגיל', () async {
      final asked = <String>[];
      final bloc = await blocWithCompanion(asked);
      reportReadingAreaWidth(bloc, 1000);

      bloc.add(AddTab(leaf('א')));
      await bloc.stream.firstWhere((s) => s.tabs.any((t) => t is CombinedTab));

      expect(bloc.state.tabs.single, isA<CombinedTab>());
      expect(asked, ['א']);
    });

    test('רוחב לא מדווח (null): אין הגבלה', () async {
      final bloc = await blocWith([leaf('א')]);
      expect(canSplitReadingArea(bloc), isTrue);
    });
  });

  group('הפיכת דף ב-PDF מכבדת הפחתת תנועה', () {
    const single = Duration(milliseconds: 500);

    test('בהפחתת תנועה המשך אפס, ובלעדיה נשאר המשך המלא', () {
      expect(
        pdfQueuedPageTurnDuration(single, 0, reduced: true),
        Duration.zero,
      );
      expect(
        pdfQueuedPageTurnDuration(single, 3, reduced: true),
        Duration.zero,
      );
      expect(pdfQueuedPageTurnDuration(single, 0), single);
    });

    testWidgets('בקר עם משך אפס מגיע ליעד מיד, בלי פריימים', (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: pdfQueuedPageTurnDuration(single, 0, reduced: true),
      );
      addTearDown(controller.dispose);

      await controller.forward(from: 0);

      expect(controller.value, 1);
      expect(controller.isAnimating, isFalse);
    });

    testWidgets('בקר שנוצר ב-initState מושפע מהעדפת המערכת', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      expect(AppMotion.controller(single), Duration.zero);
    });
  });

  group('עמודת כרטיסיות בצד שומרת מקום לתוכן', () {
    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    Future<void> pumpColumn(
      WidgetTester tester, {
      required double area,
      required double saved,
      bool collapsed = false,
    }) async {
      final tabs = [_StubTab('ספר א'), _StubTab('ספר ב')];
      final tabsBloc = StubTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
      final settingsBloc = StubSettingsBloc(
        SettingsState.initial().copyWith(
          readingTabsPlacement: SettingsRepository.readingTabsPlacementSide,
          readingTabsColumnWidth: saved,
          readingTabsColumnCollapsed: collapsed,
        ),
      );
      final historyBloc = _HistoryBloc();
      final workspaceBloc = _WorkspaceBloc();
      addTearDown(() async {
        await tabsBloc.close();
        await settingsBloc.close();
        await historyBloc.close();
        await workspaceBloc.close();
      });
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<WorkspaceBloc>.value(value: workspaceBloc),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: area,
                    height: 600,
                    child: const ReadingTabsSidePanel(
                      show: true,
                      child: SizedBox.expand(key: ValueKey('content')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('רוחב שמור 400 באזור של 526: לתוכן נשארים לפחות 320', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // חלון 600 פחות עמודת ניווט (74).
      await pumpColumn(tester, area: 526, saved: 400);

      expect(
        tester.getSize(find.byKey(const ValueKey('content'))).width,
        greaterThanOrEqualTo(LayoutConstraints.minContentBesideTabsColumn),
      );
    });

    // במצב מכווץ השם בא רק מה-tooltip; tooltip רגיל בולע את
    // הלחיצה הארוכה, ובמגע אין דרך אחרת לפתוח את תפריט הכרטיסיה (וסגירה).
    testWidgets('מכווצת: לחיצה ארוכה במגע פותחת את תפריט הכרטיסיה', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpColumn(tester, area: 1126, saved: 220, collapsed: true);

      // שורת כרטיסיה בעמודה, לא כפתורי הכותרת שלה (גם להם tooltip).
      final row = find
          .descendant(
            of: find.byType(VerticalReadingTabStrip),
            matching: find.byType(Tooltip),
          )
          .first;
      final gesture = await tester.startGesture(
        tester.getCenter(row),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('סגור הכל'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('רוחב שמור סביר לא נחתך (1200)', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpColumn(tester, area: 1126, saved: 400);

      expect(tester.getSize(find.byKey(const ValueKey('content'))).width, 726);
    });
  });
}

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

class _HistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _HistoryBloc() : super(HistoryInitial());

  @override
  void add(HistoryEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorkspaceBloc extends Cubit<WorkspaceState> implements WorkspaceBloc {
  _WorkspaceBloc() : super(WorkspaceState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _performSemantic(
  WidgetTester tester,
  Finder finder,
  SemanticsAction action,
) {
  final id = tester.getSemantics(finder).id;
  tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    id,
    action,
  );
}

class _FakeTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}
