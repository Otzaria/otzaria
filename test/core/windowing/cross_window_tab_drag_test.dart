// ⚠️ רצה בכל פלטפורמה, ובמכוון.
//
// כל מסלול הגרירה מגודר ב-`MultiWindowService.canOpenWindows`, שהוא
// `Platform.isWindows`, ולכן הקובץ היה מסומן `@TestOn('windows')` — וה-CI
// רץ על ubuntu. כלומר כל הבדיקות כאן היו ירוקות על מכונת המפתח בלבד.
// ההיגיון שנבדק אינו תלוי פלטפורמה: מה שמעבר לערוץ מדומה ב-[_FakeRunner],
// ו-`debugSupportedOverride` פותח את השער.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/cross_window_tab_drag.dart';
import 'package:otzaria/core/windowing/drag_preview_colors.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/tab_drag_preview.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.crosswindowdrag';

/// מסלול הגרירה בין חלונות נבדק עד כה **ידנית בלבד**, וזה הפער שהדוח סימן.
/// כאן נבדקת ההחלטה עצמה: מה קורה לכרטיסיה בכל אחת מארבע התוצאות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRunner runner;
  late _RecordingTabsBloc tabsBloc;
  late CrossWindowTabDrag drag;

  setUp(() {
    MultiWindowService.debugSupportedOverride = true;
    WindowBus.namespace = _namespace;
    runner = _FakeRunner()..install();
    tabsBloc = _RecordingTabsBloc(
      TabsState(
        tabs: [
          ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה'),
          ToolTab(toolId: 'builtin.gematria', title: 'גימטריה'),
        ],
        currentTabIndex: 0,
      ),
    );
    drag = CrossWindowTabDrag();
  });

  tearDown(() async {
    MultiWindowService.debugSupportedOverride = null;
    drag.dispose();
    runner.uninstall();
    await tabsBloc.close();
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    WindowBus.namespace = 'otzaria.window';
  });

  OpenedTab firstTab() => tabsBloc.state.tabs.first;

  /// תמונה אטומה קטנה — `_sendSnapshot` דוחה צילום שקוף.
  Future<ui.Image> opaqueImage() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(List<int>.filled(4 * 4 * 4, 0xFF)),
      4,
      4,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// מוסר לגרירה מוק חלון, כמו שהרצועה עושה כשהצילום מוכן.
  Future<void> applyMock(CrossWindowTabDrag drag) async {
    drag.applySnapshot(
      TabWindowPreview(
        image: await opaqueImage(),
        targetWidth: 1100,
        targetHeight: 760,
      ),
      1,
    );
    // השליחה אסינכרונית, ו-`_snapshotSent` נדלק רק בסופה.
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  test('שחרור מעל החלון עצמו אינו עושה דבר', () async {
    // ⚠️ שחרור בתוך החלון שלא פגע ביעד הפלה. בלי התנאי הזה כל גרירה
    // שהתפספסה הייתה פותחת חלון.
    runner.cursorTarget = (slot: 1, isSelf: true, isShellTray: false);

    await drag.handleDroppedOutside(firstTab(), tabsBloc);

    expect(tabsBloc.events, isEmpty);
    expect(runner.openWindowCalls, 0);
  });

  test('שחרור מעל שורת המשימות מבוטל ואינו פותח חלון', () async {
    // ⚠️ שורת המשימות נגישה גם בחלון ממוקסם, ולכן שחרור עליה הוא כמעט
    // תמיד החטאה. קודם לכן הוא פתח חלון שני והכרטיסיה עזבה — שינוי
    // בהתנהגות שמשתמש בחלון יחיד נתקל בו בטעות.
    runner.cursorTarget = (slot: null, isSelf: false, isShellTray: true);

    await drag.handleDroppedOutside(firstTab(), tabsBloc);

    expect(tabsBloc.events, isEmpty);
    expect(runner.openWindowCalls, 0);
  });

  test('שחרור מעל שולחן העבודה פותח חלון והכרטיסיה עוברת', () async {
    runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);

    await drag.handleDroppedOutside(firstTab(), tabsBloc);

    expect(runner.openWindowCalls, 1);
    expect(tabsBloc.events.whereType<RemoveTab>(), hasLength(1));
  });

  test('החלון נפתח בנקודת השחרור ולא בהיסט מהפינה', () async {
    // ⚠️ עד כה החלון נפתח בהיסט מדורג מהפינה, בלי קשר למקום שאליו גררו —
    // גררת לפינה התחתונה-ימנית והחלון קפץ למעלה-שמאלה. רשימת ה-QA של
    // הענף כן דרשה "חלון חדש במיקום הסמן".
    runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);

    await drag.handleDroppedOutside(firstTab(), tabsBloc);

    expect(runner.lastOpenArgs?['originX'], 100);
    expect(runner.lastOpenArgs?['originY'], 200);
  });

  group('הרוח שהוקפאה במקום השחרור', () {
    test('סיום גרירה מקפיא ואינו מסתיר', () async {
      // ⚠️ `onDragFinishedAnywhere` נורה **לפני** השחרור, ולכן בשלב הזה
      // עוד לא ידוע אם ייפתח חלון. הסתרה מיידית השאירה את המסך ריק בדיוק
      // בפרק הזמן שבו המשתמש מחכה לראות תוצאה.
      drag.end();
      await Future<void>.delayed(Duration.zero);

      expect(runner.freezeCalls, 1);
      expect(runner.endCalls, 0);
    });

    test('פתיחת חלון משאירה אותה — היא תוחלף בחלון האמיתי', () async {
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);

      await drag.handleDroppedOutside(firstTab(), tabsBloc);

      expect(runner.endCalls, 0);
    });

    test('שחרור לחלון קיים מסתיר מיד — אין מה להחליף', () async {
      final peer = _FakePeer(2, accept: true)..register();
      addTearDown(peer.dispose);
      runner.cursorTarget = (slot: 2, isSelf: false, isShellTray: false);

      await drag.handleDroppedOutside(firstTab(), tabsBloc);

      expect(runner.endCalls, 1);
    });

    test('כל מסלול שאינו פותח חלון מסתיר', () async {
      // ⚠️ ההפך היה משאיר רוח מרחפת על המסך אחרי גרירה שהתבטלה.
      runner.cursorTarget = (slot: 1, isSelf: true, isShellTray: false);
      await drag.handleDroppedOutside(firstTab(), tabsBloc);
      expect(runner.endCalls, 1);

      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: true);
      await drag.handleDroppedOutside(firstTab(), tabsBloc);
      expect(runner.endCalls, 2);
    });
  });

  test('כשל פתיחה משאיר את הכרטיסיה במקומה', () async {
    // ⚠️ זו כל הנקודה בכך ש-`openWindow` ממתין ליצירה בפועל: מחיקה על סמך
    // "הצלחה" שלא נבדקה הייתה מאבדת את הכרטיסיה.
    runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
    runner.openWindowResult = false;

    await drag.handleDroppedOutside(firstTab(), tabsBloc);

    expect(tabsBloc.events.whereType<RemoveTab>(), isEmpty);
  });

  test(
    'גם הכרטיסיה האחרונה יוצאת לחלון חדש — חלון המקור נשאר על הספרייה',
    () async {
      tabsBloc.emitState(TabsState(tabs: [firstTab()], currentTabIndex: 0));
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);

      await drag.handleDroppedOutside(firstTab(), tabsBloc);

      expect(runner.openWindowCalls, 1);
      expect(tabsBloc.events.whereType<RemoveTab>(), hasLength(1));
    },
  );

  test('שחרור מעל חלון אחר שולח אליו, והכרטיסיה מוסרת רק אחרי אישור', () async {
    final peer = _FakePeer(2, accept: true)..register();
    addTearDown(peer.dispose);
    runner.cursorTarget = (slot: 2, isSelf: false, isShellTray: false);

    await drag.handleDroppedOutside(firstTab(), tabsBloc);

    expect(peer.receivedTabs, 1);
    expect(runner.openWindowCalls, 0);
    expect(tabsBloc.events.whereType<RemoveTab>(), hasLength(1));
  });

  test('חלון יעד שלא אישר — הכרטיסיה נשארת ואינה נעלמת משני הצדדים', () async {
    final peer = _FakePeer(2, accept: false)..register();
    addTearDown(peer.dispose);
    runner.cursorTarget = (slot: 2, isSelf: false, isShellTray: false);

    await drag.handleDroppedOutside(firstTab(), tabsBloc);

    expect(peer.receivedTabs, 1);
    expect(tabsBloc.events.whereType<RemoveTab>(), isEmpty);
  });

  group('מסירת הגרירה ל-Windows (Snap Layouts)', () {
    // ⚠️ המתנה **אמיתית**, ולא `FakeAsync`. המסירה נתלית על טיימר תקופתי
    // שכל פעימה שלו היא קריאת ערוץ, והתשובה חוזרת דרך ה-messenger
    // האסינכרוני — כלומר זמן מדומה לא היה מקדם את המסלול שנבדק.
    const settle = Duration(milliseconds: 260);

    const colors = DragPreviewColors(
      tab: Color(0xFF202020),
      border: Color(0xFF404040),
      text: Color(0xFFF0F0F0),
    );

    /// מתחיל גרירה כמו שהרצועה עושה, ומחזיר האם הגרירה בוטלה.
    bool Function() startDrag(OpenedTab tab) {
      var cancelled = false;
      drag.begin(
        tab,
        colors,
        tabsBloc: tabsBloc,
        cancelDrag: () => cancelled = true,
      );
      return () => cancelled;
    }

    test('יציאה מחלון המקור מוסרת את הגרירה ומבטלת את זו של Flutter', () async {
      // ⚠️ בלי הביטול, לולאת ההזזה של Windows לוכדת את העכבר ו-Flutter
      // לא יראה את השחרור — ה-`Draggable` נתקע לנצח, עם הכרטיסיה
      // מעומעמת במקומה.
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);

      final cancelled = startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 1);
      expect(cancelled(), isTrue);
    });

    test('⚠️ אינה פותחת חלון בזמן הגרירה', () async {
      // זו נקודת התיקון מול הגרסה הקודמת, שפתחה מנוע Flutter מלא באמצע
      // הגרירה. מה שנמסר למערכת הוא חלון Win32 ריק שכבר קיים; החלון
      // האמיתי נפתח רק בשחרור.
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      final gate = Completer<void>();
      runner.systemDragGate = gate;

      startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 1, reason: 'הגרירה נמסרה');
      expect(
        runner.openWindowCalls,
        0,
        reason: 'החלון נפתח בשחרור, לא בתחילת הגרירה',
      );
      expect(tabsBloc.events, isEmpty, reason: 'הכרטיסיה עוד בחלון המקור');

      // המשתמש שחרר.
      gate.complete();
      await Future<void>.delayed(settle);

      expect(runner.openWindowCalls, 1);
      expect(tabsBloc.events.whereType<RemoveTab>(), hasLength(1));
    });

    test('שחרור מוצמד פותח את החלון **במסגרת** שההצמדה נתנה', () async {
      // ⚠️ בלי זה ההצמדה שהמשתמש ראה נעלמת ברגע שהחלון האמיתי מופיע.
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      runner.systemDragResult = (
        ran: true,
        snapped: true,
        left: 960,
        top: 0,
        width: 960,
        height: 1040,
      );

      startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(runner.openWindowCalls, 1);
      final bounds = runner.lastOpenArgs?['bounds'] as Map<Object?, Object?>?;
      expect(bounds?['left'], 960);
      expect(bounds?['width'], 960);
      expect(bounds?['height'], 1040);
      expect(
        runner.lastOpenArgs?['originX'],
        isNull,
        reason: 'מסגרת מדויקת דוחה את נקודת השחרור',
      );
      expect(tabsBloc.events.whereType<RemoveTab>(), hasLength(1));
    });

    test('שחרור בלי הצמדה: החלון נפתח בפינה שבה התצוגה נעצרה', () async {
      // ⚠️ שתי הצהרות בבדיקה אחת, ובמכוון — שתיהן היו באגים שהמשתמש ראה.
      //
      // 1. **לא** המסגרת: התצוגה היא בגודל כרטיסיה, ושימוש עיוור בה היה
      //    יוצר חלון אוצריא של 176×40.
      // 2. **לא** מיקום הסמן: ה-runner הזיז את החלון `-width + 100`
      //    מהנקודה שקיבל, ואחרי ההידוק לקצה המסך התוצאה הייתה קבועה —
      //    "גררתי ימינה והחלון נפתח בשמאל, טיפה מתחת למקור".
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      runner.systemDragResult = (
        ran: true,
        snapped: false,
        left: 500,
        top: 300,
        width: 176,
        height: 40,
      );

      startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(runner.lastOpenArgs?['bounds'], isNull);
      expect(
        runner.lastOpenArgs?['originX'],
        500,
        reason: 'הפינה של התצוגה, ולא הסמן (100)',
      );
      expect(runner.lastOpenArgs?['originY'], 300);
    });

    test('שחרור מעל חלון אוצריא אחר מעביר אליו ואינו פותח חלון', () async {
      // ⚠️ זה מה שהיה נשבר בגרסה שפתחה חלון תוך כדי הגרירה: הדרך לחלון
      // ב' עוברת מעל שולחן העבודה. עכשיו ההחלטה נופלת בשחרור, ולכן
      // המסלול הזה שרד בלי השהיות.
      final peer = _FakePeer(2, accept: true)..register();
      addTearDown(peer.dispose);
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      runner.systemDragTarget = (slot: 2, isSelf: false, isShellTray: false);

      startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(peer.receivedTabs, 1);
      expect(runner.openWindowCalls, 0);
      expect(tabsBloc.events.whereType<RemoveTab>(), hasLength(1));
    });

    test('⚠️ הצמדה פותחת חלון גם כשחלון המקור תחת הסמן', () async {
      // זה היה באג נראה לעין: המשתמש ראה את מסדר החלונות נפתח, בחר אזור,
      // **ושום חלון לא נפתח**. האזור המוצמד מכסה בדרך כלל את חלון המקור
      // עצמו, ולכן `isSelf` יצא true והקוד ביטל בשקט.
      //
      // הצמדה היא החלטה מפורשת של המשתמש "החלון יהיה כאן", ולכן מה
      // שנמצא תחת הסמן באותו רגע חסר משמעות.
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      runner.systemDragTarget = (slot: 1, isSelf: true, isShellTray: false);
      runner.systemDragResult = (
        ran: true,
        snapped: true,
        left: 0,
        top: 0,
        width: 960,
        height: 1040,
      );

      startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(runner.openWindowCalls, 1);
      expect(tabsBloc.events.whereType<RemoveTab>(), hasLength(1));
    });

    test('הצמדה גוברת גם על חלון אוצריא אחר שתחת הסמן', () async {
      // אותו היגיון: הצמדה אינה "העבר לחלון הזה" אלא "פתח חלון כאן".
      final peer = _FakePeer(2, accept: true)..register();
      addTearDown(peer.dispose);
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      runner.systemDragTarget = (slot: 2, isSelf: false, isShellTray: false);
      runner.systemDragResult = (
        ran: true,
        snapped: true,
        left: 960,
        top: 0,
        width: 960,
        height: 1040,
      );

      startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(peer.receivedTabs, 0);
      expect(runner.openWindowCalls, 1);
    });

    test('שחרור חזרה מעל חלון המקור מבוטל', () async {
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      runner.systemDragTarget = (slot: 1, isSelf: true, isShellTray: false);

      startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(runner.openWindowCalls, 0);
      expect(tabsBloc.events, isEmpty);
      expect(runner.endCalls, 1);
    });

    test('שחרור מעל שורת המשימות מבוטל', () async {
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      runner.systemDragTarget = (slot: null, isSelf: false, isShellTray: true);

      startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(runner.openWindowCalls, 0);
      expect(tabsBloc.events, isEmpty);
    });

    test('גם הכרטיסיה האחרונה יוצאת לחלון חדש', () async {
      tabsBloc.emitState(TabsState(tabs: [firstTab()], currentTabIndex: 0));
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);

      startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(runner.openWindowCalls, 1);
    });

    test('שחרור אחרי המסירה אינו מטפל בכרטיסיה פעמיים', () async {
      // ⚠️ הביטול ששלחנו ל-Flutter מגיע ל-`onDraggableCanceled`, ומשם
      // ל-`handleDroppedOutside`.
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      final tab = firstTab();

      startDrag(tab);
      await Future<void>.delayed(settle);
      drag.end();
      await drag.handleDroppedOutside(tab, tabsBloc);

      expect(runner.openWindowCalls, 1);
      expect(tabsBloc.events.whereType<RemoveTab>(), hasLength(1));
    });

    test('הסמן בתוך החלון אינו מוסר דבר', () async {
      runner.cursorTarget = (slot: 1, isSelf: true, isShellTray: false);

      startDrag(firstTab());
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 0);
    });

    test('בלי bloc אין מסירה — הגרירה נשארת כשהייתה', () async {
      // הרצועות מעבירות את שניהם; מי שלא, מקבל את ההתנהגות הקודמת ולא
      // מסירה חלקית שמאבדת כרטיסיה.
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);

      drag.begin(firstTab(), colors);
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 0);
      expect(tabsBloc.events, isEmpty);
    });

    test('תשובת מיקום מגרירה קודמת אינה מוסרת את הגרירה הבאה', () async {
      final gate = Completer<void>();
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      runner.cursorGate = gate;

      drag.begin(firstTab(), colors, tabsBloc: tabsBloc);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(runner.cursorQueries, greaterThan(0));

      drag.end();
      runner.cursorTarget = (slot: 1, isSelf: true, isShellTray: false);
      drag.begin(firstTab(), colors, tabsBloc: tabsBloc);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(runner.systemDragCalls, 0);
    });
  });

  group('צילום הכרטיסיה', () {
    const colors = DragPreviewColors(
      tab: Color(0xFF202020),
      border: Color(0xFF404040),
      text: Color(0xFFF0F0F0),
    );

    /// תמונה אטומה קטנה — `_hasVisiblePixels` דורש פיקסל שאינו שקוף.
    test('⚠️ נשלח מיד ולא נדחה ליציאה מהחלון', () async {
      // ⚠️ זו הגנה על שלושה באגים שדחיית השליחה יצרה בבת אחת:
      //
      // 1. `SetImage` שמגיע אחרי שהלולאה המודאלית התחילה מדלג על
      //    `Compose`, ולכן נגררה רק **כותרת** הכרטיסיה ולא המוק שלה.
      // 2. `PreviewSize` מחזיר את גודל היעד שנקבע ב-`SetImage`, ולכן
      //    ההשוואה בסוף הגרירה החזירה `snapped=true` כוזב.
      // 3. `snapped` גובר על היעד שתחת הסמן — כלומר שחרור מעל חלון
      //    אוצריא אחר פתח חלון **חדש** במקום להעביר אליו.
      runner.cursorTarget = (slot: 1, isSelf: true, isShellTray: false);
      drag.begin(firstTab(), colors, tabsBloc: tabsBloc);

      drag.applySnapshot(
        TabWindowPreview(
          image: await opaqueImage(),
          targetWidth: 1100,
          targetHeight: 760,
        ),
        1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runner.setImageCalls, 1, reason: 'הצילום נשלח בלי להמתין ליציאה');
      expect(runner.systemDragCalls, 0, reason: 'הסמן עוד בתוך החלון');
    });

    test('הצילום מקדים את המסירה למערכת', () async {
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
      final gate = Completer<void>();
      runner.systemDragGate = gate;

      drag.begin(firstTab(), colors, tabsBloc: tabsBloc, cancelDrag: () {});
      drag.applySnapshot(
        TabWindowPreview(
          image: await opaqueImage(),
          targetWidth: 1100,
          targetHeight: 760,
        ),
        1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 260));
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(runner.setImageCalls, 1);
      expect(
        runner.imageArrivedAfterHandOff,
        isFalse,
        reason:
            'צילום שמגיע אחרי `dragOutToSystem` אינו מורכב, ומזייף '
            'את חישוב ה-snapped',
      );
    });

    test('מוק מגרירה קודמת נדחה אחרי שגרירה חדשה התחילה', () async {
      drag.begin(firstTab(), colors, tabsBloc: tabsBloc);
      drag.end();
      drag.begin(firstTab(), colors, tabsBloc: tabsBloc);

      drag.applySnapshot(
        TabWindowPreview(
          image: await opaqueImage(),
          targetWidth: 1100,
          targetHeight: 760,
        ),
        1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(runner.setImageCalls, 0);
    });

    test('שליחת מוק ישן אינה מאשרת מסירה של גרירה חדשה', () async {
      final gate = Completer<void>();
      runner.cursorTarget = (slot: 1, isSelf: true, isShellTray: false);
      runner.cursorY = 200;
      runner.imageGate = gate;

      drag.begin(firstTab(), colors, tabsBloc: tabsBloc);
      drag.applySnapshot(
        TabWindowPreview(
          image: await opaqueImage(),
          targetWidth: 1100,
          targetHeight: 760,
        ),
        1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(runner.setImageCalls, 1);

      drag.end();
      drag.begin(firstTab(), colors, tabsBloc: tabsBloc);
      drag.notePointerLeftStrip();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      runner.cursorY = 0;
      runner.approachingTop = true;
      await Future<void>.delayed(const Duration(milliseconds: 160));

      expect(runner.systemDragCalls, 0);
    });
  });

  group('מסירה מוקדמת בדרך מעלה, בעוד הסמן בתוך החלון', () {
    // ⚠️ שני דברים שהלוג לימד, ושניהם נגד האינטואיציה הראשונה:
    //
    // 1. הסמן **כן** יוצא מחלון המקור בחלון שצמוד לראש המסך — הוא נקרא
    //    כמי שיצא בדיוק ב-`y == 0`, ולכן המסירה למערכת כן קורית.
    // 2. ובכל זאת מסדר החלונות לא נפתח: ה-shell פותח אותו כשהחלון הנגרר
    //    **נכנס** לאזור העליון בזמן לולאת ההזזה, ומסירה בפיקסל האחרון
    //    אינה משאירה שום נסיעה שתיראה כמו כניסה. יציאה בצד
    //    (`cursor=(890,134)`) כן קיבלה מסדר חלונות; `(582,0)` לא.
    //
    // ⚠️ ומה שמפריד את המסירה מסידור כרטיסיות הוא **יציאה מהרצועה**,
    // ולא גאומטריית המסך. גרסה ראשונה של התיקון גידרה לפי אזור
    // ההתקרבות ולפי נסיעה מעלה, בהנחה שהאזור נשאר מעל הרצועה — והנחה
    // זו שגויה: הרצועה **היא** הסרגל העליון (0..40 יחידות לוגיות),
    // והאזור (28) יושב בתוכה. סקירה מצאה את זה, והבדיקות כאן שחזרו:
    // סידור אופקי עם סחיפה מעלה נמסר למערכת והמחווה אבדה.

    /// די לכמה פעימות של 60ms, בזמן אמת.
    const settle = Duration(milliseconds: 200);

    const colors = DragPreviewColors(
      tab: Color(0xFF202020),
      border: Color(0xFF404040),
      text: Color(0xFFF0F0F0),
    );

    /// הסמן מעל חלון המקור עצמו — המצב שבו הבאג התקיים.
    void overSelf() {
      runner.cursorTarget = (slot: 1, isSelf: true, isShellTray: false);
    }

    /// מתחיל גרירה מגובה [fromY], ומחזיר האם היא בוטלה.
    ///
    /// ⚠️ הגובה נקבע **לפני** ההתחלה: נקודת המוצא נדגמת ב-`begin` עצמו,
    /// כי הפעימה הראשונה מגיעה 60ms מאוחר מדי — ראו `_captureDragOrigin`.
    ///
    /// [withMock] הוא ברירת המחדל כי זה המצב האמיתי: הרצועה מרכיבה את מוק
    /// החלון ושולחת אותו בתחילת כל גרירה. המסירה המוקדמת ממתינה לו.
    ///
    /// [leftStrip] מדמה את מה שהרצועה מדווחת ב-`onLeave` — הסמן משך את
    /// הכרטיסיה מחוץ לרצועה. ברירת המחדל היא **סידור**, כלומר בלי יציאה,
    /// כדי שבדיקה שלא הצהירה על יציאה לא תיהנה מהמסירה בשקט.
    Future<bool Function()> startDragAt(
      OpenedTab tab,
      int fromY, {
      bool withMock = true,
      bool leftStrip = false,
    }) async {
      overSelf();
      runner.cursorY = fromY;
      runner.approachingTop = false;
      var cancelled = false;
      drag.begin(
        tab,
        colors,
        tabsBloc: tabsBloc,
        cancelDrag: () => cancelled = true,
      );
      if (leftStrip) drag.notePointerLeftStrip();
      if (withMock) await applyMock(drag);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return () => cancelled;
    }

    /// מזיז את הסמן לגובה [toY] ומדווח שהוא מתקרב לראש הצג.
    void moveToTop(int toY) {
      runner.cursorY = toY;
      runner.approachingTop = true;
    }

    test('נסיעה מעלה אל אזור ההתקרבות מוסרת את הגרירה למערכת', () async {
      final cancelled = await startDragAt(firstTab(), 200, leftStrip: true);
      expect(runner.systemDragCalls, 0, reason: 'ברצועה — אין מסירה');

      moveToTop(20);
      await Future<void>.delayed(settle);

      expect(
        runner.systemDragCalls,
        1,
        reason: 'בלי המסירה מסדר החלונות אינו נפתח כלל',
      );
      expect(cancelled(), isTrue, reason: 'גרירת Flutter מבוטלת במסירה');
    });

    test('⚠️ המסירה מקדימה את הקצה ומשאירה נסיעה ללולאת ההזזה', () async {
      // ⚠️ זו כל נקודת התיקון. `y=20` הוא **לא** הקצה: מכאן והלאה
      // המשתמש ממשיך לנסוע מעלה בתוך לולאת ההזזה של Windows, וזו
      // הנסיעה שה-shell רואה כ"החלון נכנס לאזור העליון". מסירה
      // ב-`y=0` — מה שהיה קורה קודם — אינה משאירה כלום.
      await startDragAt(firstTab(), 200, leftStrip: true);
      moveToTop(20);
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 1);
      expect(
        runner.cursorY,
        greaterThan(0),
        reason: 'מסירה בקצה עצמו היא הבאג, לא התיקון',
      );
    });

    test('ההצמדה שנבחרה פותחת חלון במסגרת שלה', () async {
      // המסלול המלא: נסיעה מעלה → מסירה → מסדר החלונות → בחירת אזור.
      runner.systemDragTarget = (slot: 1, isSelf: true, isShellTray: false);
      runner.systemDragResult = (
        ran: true,
        snapped: true,
        left: 960,
        top: 0,
        width: 960,
        height: 1040,
      );

      await startDragAt(firstTab(), 200, leftStrip: true);
      moveToTop(20);
      await Future<void>.delayed(settle);

      expect(runner.openWindowCalls, 1);
      final bounds = runner.lastOpenArgs?['bounds'] as Map<Object?, Object?>?;
      expect(bounds?['left'], 960);
      expect(bounds?['width'], 960);
      expect(tabsBloc.events.whereType<RemoveTab>(), hasLength(1));
    });

    test('שחרור בלי הצמדה מעל חלון המקור — הכרטיסיה נשארת במקומה', () async {
      // ⚠️ זו רשת הביטחון של המסירה המוקדמת: מהרגע שהיא קורית גרירת
      // Flutter מבוטלת, ולכן חייבת להיות דרך לומר "התחרטתי". שחרור מעל
      // החלון עצמו הוא היא, וההתנהגות הזו קיימת ממילא בכל מסלול מסירה.
      runner.systemDragTarget = (slot: 1, isSelf: true, isShellTray: false);
      runner.systemDragResult = (
        ran: true,
        snapped: false,
        left: 0,
        top: 0,
        width: 623,
        height: 678,
      );

      await startDragAt(firstTab(), 200, leftStrip: true);
      moveToTop(20);
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 1, reason: 'המסירה כן קרתה');
      expect(runner.openWindowCalls, 0);
      expect(tabsBloc.events, isEmpty, reason: 'הכרטיסיה לא זזה');
    });

    test('⚠️ סידור אופקי עם סחיפה מעלה בתוך הרצועה אינו נמסר', () async {
      // ⚠️ הרגרסיה שהסקירה מצאה, ושהבדיקה הזו שחזרה לפני התיקון.
      //
      // הרצועה **היא** הסרגל העליון (0..40 יחידות לוגיות), ואזור
      // ההתקרבות (28) יושב בתוכה — כלומר תפיסה בשליש התחתון של כרטיסיה
      // וסחיפה מעלה בזמן סידור נמסרה למערכת, גרירת Flutter בוטלה,
      // ו-`MoveTab` לא נורה מעולם. הסידור פשוט אבד.
      //
      // ‎`leftStrip: false` — סידור אינו יוצא מהרצועה, וזה כל ההבדל.
      final cancelled = await startDragAt(firstTab(), 35);
      moveToTop(8);
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 0, reason: 'הסידור נחטף למסירה');
      expect(cancelled(), isFalse, reason: 'גרירת Flutter בוטלה באמצע סידור');
      expect(tabsBloc.events, isEmpty);
    });

    test('⚠️ סידור ברצועה האנכית — שעולה מעצמו — אינו נמסר', () async {
      // ⚠️ ברצועה האנכית זה גרוע יותר: שם סידור **הוא** מחווה שעולה,
      // ומעבר של משבצת אחת (`kVerticalTabHeight` = 38) עובר את סף
      // הנסיעה בעצמו. גרירה של הכרטיסיה השלישית למקום הראשון בחלון
      // שצמוד לראש המסך נמסרה למערכת.
      final cancelled = await startDragAt(firstTab(), 78);
      moveToTop(20);
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 0);
      expect(cancelled(), isFalse);
      expect(tabsBloc.events, isEmpty);
    });

    test('⚠️ סידור של כרטיסיה שאינה ניתנת להעברה אינו מציג שגיאה', () async {
      // ⚠️ `_rejectTransfer` במסלול שבתוך החלון הפך סידור מקומי של
      // כרטיסיה כזו להודעת שגיאה "אי אפשר להעביר לחלון אחר" — משפט
      // שאינו נכון על מה שהמשתמש עשה — וגם ביטל את הגרירה. ההודעה
      // נשארת רק במסלול היציאה מהחלון, שם היא מתארת את הכוונה.
      tabsBloc.emitState(
        TabsState(tabs: [_UnserializableTab(), firstTab()], currentTabIndex: 0),
      );

      final cancelled = await startDragAt(tabsBloc.state.tabs.first, 35);
      moveToTop(8);
      await Future<void>.delayed(settle);

      expect(cancelled(), isFalse, reason: 'הסידור בוטל בגלל הודעת שגיאה');
      expect(runner.systemDragCalls, 0);
      expect(tabsBloc.events, isEmpty);
    });

    test('⚠️ כרטיסיה שאינה ניתנת להעברה אינה נמסרת גם אחרי יציאה', () async {
      tabsBloc.emitState(
        TabsState(tabs: [_UnserializableTab(), firstTab()], currentTabIndex: 0),
      );

      await startDragAt(tabsBloc.state.tabs.first, 200, leftStrip: true);
      moveToTop(20);
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 0);
      expect(tabsBloc.events, isEmpty);
    });

    test('⚠️ סידור כרטיסיות ברצועה אינו נחטף', () async {
      // ⚠️ הבדיקה שמגנה על המחווה הנפוצה. אזור ההתקרבות חייב להישאר
      // **מעל** רצועת הכרטיסיות: מסירה שהייתה נוגעת בה מבטלת את גרירת
      // Flutter באמצע סידור, כלומר הסידור אובד.
      final cancelled = await startDragAt(firstTab(), 200, leftStrip: true);
      final moving = Timer.periodic(
        const Duration(milliseconds: 30),
        (_) => runner.cursorX += 40,
      );
      addTearDown(moving.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      moving.cancel();

      expect(runner.systemDragCalls, 0);
      expect(cancelled(), isFalse, reason: 'הסידור נשאר בידי Flutter');
      expect(tabsBloc.events, isEmpty);
    });

    test('⚠️ תפיסה שכבר ליד ראש המסך, בלי נסיעה, אינה נמסרת', () async {
      // ⚠️ בלי תנאי הנסיעה כל גרירה שהתחילה ליד ראש המסך הייתה נמסרת
      // בפעימה הראשונה — כלומר סידור כרטיסיות בחלון שצמוד לראש המסך
      // היה נעלם מהתוכנה כליל.
      final cancelled = await startDragAt(firstTab(), 12);
      runner.approachingTop = true;
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(runner.systemDragCalls, 0);
      expect(cancelled(), isFalse);
    });

    test('⚠️ ממתינה למוק החלון, ואינה מוסרת עם שרטוט', () async {
      // ⚠️ זו הרגרסיה שדווחה: "כשקופץ מסדר החלונות יופיע בעכבר החלון
      // הממוזער — כרגע מופיע רק סימול של כרטיסייה".
      //
      // `SetImage` מדלג על `Compose` בזמן לולאת ההזזה, ולכן מוק שמגיע
      // אחרי המסירה אינו מוצג לעולם והמשתמש גורר את שרטוט ה-GDI. בגרירה
      // החוצה זה לא נראה — הצילום מזמן הגיע — אבל המסירה המוקדמת יורה
      // תוך פעימות בודדות ומקדימה אותו.
      final cancelled = await startDragAt(
        firstTab(),
        200,
        withMock: false,
        leftStrip: true,
      );
      moveToTop(20);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        runner.systemDragCalls,
        0,
        reason: 'בלי מוק המסירה הייתה גוררת ראש כרטיסיה ב-176×40',
      );
      expect(cancelled(), isFalse);

      // ברגע שהמוק בידי הנייטיב, הפעימה הבאה מוסרת.
      await applyMock(drag);
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 1);
      expect(
        runner.imageArrivedAfterHandOff,
        isFalse,
        reason: 'המוק הקדים את לולאת ההזזה — זו כל הנקודה',
      );
    });

    test('ירידה לאזור הקריאה וחזרה מעלה נחשבת נסיעה מעלה', () async {
      // ⚠️ הנסיעה נמדדת מהנקודה **הנמוכה** ביותר ולא מנקודת ההתחלה:
      // גרירה שירדה לאזור הקריאה וחזרה מעלה היא יציאה מעלה לכל דבר.
      await startDragAt(firstTab(), 100, leftStrip: true);
      runner.cursorY = 400;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(runner.systemDragCalls, 0, reason: 'למטה — אין מסירה');

      moveToTop(20);
      await Future<void>.delayed(settle);

      expect(runner.systemDragCalls, 1);
    });
  });

  group('כרטיסיה שאינה שורדת סריאליזציה', () {
    const colors = DragPreviewColors(
      tab: Color(0xFF202020),
      border: Color(0xFF404040),
      text: Color(0xFFF0F0F0),
    );

    setUp(() {
      tabsBloc.emitState(
        TabsState(tabs: [_UnserializableTab(), firstTab()], currentTabIndex: 0),
      );
      runner.cursorTarget = (slot: null, isSelf: false, isShellTray: false);
    });

    test('נחסמת לפני כל ניסיון העברה', () async {
      await drag.handleDroppedOutside(tabsBloc.state.tabs.first, tabsBloc);

      expect(runner.openWindowCalls, 0);
      expect(tabsBloc.events, isEmpty);
    });

    test('⚠️ הגרירה נעצרת בפעימה הראשונה בחוץ ואינה חוזרת בלולאה', () async {
      // ⚠️ הבדיקה הזו היא ההגנה על H4: `canTransfer` בונה כרטיסיה מלאה —
      // BLoC, repository ומנויים — וקודם לכן היא נקראה מתוך לולאת הפעימות
      // של 60ms. כשהכרטיסיה נדחתה, `_handOffToSystem` חזר בלי לסמן דבר,
      // הטיימר המשיך, וכל 60ms נבנה BLoC חדש ונזרק כל עוד הסמן בחוץ.
      var cancelled = false;
      drag.begin(
        tabsBloc.state.tabs.first,
        colors,
        tabsBloc: tabsBloc,
        cancelDrag: () => cancelled = true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(cancelled, isTrue, reason: 'הגרירה בוטלה עם הודעה');
      expect(runner.systemDragCalls, 0, reason: 'לא נמסרה למערכת');
      expect(runner.openWindowCalls, 0);
      expect(tabsBloc.events, isEmpty);
      // הפעימות נמשכו 400ms; בלי העצירה היו כאן שש קריאות ומעלה.
      expect(runner.cursorQueries, lessThanOrEqualTo(2));
    });
  });
}

