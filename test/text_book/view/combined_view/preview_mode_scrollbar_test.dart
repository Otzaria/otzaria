import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
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
import 'package:otzaria/text_book/view/selection/enhanced_gesture_detector.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
import '../../../test_helpers/memory_cache_provider.dart';

/// שורות ספר אמיתיות אינן בגובה אחיד — שורה קצרה לעומת פסקה שנשברת לכמה
/// שורות. זה בדיוק המצב שבו אומדן ההיקף של ListView מתנודד.
const int _lineCount = 120;

List<String> _variableHeightContent() => List.generate(_lineCount, (i) {
  final words = const [2, 4, 30, 3, 12, 60][i % 6];
  return List.filled(words, 'מילה$i').join(' ');
});

TextBookLoaded _loadedState(List<String> content) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: content,
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: null,
    pinLeftPane: false,
    searchText: '',
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  final List<TextBookEvent>? eventLog;

  _TestTextBookBloc(super.initialState, {this.eventLog}) {
    on<TextBookEvent>((event, emit) => eventLog?.add(event));
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  /// בונה את התצוגה המקדימה של הספרייה (CombinedView במצב preview) בעברית,
  /// ומחזיר את ה-tab כדי שאפשר לבדוק את מיקום הגלילה שנשמר בו.
  Future<TextBookTab> pumpPreview(
    WidgetTester tester, {
    bool isPreviewMode = true,
    Size size = const Size(500, 800),
    // עוטף את התצוגה כמו בספרייה: חלונית צד בצד שמאל (RTL) הניתנת לשינוי רוחב.
    bool inSidePane = false,
    List<TextBookEvent>? eventLog,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final content = _variableHeightContent();
    final textBookBloc = _TestTextBookBloc(
      _loadedState(content),
      eventLog: eventLog,
    );
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
    addTearDown(textBookBloc.close);
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(tab.dispose);

    final preview = CombinedView(
      data: content,
      openBookCallback: (_) {},
      openLeftPaneTab: (_, {searchText}) {},
      textSize: 18,
      showCommentaryAsExpansionTiles: false,
      tab: tab,
      isPreviewMode: isPreviewMode,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('he', 'IL')],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: inSidePane
                ? AdaptiveSidePane(
                    isOpen: true,
                    alignment: AlignmentDirectional.centerStart,
                    isResizable: true,
                    onPaneWidthChanged: (_) {},
                    onClose: () {},
                    mainContent: const SizedBox.expand(),
                    paneContent: preview,
                  )
                : preview,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return tab;
  }

  Future<TextBookTab> pumpPreviewInSidePane(WidgetTester tester) =>
      pumpPreview(tester, inSidePane: true);

  Finder thumbFinder() => find.descendant(
    of: find.byType(ScrollablePositionedListScrollbar),
    matching: find.byKey(ScrollablePositionedListScrollbar.thumbKey),
  );

  Finder trackFinder() => find.descendant(
    of: find.byType(ScrollablePositionedListScrollbar),
    matching: find.byKey(ScrollablePositionedListScrollbar.trackKey),
  );

  /// גולל את התצוגה בגלגלת ומחזיר את מיקומי האגודל שנמדדו בכל פריים.
  Future<List<double>> scrollAndSampleThumbTop(
    WidgetTester tester, {
    int frames = 200,
    double delta = 20,
  }) async {
    final samples = <double>[];
    final center = tester.getCenter(find.byType(ScrollablePositionedList));
    for (var i = 0; i < frames; i++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: Offset(0, delta)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(tester.getRect(thumbFinder()).top);
    }
    return samples;
  }

  group('בחירת שורה בתצוגה מקדימה (#4509)', () {
    testWidgets('לחיצה רגילה או Ctrl+לחיצה אינן מוסיפות בחירת שורה', (
      tester,
    ) async {
      final events = <TextBookEvent>[];
      await pumpPreview(tester, eventLog: events);
      final paragraph = find.byType(EnhancedGestureDetector).first;
      expect(paragraph, findsOneWidget);

      await tester.tap(paragraph, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 350));
      expect(events.whereType<UpdateSelectedIndex>(), isEmpty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(paragraph, kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 350));
      expect(events.whereType<UpdateSelectedIndex>(), isEmpty);
    });

    testWidgets('בקורא רגיל לחיצה עדיין בוחרת שורה', (tester) async {
      final events = <TextBookEvent>[];
      await pumpPreview(
        tester,
        isPreviewMode: false,
        eventLog: events,
      );
      final paragraph = find.byType(EnhancedGestureDetector).first;
      await tester.tap(paragraph, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 350));
      expect(events.whereType<UpdateSelectedIndex>(), isNotEmpty);
    });
  });

  group('מחוון הגלילה בתצוגה המקדימה', () {
    testWidgets('משתמש במחוון של האפליקציה ולא ב-Scrollbar של ListView', (
      tester,
    ) async {
      await pumpPreview(tester);

      expect(find.byType(ScrollablePositionedListScrollbar), findsOneWidget);
      expect(find.byType(ScrollablePositionedList), findsOneWidget);
      // Scrollbar של Flutter נשען על אומדן ההיקף של ListView, ואומדן זה משתנה
      // בכל פריים כששורות הספר בגבהים שונים — שם נולד "ריקוד" האגודל.
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('המסילה בקצה ימין של אזור התצוגה (כיוון הקריאה בעברית)', (
      tester,
    ) async {
      await pumpPreview(tester);

      final scrollbarRect = tester.getRect(
        find.byType(ScrollablePositionedListScrollbar),
      );
      final trackRect = tester.getRect(trackFinder());

      expect(
        trackRect.center.dx,
        greaterThan(scrollbarRect.center.dx),
        reason: 'המסילה בצד שמאל — הפוך משאר מחווני הגלילה באפליקציה',
      );
      expect(
        trackRect.right,
        closeTo(scrollbarRect.right, 0.5),
        reason: 'המסילה אינה צמודה לקצה ימין',
      );
      expect(
        tester.getRect(thumbFinder()).center.dx,
        greaterThan(scrollbarRect.center.dx),
        reason: 'האגודל אינו בתוך המסילה הימנית',
      );
    });

    testWidgets('המסילה אינה מכסה את הטקסט אלא יושבת ברצועה משלה', (
      tester,
    ) async {
      await pumpPreview(tester);

      final trackRect = tester.getRect(trackFinder());
      final listRect = tester.getRect(find.byType(ScrollablePositionedList));

      expect(
        listRect.right,
        lessThanOrEqualTo(trackRect.left + 0.5),
        reason: 'התוכן נכנס אל מתחת למסילה',
      );
    });

    testWidgets('האגודל נוסע ישר בגלילה למטה ואינו רוקד כלפי מעלה', (
      tester,
    ) async {
      // רגרסיה: ListView אומד את היקף הגלילה מגובה הפריטים הבנויים כרגע.
      // בשורות בגבהים שונים האומדן משתנה בכל פריים, והאגודל קפץ אחורה עד
      // 17px בזמן גלילה קדימה — "ריקוד" במקום נסיעה ישרה. המחוון האינדקסי
      // אינו אומד היקף בכלל, ונשאר בתוך פיקסל בודד.
      await pumpPreview(tester);

      final samples = await scrollAndSampleThumbTop(tester);

      var worstBackwardJump = 0.0;
      for (var i = 1; i < samples.length; i++) {
        final backward = samples[i - 1] - samples[i];
        if (backward > worstBackwardJump) worstBackwardJump = backward;
      }

      expect(
        worstBackwardJump,
        lessThan(1.5),
        reason:
            'האגודל נסוג ב-${worstBackwardJump.toStringAsFixed(1)}px בזמן '
            'גלילה למטה',
      );
      expect(
        samples.last,
        greaterThan(samples.first),
        reason: 'האגודל כלל לא זז — הטסט אינו בודק כלום',
      );
    });

    testWidgets('גובה האגודל יציב לאורך הגלילה', (tester) async {
      await pumpPreview(tester);

      final initialHeight = tester.getRect(thumbFinder()).height;
      var worstChange = 0.0;
      final center = tester.getCenter(find.byType(ScrollablePositionedList));
      for (var i = 0; i < 120; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            scrollDelta: const Offset(0, 20),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        final change = (tester.getRect(thumbFinder()).height - initialHeight)
            .abs();
        if (change > worstChange) worstChange = change;
      }

      expect(
        worstChange,
        lessThan(initialHeight * 0.35),
        reason: 'גובה האגודל משתנה בזמן גלילה ומשווה לו תנועת "נשימה"',
      );
    });

    testWidgets('האגודל מתקדם לפי הגלילה — לא נשאר במקום ולא מקדים לסוף', (
      tester,
    ) async {
      await pumpPreview(tester);

      final trackRect = tester.getRect(trackFinder());
      final samples = await scrollAndSampleThumbTop(tester, frames: 40);

      // 40 פריימים × 20px = 800px מתוך תוכן של עשרות מסכים — האגודל אמור
      // להתקדם מעט בלבד, ובוודאי לא לקרוס לתחתית.
      expect(samples.last, greaterThan(trackRect.top));
      expect(
        samples.last,
        lessThan(trackRect.top + trackRect.height * 0.5),
        reason: 'האגודל זינק לאמצע המסילה אחרי גלילה קצרה',
      );
    });

    testWidgets('גלילה בתצוגה המקדימה מעדכנת את מיקום הטאב לפתיחה בעיון', (
      tester,
    ) async {
      // לחיצה כפולה על התצוגה המקדימה פותחת את הספר במיקום הנוכחי, והמיקום
      // הזה נקרא מ-tab.index. הוא מתעדכן רק מ-itemPositions של הרשימה.
      final tab = await pumpPreview(tester);
      expect(tab.index, 0);

      await scrollAndSampleThumbTop(tester, frames: 60);

      expect(
        tab.index,
        greaterThan(0),
        reason: 'מיקום הגלילה בתצוגה המקדימה לא נשמר בטאב',
      );
    });

    testWidgets('אין חריגות בזמן החלפת ספר (dispose של הרשימה)', (
      tester,
    ) async {
      await pumpPreview(tester);
      await scrollAndSampleThumbTop(tester, frames: 20);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));

      expect(tester.takeException(), isNull);
    });

    testWidgets('האגודל אינו נחבא מתחת לידית שינוי רוחב החלונית', (
      tester,
    ) async {
      // חלונית התצוגה המקדימה היא AdaptiveSidePane בצד שמאל (RTL) הניתן
      // לשינוי רוחב, וידית הגרירה יושבת בדופן הימנית — בדיוק מקום המסילה.
      await pumpPreviewInSidePane(tester);

      final thumbRect = tester.getRect(thumbFinder());
      final handleRect = tester.getRect(find.byType(ResizableDragHandle));

      expect(
        handleRect.contains(thumbRect.center),
        isFalse,
        reason:
            'שטח המגע של הידית ($handleRect) בולע את מרכז האגודל ($thumbRect) '
            '— גרירה תשנה את רוחב החלונית במקום לגלול',
      );
    });

    for (final isPreviewMode in [true, false]) {
      testWidgets(
        'גלילה בשתי אצבעות כשהסמן על המסילה אינה מקפיצה את הספר '
        '(issue #2680, preview=$isPreviewMode)',
        (tester) async {
          final tab = await pumpPreview(tester, isPreviewMode: isPreviewMode);
          final position = tab.lines.itemController.scrollController!.position;
          final at = tester.getRect(trackFinder()).center;
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.trackpad,
          );
          await gesture.panZoomStart(at);
          for (var i = 1; i <= 3; i++) {
            await gesture.panZoomUpdate(at, pan: Offset(0, -10.0 * i));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.panZoomEnd();
          await tester.pumpAndSettle();

          expect(
            position.pixels,
            lessThanOrEqualTo(30),
            reason: 'תנועה של 30px בלוח המגע קפצה למקום הסמן על המסילה',
          );
        },
      );
    }

    testWidgets('אזור הקריאה הרגיל ממשיך להשתמש באותו מחוון', (tester) async {
      await pumpPreview(tester, isPreviewMode: false);

      expect(find.byType(ScrollablePositionedListScrollbar), findsWidgets);
      expect(find.byType(Scrollbar), findsNothing);
    });
  });
}
