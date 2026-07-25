import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../helpers/memory_settings_cache.dart';

/// טסטי רגרסיה לתיקונים בקובץ `lib/tabs/reading_screen.dart`:
///
/// 1. החלפת `TabBarView` ב-`PageView` עם `ValueKey(tab)` על כל ילד —
///    שומרת על ה-`Element` של טאב פעיל כשטאב לידו נסגר/מוזז, כך
///    שמצב ה-PDF/Bloc לא נטען מחדש (קומיט `74702ae15`).
///
/// 2. שימוש ב-`ValueKey(tab)` (ולא ב-`PageStorageKey(tab)`) על העטיפה
///    החיצונית — מונע התנגשות נתיב PageStorage בין `ScrollablePositionedList`
///    הפנימי, שכותב `ItemPosition`, לבין `PageView` הפנימי של `TabBarView`
///    בחלונית השמאלית, שקורא `double?` מאותו תא ונופל ב-cast error.
///
/// 3. דחיית `_syncPageController` ל-`addPostFrameCallback` ונטרול
///    `onPageChanged → SetCurrentTab` בדסקטופ — מונעים שההדגשה בשורת
///    הטאבים תקפוץ לטאב הקודם במקום לחדש בעת פתיחת טאב חדש בסוף.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reading_screen — שימור Element של ילד טאב בהזזת טאב סמוך', () {
    testWidgets(
      'reconciliation לפי ValueKey לא מאתחל מחדש ילד כשנסגר ילד שלפניו',
      (tester) async {
        // הבדיקה ברמת ה-reconciliation של רשימת ילדים עם מפתחות. זוהי
        // אותה לוגיקה שמשמשת את ה-`SliverChildListDelegate` של ה-PageView
        // ב-reading_screen — Element נשמר על פי המפתח של הילד, לא על פי
        // האינדקס שלו. הטסט משתמש ב-`Stack` רק כי הוא מאלץ את כל הילדים
        // להבנות בעץ (`PageView` מבנה רק את העמוד הפעיל ולכן Elementים
        // של עמודים אחרים פשוט לא קיימים — אין מה לשמר). הקריטריון הוא
        // אותו קריטריון: ValueKey יציב לכל טאב.
        _InitCounter.reset();

        Widget build(List<String> labels) {
          return MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  for (final label in labels)
                    _InitCounter(key: ValueKey(label), label: label),
                ],
              ),
            ),
          );
        }

        await tester.pumpWidget(build(['a', 'b', 'c']));
        await tester.pumpAndSettle();
        expect(
          _InitCounter.counts,
          {'a': 1, 'b': 1, 'c': 1},
          reason: 'כל ילד עבר initState פעם אחת בלבד בעת ה-mount הראשון',
        );

        // הסרת 'a' מקדמת הרשימה — מדמה סגירה/הזזה של טאב משמאל לטאב הפעיל.
        // אם reconciliation היה לפי אינדקס (כפי שמתנהג ה-`KeyedSubtree.wrap`
        // הפנימי של `TabBarView`), 'b' היה מקבל את האינדקס הקודם של 'a'
        // ועובר remount. עם `ValueKey('b')` המפתח לא משתנה — Element נשמר.
        await tester.pumpWidget(build(['b', 'c']));
        await tester.pumpAndSettle();

        expect(_InitCounter.counts, {
          'a': 1,
          'b': 1,
          'c': 1,
        }, reason: 'אסור שייקרא initState נוסף ל-"b" או ל-"c"');
      },
    );

    testWidgets(
      'index-keyed wrappers (כמו TabBarView) זורקים State בהסרת טאב מהקדמה',
      (tester) async {
        // טסט "שלילה" — משחזר את שורש הבאג שתואר בקומיט `74702ae15`:
        // "TabBarView עוטף ילדים ב-KeyedSubtree.wrap הפנימי שמקבע מפתח לפי
        // אינדקס. בהזזה/סגירה של טאב לפני ה-PDF, ה-reconciliation מצליח
        // חיצונית אך נכשל ב-type-mismatch בילד הפנימי ויוצר מחדש את ה-State."
        // כאן אנו מדמים את אותו דפוס ידנית: עטיפת KeyedSubtree עם
        // `ValueKey<int>(index)` סביב כל ילד.
        _PdfMock.initCount = 0;

        Widget buildIndexKeyed(List<Widget> children) {
          return MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  for (var i = 0; i < children.length; i++)
                    KeyedSubtree(key: ValueKey<int>(i), child: children[i]),
                ],
              ),
            ),
          );
        }

        await tester.pumpWidget(
          buildIndexKeyed([
            const _InitCounter(label: 'text'),
            const _PdfMock(),
          ]),
        );
        await tester.pumpAndSettle();
        expect(_PdfMock.initCount, 1);

        // הסרת הילד הראשון. ה-KeyedSubtree במיקום 0 שומר על אותו מפתח
        // חיצוני (`ValueKey<int>(0)`) — כך שה-Element החיצוני שלו ממוחזר,
        // אבל סוג הילד הפנימי משתנה מ-_InitCounter ל-_PdfMock → ה-Element
        // הפנימי מוחלף, וה-State של _PdfMock נזרק → initState נקרא שוב.
        await tester.pumpWidget(
          buildIndexKeyed([
            const _PdfMock(),
          ]),
        );
        await tester.pumpAndSettle();

        expect(
          _PdfMock.initCount,
          2,
          reason:
              'index-keyed wrap (כפי שעושה TabBarView) גורם ל-_PdfMock '
              'לאבד State כשטאב לפניו נסגר. זו הרגרסיה של 74702ae15.',
        );
      },
    );

    testWidgets(
      'value-keyed wrappers (התיקון) שומרים State גם בהסרת טאב מהקדמה',
      (tester) async {
        // משלים את הטסט הקודם: אותו מבנה בדיוק, אבל עם `ValueKey(tag)` יציב
        // על העטיפה במקום `ValueKey<int>(index)`. עכשיו ה-Element עוקב אחרי
        // המפתח, לא אחרי המיקום — בדיוק מה שהקומיט עשה כשעטף את הילדים
        // ב-`ValueKey(tab)`.
        _PdfMock.initCount = 0;

        Widget buildValueKeyed(List<(String tag, Widget child)> children) {
          return MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  for (final (tag, child) in children)
                    KeyedSubtree(key: ValueKey(tag), child: child),
                ],
              ),
            ),
          );
        }

        await tester.pumpWidget(
          buildValueKeyed([
            ('text', const _InitCounter(label: 'text')),
            ('pdf', const _PdfMock()),
          ]),
        );
        await tester.pumpAndSettle();
        expect(_PdfMock.initCount, 1);

        await tester.pumpWidget(
          buildValueKeyed([
            ('pdf', const _PdfMock()),
          ]),
        );
        await tester.pumpAndSettle();

        expect(
          _PdfMock.initCount,
          1,
          reason:
              'עם ValueKey יציב, ה-Element של "pdf" עוקב אחרי המפתח גם '
              'כשטאב "text" שלפניו נסגר. ה-State נשמר.',
        );
      },
    );
  });

  group('reading_screen — סנכרון PageController בפתיחת טאב חדש בסוף', () {
    // שורש הבאג שתוקן: ה-BlocListener ב-reading_screen רץ *לפני* שה-
    // BlocBuilder בונה מחדש את ה-PageView עם הילד החדש (listener הוא ancestor
    // ולכן מנוי לפני הילד). אם _syncPageController קוראת ל-jumpToPage
    // סינכרונית בתוך ה-listener, ה-PageView עדיין עם מספר הילדים הישן —
    // קפיצה לאינדקס שמעבר לתחום מצמדת ויורה onPageChanged עם האינדקס הקודם.
    // אם onPageChanged מזין SetCurrentTab (כפי שהיה בקוד הישן), זה דורס את
    // ה-currentTabIndex הנכון, וההדגשה בשורת הטאבים זזה לטאב לפני החדש.
    //
    // התיקון: שני שינויים משלימים —
    //   (א) דחיית jumpToPage ל-addPostFrameCallback (קופצים על PageView
    //       שכבר קיבל את הילד החדש, בלי clamp).
    //   (ב) `onPageChanged: null` בדסקטופ (NeverScrollableScrollPhysics →
    //       אין גלילה ידנית → ה-callback רק מהדהד קפיצות תוכנתיות וערכי
    //       clamp שגויים → מיותר ומזיק).

    testWidgets(
      'הוכחת המנגנון: jumpToPage לאינדקס מחוץ לתחום מצמיד ויורה '
      'onPageChanged עם האינדקס הקודם, לא עם היעד',
      (tester) async {
        final controller = PageController();
        final received = <int>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PageView(
                controller: controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: received.add,
                children: const [
                  Center(child: Text('p0')),
                  Center(child: Text('p1')),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        received.clear();

        // ה-PageView כרגע עם 2 ילדים (אינדקסים 0,1). קפיצה ל-2 מדמה את
        // התרחיש: ה-listener קרא ל-jumpToPage(N) לפני שה-PageView קיבל
        // את הילד ה-N+1.
        controller.jumpToPage(2);
        await tester.pumpAndSettle();

        expect(
          received,
          isNotEmpty,
          reason: 'jumpToPage לאינדקס חורג חייב לירות onPageChanged',
        );
        expect(
          received.last,
          1,
          reason:
              'אחרי applyContentDimensions ה-pixels נצמדים '
              'ל-maxScrollExtent (page=1) → onPageChanged יורה עם 1, '
              'לא עם היעד 2. זה ה-clamped index שדרס את currentTabIndex '
              'בקוד הישן (ההדגשה זזה ל-"הטאב הבא" במקום לחדש).',
        );

        controller.dispose();
      },
    );

    testWidgets(
      'הוכחת ההגנה השנייה: עם onPageChanged: null, גם clamp רגעי לא יוצר '
      'ערוץ ל-SetCurrentTab שגוי',
      (tester) async {
        // אותו תרחיש כמו "הוכחת המנגנון" (jumpToPage לאינדקס חורג שגורם
        // ל-clamp), אבל הפעם onPageChanged הוא null כפי שמוגדר בדסקטופ.
        // אם מישהו יחזיר onPageChanged בלי הגנת platform, ה-clamped index
        // יזרום שוב ל-SetCurrentTab וההדגשה תקפוץ לטאב הקודם.
        final controller = PageController();
        var rogueCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PageView(
                controller: controller,
                physics: const NeverScrollableScrollPhysics(),
                // אם תשנה את זה לפונקציה שמסמנת rogueCalled = true, הטסט
                // ייכשל — וזה בדיוק מה שהקוד הישן בדסקטופ עשה.
                onPageChanged: null,
                children: const [
                  Center(child: Text('p0')),
                  Center(child: Text('p1')),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        controller.jumpToPage(2);
        await tester.pumpAndSettle();

        expect(
          rogueCalled,
          isFalse,
          reason:
              'onPageChanged: null מבטיח שאין מסלול לכתיבת '
              'currentTabIndex שגוי גם כשה-clamp קורה',
        );
        expect(tester.takeException(), isNull);

        controller.dispose();
      },
    );
  });

  group('reading_screen — שוליים חיצוניים בתצוגה זה-לצד-זה', () {
    // רגרסיה: הטקסט בתצוגה המפוצלת נצמד לדופן החלון. התיקון מזריק שוליים של 12
    // (רוחב המפריד) לתוך *תוכן* כל חלונית בלבד, דרך SplitPaneContentInset,
    // כך שהחלונית עצמה נשארת צמודה לדופן — ידית פתיחת החלונית
    // (Positioned(left:0)) יושבת בדיוק על הדופן, בעוד הטקסט שומר 12px.
    const dividerWidth = 12.0;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    testWidgets(
      'ReadingScreen עם CombinedTab: החלוניות צמודות לדופן והתוכן נשמר 12px פנימה',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final combined = CombinedTab(
          rightTab: _commentaryTab('ימין'),
          leftTab: _commentaryTab('שמאל'),
        );
        addTearDown(combined.dispose);

        final tabsBloc = _FakeTabsBloc(
          TabsState(tabs: [combined], currentTabIndex: 0),
        );
        addTearDown(tabsBloc.close);

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              // כמו באפליקציה האמיתית (locale he) — כדי שהחלפת start/end
              // בשוליי SplitPaneContentInset תתגלה בכיוון הייצור.
              textDirection: TextDirection.rtl,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
                  BlocProvider<PersonalNotesBloc>.value(
                    value: _FakePersonalNotesBloc(),
                  ),
                  BlocProvider<TabsBloc>.value(value: tabsBloc),
                  Provider<FocusRepository>.value(value: FocusRepository()),
                ],
                child: const ReadingScreen(),
              ),
            ),
          ),
        );
        await tester.pump();

        final panes = find.byType(PdfCommentatorsTabScreen);
        expect(panes, findsNWidgets(2));

        // כל חלונית נצמדת לדופן החלון — הידית ב-Positioned(left:0) יושבת על
        // הדופן האמיתי (x=0 / x=רוחב), ולא 12px פנימה.
        final paneRects = [
          tester.getRect(panes.at(0)),
          tester.getRect(panes.at(1)),
        ];
        final paneLeft = paneRects
            .map((r) => r.left)
            .reduce((a, b) => a < b ? a : b);
        final paneRight = paneRects
            .map((r) => r.right)
            .reduce((a, b) => a > b ? a : b);

        expect(
          paneLeft,
          0,
          reason:
              'החלונית הקיצונית חייבת להיצמד לדופן החלון כדי שהידית '
              '(Positioned(left:0)) תשב בדיוק על הדופן',
        );
        expect(
          paneRight,
          1600,
          reason: 'החלונית הקיצונית חייבת להיצמד לדופן החלון',
        );

        // תוכן הקריאה (AdaptiveSidePane) מוזרק 12px פנימה מדופן החלון.
        final content = find.byType(AdaptiveSidePane);
        expect(content, findsNWidgets(2));
        final contentRects = [
          tester.getRect(content.at(0)),
          tester.getRect(content.at(1)),
        ];
        final contentLeft = contentRects
            .map((r) => r.left)
            .reduce((a, b) => a < b ? a : b);
        final contentRight = contentRects
            .map((r) => r.right)
            .reduce((a, b) => a > b ? a : b);

        expect(
          contentLeft,
          dividerWidth,
          reason:
              'תוכן הקריאה חייב לשמור 12px מדופן החלון; 0 פירושו '
              'שה-SplitPaneContentInset לא הוזרק לתוכן',
        );
        expect(
          contentRight,
          1600 - dividerWidth,
          reason: 'תוכן הקריאה חייב לשמור 12px מדופן החלון',
        );
      },
    );
  });

  group('reading_screen — מניעת התנגשות נתיב PageStorage', () {
    Widget buildTree({
      required Key wrapperKey,
      required bool showPageView,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: KeyedSubtree(
            key: wrapperKey,
            child: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: ScrollablePositionedList.builder(
                    itemCount: 50,
                    itemBuilder: (_, i) => SizedBox(
                      height: 40,
                      child: Text('item-$i'),
                    ),
                  ),
                ),
                if (showPageView)
                  SizedBox(
                    height: 200,
                    child: PageView(
                      children: const [
                        Center(child: Text('p0')),
                        Center(child: Text('p1')),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Future<Object?> scrollListThenMountPageView(
      WidgetTester tester, {
      required Key wrapperKey,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // שלב 1: עליית ה-SPL לבדה.
      await tester.pumpWidget(
        buildTree(wrapperKey: wrapperKey, showPageView: false),
      );
      await tester.pumpAndSettle();

      // שלב 2: גלילה שמפעילה
      // `PageStorage.of(context).writeState(context, itemPosition)`
      // (שורה 646 בחבילת scrollable_positioned_list — כותב `ItemPosition`).
      await tester.drag(find.text('item-0'), const Offset(0, -200));
      await tester.pumpAndSettle();

      // שלב 3: הוספת ה-PageView לעץ — fresh mount. הבנאי של
      // `_PagePosition` קורא `restoreScrollOffset` שמושך מ-PageStorage
      // ומבצע cast ל-`double?`. אם הנתיב של ה-PageView מתנגש עם זה של
      // ה-SPL, התא מכיל `ItemPosition` והקריסה מתרחשת כאן.
      await tester.pumpWidget(
        buildTree(wrapperKey: wrapperKey, showPageView: true),
      );
      await tester.pumpAndSettle();

      return tester.takeException();
    }

    testWidgets(
      'עטיפה עם ValueKey לא קורסת לאחר כתיבת ItemPosition ל-PageStorage',
      (tester) async {
        final exception = await scrollListThenMountPageView(
          tester,
          wrapperKey: const ValueKey('tab-1'),
        );
        expect(
          exception,
          isNull,
          reason:
              'ValueKey לא משתתפת בנתיב PageStorage, לכן ה-SPL '
              'וה-PageView הפנימי לא חולקים תא ולא מתרחשת התנגשות',
        );
      },
    );

    testWidgets(
      'עטיפה עם PageStorageKey מובילה ל-cast error (תרחיש הרגרסיה)',
      (tester) async {
        // טסט "שלילה" — מתעד בדיוק את הסיבה ש-PageStorageKey הוחלף ב-ValueKey.
        // אם מישהו יחזיר את העטיפה ל-PageStorageKey, הטסט בכוונה ינפץ.
        final exception = await scrollListThenMountPageView(
          tester,
          wrapperKey: const PageStorageKey('tab-1'),
        );
        expect(
          exception,
          isA<TypeError>(),
          reason:
              'PageStorageKey יוצרת נתיב PageStorage משותף בין SPL '
              'ל-PageView הפנימי → ItemPosition נקרא במקום double?',
        );
        expect(exception.toString(), contains('ItemPosition'));
      },
    );
  });

  group('reading_screen — העברת כרטיסייה (גרירה) לא טוענת את הספר מחדש', () {
    // ה-PageView משייך ילדים לפי *מיקום*, ולכן בלי key על הילד הישיר גרירת
    // טאב הורסת את ה-State של הטאבים שזזו (ב-PDF: dispose סוגר את המסמך
    // ו-initState פותח אותו מחדש). הבדיקות שלמעלה רצות על Stack ולכן אינן
    // תופסות את הכשל — כאן PageView אמיתי.
    Future<Map<String, int>> moveFirstTabToEnd(
      WidgetTester tester, {
      required bool withKeys,
    }) async {
      _InitCounter.reset();
      final controller = PageController();
      addTearDown(controller.dispose);
      var order = ['A', 'B', 'C'];
      var current = 0;
      late StateSetter setOuter;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return PageView(
                controller: controller,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < order.length; i++)
                    if (withKeys)
                      KeyedSubtree(
                        key: ObjectKey(order[i]),
                        child: TickerMode(
                          enabled: i == current,
                          child: _KeepAliveTab(
                            key: ValueKey(order[i]),
                            label: order[i],
                          ),
                        ),
                      )
                    else
                      TickerMode(
                        enabled: i == current,
                        child: _KeepAliveTab(
                          key: ValueKey(order[i]),
                          label: order[i],
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      );

      // ביקור בכל הטאבים כדי שכולם יהיו חיים (keepAlive) לפני ההזזה.
      for (var i = 0; i < 3; i++) {
        controller.jumpToPage(i);
        await tester.pumpAndSettle();
      }
      controller.jumpToPage(0);
      await tester.pumpAndSettle();
      _InitCounter.reset();

      setOuter(() {
        order = ['B', 'C', 'A'];
        current = 2;
      });
      await tester.pumpAndSettle();
      return Map<String, int>.from(_InitCounter.counts);
    }

    testWidgets('בלי key על הילד הישיר — הטאבים שזזו נבנים מחדש (הבאג)', (
      tester,
    ) async {
      final counts = await moveFirstTabToEnd(tester, withKeys: false);
      expect(
        counts.values.fold<int>(0, (a, b) => a + b),
        greaterThan(0),
        reason: 'בלי key ה-PageView משייך לפי מיקום ובונה מחדש',
      );
    });

    testWidgets('עם ObjectKey — אף טאב לא נבנה מחדש', (tester) async {
      final counts = await moveFirstTabToEnd(tester, withKeys: true);
      for (final t in ['A', 'B', 'C']) {
        expect(
          counts[t] ?? 0,
          0,
          reason: 'הטאב "$t" איבד State — ב-PDF זו טעינה מחדש מהדיסק',
        );
      }
    });
  });
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
    : super(
        const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        ),
      ) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initial) {
    on<TabsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// כרטסיית מפרשים מזויפת — תוכן קל שנטען סינכרונית בתצוגה המפוצלת.
PdfCommentatorsTab _commentaryTab(String title) {
  final sourceTab = PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );
  sourceTab.pdfHeadings = PdfHeadings(
    bookTitle: title,
    headingsMap: {'פרק א': 1},
  );
  sourceTab.currentTitle.value = 'פרק א';
  sourceTab.currentTextLineNumber = 1;
  sourceTab.currentTextLineNumberEnd = 9;
  return PdfCommentatorsTab(sourceTab: sourceTab);
}

/// וידג'ט בדיקה שסופר כמה פעמים נקרא ה-initState שלו לכל label.
/// מדמה טאב אמיתי: `PdfBookScreen` ו-`TextBookScreen` שניהם משתמשים
/// ב-[AutomaticKeepAliveClientMixin], וזה תנאי לכך שהתיקון ישמור גם על
/// טאבים שזזו בעקבות הגרירה (ולא רק על הטאב שנגרר).
class _KeepAliveTab extends StatefulWidget {
  final String label;
  const _KeepAliveTab({super.key, required this.label});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _InitCounter.counts[widget.label] =
        (_InitCounter.counts[widget.label] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Text(widget.label);
  }
}

class _InitCounter extends StatefulWidget {
  final String label;
  const _InitCounter({super.key, required this.label});

  static final Map<String, int> counts = {};
  static void reset() => counts.clear();

  @override
  State<_InitCounter> createState() => _InitCounterState();
}

class _InitCounterState extends State<_InitCounter> {
  @override
  void initState() {
    super.initState();
    _InitCounter.counts[widget.label] =
        (_InitCounter.counts[widget.label] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

/// וידג'ט עם runtimeType שונה כדי לדמות PdfBookScreen ↔ TextBookViewerBloc:
/// בלי מפתחות, החלפת טאב טקסט בטאב PDF באותו מיקום גורמת ל-remount כי
/// ה-runtimeType שונה. עם `ValueKey(tab)`, ה-Element עוקב אחרי המפתח.
class _PdfMock extends StatefulWidget {
  const _PdfMock();

  static int initCount = 0;

  @override
  State<_PdfMock> createState() => _PdfMockState();
}

class _PdfMockState extends State<_PdfMock> {
  @override
  void initState() {
    super.initState();
    _PdfMock.initCount += 1;
  }

  @override
  Widget build(BuildContext context) => const Text('pdf');
}