/// ה-runner המדומה — עונה על ערוץ `otzaria/multiwindow`.
class _FakeRunner {
  ({int? slot, bool isSelf, bool isShellTray}) cursorTarget = (
    slot: null,
    isSelf: false,
    isShellTray: false,
  );
  bool openWindowResult = true;
  int openWindowCalls = 0;

  /// התקרבות לראש הצג, ומיקום הסמן שמדווח בכל פעימה.
  ///
  /// ⚠️ שדות נפרדים ולא הרחבה של [cursorTarget]: הוא נבנה בעשרים מקומות
  /// בקובץ, וברירות המחדל כאן משאירות את כולם על ההתנהגות הקודמת —
  /// כלומר אף בדיקה קיימת אינה נכנסת בטעות למסלול המסירה המוקדמת.
  bool approachingTop = false;
  int cursorX = 100;
  int cursorY = 200;

  /// סף הנסיעה מעלה, כפי שהנייטיב מחשב אותו לפי ה-DPI של הצג.
  int minUpwardTravel = 24;

  /// כמה פעימות של המעקב יצאו לנייטיב — מודד שהלולאה נעצרה.
  int cursorQueries = 0;
  Completer<void>? cursorGate;

  /// כמה פעמים נשלח צילום הכרטיסיה, והאם הוא הגיע **אחרי** המסירה למערכת.
  int setImageCalls = 0;
  Completer<void>? imageGate;
  bool imageArrivedAfterHandOff = false;
  Map<Object?, Object?>? lastOpenArgs;

  /// היעד שהמערכת מדווחת עליו **בשחרור**, אם הוא שונה מזה שבזמן הגרירה.
  ///
  /// ⚠️ ההפרדה היא כל הנקודה: הגרירה עוברת מעל שולחן העבודה, וההחלטה
  /// נופלת לפי מה שתחת הסמן ברגע השחרור.
  ({int? slot, bool isSelf, bool isShellTray})? systemDragTarget;
  int systemDragCalls = 0;

  /// שער שמדמה את **החסימה** האמיתית: `dragOutToSystem` נענה רק כשהמשתמש
  /// שחרר, כי התשובה היא המסגרת הסופית. בלי השער המדומה עונה מיד, וכל
  /// המסלול היה מסתיים באותה מיקרו-משימה — כלומר "לא נפתח חלון בזמן
  /// הגרירה" היה עובר גם אם כן נפתח.
  Completer<void>? systemDragGate;
  ({bool ran, bool snapped, int left, int top, int width, int height})
  systemDragResult = (
    ran: true,
    snapped: false,
    left: 0,
    top: 0,
    width: 176,
    height: 40,
  );

  /// ⚠️ שני מונים נפרדים, כי ההבחנה ביניהם היא כל התיקון: `freeze` משאיר
  /// את הרוח במקום השחרור עד שהחלון האמיתי מחליף אותה, ו-`end` מסתיר.
  int freezeCalls = 0;
  int endCalls = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MultiWindowService.channel, (call) async {
          switch (call.method) {
            case 'windowAtCursor':
              cursorQueries++;
              final target = cursorTarget;
              final isApproachingTop = approachingTop;
              final minTravel = minUpwardTravel;
              final x = cursorX;
              final y = cursorY;
              await cursorGate?.future;
              return {
                'slot': target.slot,
                'isSelf': target.isSelf,
                'isShellTray': target.isShellTray,
                'approachingTop': isApproachingTop,
                'minUpwardTravel': minTravel,
                'x': x,
                'y': y,
              };
            case 'setTabDragImage':
              setImageCalls++;
              if (systemDragCalls > 0) imageArrivedAfterHandOff = true;
              await imageGate?.future;
              return null;
            case 'dragOutToSystem':
              systemDragCalls++;
              await systemDragGate?.future;
              final target = systemDragTarget ?? cursorTarget;
              return {
                'ran': systemDragResult.ran,
                'snapped': systemDragResult.snapped,
                'left': systemDragResult.left,
                'top': systemDragResult.top,
                'width': systemDragResult.width,
                'height': systemDragResult.height,
                'slot': target.slot,
                'isSelf': target.isSelf,
                'isShellTray': target.isShellTray,
                'x': 100,
                'y': 200,
              };
            case 'openWindow':
              openWindowCalls++;
              lastOpenArgs = call.arguments as Map<Object?, Object?>?;
              return openWindowResult;
            case 'freezeTabDrag':
              freezeCalls++;
              return null;
            case 'endTabDrag':
              endCalls++;
              return null;
            case 'windowCount':
              return {'count': 1, 'max': 4, 'engines': 1};
            default:
              return null;
          }
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MultiWindowService.channel, null);
  }
}

/// חלון יעד מדומה על האפיק.
class _FakePeer {
  _FakePeer(this.slot, {required this.accept});

  final int slot;
  final bool accept;
  int receivedTabs = 0;
  late final ReceivePort _port;

  void register() {
    _port = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.$slot',
    );
    _port.listen((message) {
      final map = message as Map;
      final reply = map['reply'] as SendPort;
      final body = Map<String, dynamic>.from(map['body'] as Map);
      if (body['type'] == MultiWindowService.requestReceiveTab) {
        receivedTabs++;
        reply.send({'ok': true, 'result': accept});
        return;
      }
      reply.send({'ok': true, 'result': null});
    });
  }

  void dispose() {
    ui.IsolateNameServer.removePortNameMapping('$_namespace.$slot');
    _port.close();
  }
}

class _RecordingTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _RecordingTabsBloc(super.initialState);

  final List<TabsEvent> events = [];

  void emitState(TabsState state) => emit(state);

  @override
  void add(TabsEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnserializableTab extends OpenedTab {
  _UnserializableTab() : super('כרטיסיה שבורה');

  @override
  Map<String, dynamic> toJson() => {'type': 'DefinitelyNotATabType'};

  @override
  OpenedTab clone() => _UnserializableTab();
}
