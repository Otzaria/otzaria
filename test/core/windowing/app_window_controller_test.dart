import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:window_manager/window_manager.dart' show TitleBarStyle;

/// אי-אפשר להחליף את `windowManager` ב-mock — הוא singleton גלובלי מסוג
/// `final`. במקומו מיירטים את ערוץ ה-MethodChannel שמתחתיו, בדיוק כמו
/// ב-`test/utils/ui/fullscreen_helper_toggle_test.dart`.
///
/// ⚠️ `window_manager` אינו מיפוי 1:1 לערוץ. `show()` בודק מזעור ומשחזר
/// קודם, `center()` מיושם כ-getBounds+setBounds, ו-`startDragging()` הוא
/// **no-op במסך מלא ב-Windows**. לכן הבדיקות כאן מאמתות שהפעולה הגיעה
/// לערוץ — ולא רצף פנימי שהוא פרט מימוש של הספרייה.
const Map<String, dynamic> _display = <String, dynamic>{
  'id': 'display-1',
  'name': 'מסך בדיקה',
  'size': <String, dynamic>{'width': 1920.0, 'height': 1080.0},
  'visiblePosition': <String, dynamic>{'dx': 0.0, 'dy': 0.0},
  'visibleSize': <String, dynamic>{'width': 1920.0, 'height': 1040.0},
  'scaleFactor': 1.0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late Map<String, bool> boolResponses;

  setUp(() {
    calls = [];
    // ברירת המחדל היא חלון רגיל: לא ממוזער ולא במסך מלא. שני אלה משנים
    // את מסלול הביצוע של show() ו-startDragging().
    boolResponses = {
      'isVisible': true,
      'isMaximized': true,
      'isMinimized': false,
      'isFullScreen': false,
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          calls.add(call);
          // כל getter מפרש את התשובה בטיפוס אחר: השאילתות הבוליאניות
          // מצפות ל-bool, ו-getBounds למפה. תשובה אחידה נופלת ב-cast.
          if (boolResponses.containsKey(call.method)) {
            return boolResponses[call.method];
          }
          if (call.method == 'getBounds') {
            return <String, dynamic>{
              'x': 1.0,
              'y': 2.0,
              'width': 3.0,
              'height': 4.0,
            };
          }
          return null;
        });

    // `center()` שואל שלוש שאלות ברצף: היכן הסמן, מהם כל המסכים, ומהו
    // הראשי — לכל אחת צורת תשובה משלה, ורשימת מסכים ריקה זורקת.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.leanflutter.plugins/screen_retriever'),
          (call) async => switch (call.method) {
            'getCursorScreenPoint' => <String, dynamic>{'dx': 0.0, 'dy': 0.0},
            'getAllDisplays' => <String, dynamic>{
              'displays': <dynamic>[_display],
            },
            _ => _display,
          },
        );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.leanflutter.plugins/screen_retriever'),
      null,
    );
  });

  const controller = WindowManagerAppWindowController();

  Future<void> expectReachesChannel(
    Future<void> Function() action,
    String channelMethod,
  ) async {
    calls.clear();
    await action();
    expect(
      calls.map((c) => c.method),
      contains(channelMethod),
      reason: 'הפעולה לא הגיעה לערוץ כ-$channelMethod',
    );
  }

  test('ברירת המחדל של המזהה היא החלון הראשי', () {
    expect(controller.id, AppWindowId.primary);
    expect(
      const WindowManagerAppWindowController(id: AppWindowId('window-2')).id,
      const AppWindowId('window-2'),
    );
  });

  test('כל פעולה מגיעה לערוץ', () async {
    await expectReachesChannel(controller.show, 'show');
    await expectReachesChannel(controller.focus, 'focus');
    await expectReachesChannel(controller.minimize, 'minimize');
    await expectReachesChannel(controller.maximize, 'maximize');
    await expectReachesChannel(controller.unmaximize, 'unmaximize');
    await expectReachesChannel(controller.startDragging, 'startDragging');
    await expectReachesChannel(controller.close, 'close');
    // שם המתודה בערוץ נשאר `destroy` — זו הספרייה. השם אצלנו שונה כי הוא
    // מסיים את התוכנה, וההטעיה כבר עלתה בקריסת יציאה בייצור.
    await expectReachesChannel(controller.quitApplication, 'destroy');
    // אין מתודת ערוץ בשם center — הספרייה מחשבת מיקום ומזיזה את החלון.
    await expectReachesChannel(controller.center, 'setBounds');
  });

  test('show משחזר חלון ממוזער לפני שהוא מציג אותו', () async {
    boolResponses['isMinimized'] = true;
    calls.clear();

    await controller.show();

    final methods = calls.map((c) => c.method).toList();
    expect(methods, containsAllInOrder(['restore', 'show']));
  });

  test('startDragging במסך מלא — no-op ב-Windows בלבד', () async {
    // התנהגות של הספרייה שכדאי להכיר לפני שמעבירים אליה קוראים: גרירה
    // מסרגל הכותרת פשוט לא תקרה במסך מלא.
    //
    // ⚠️ **הבדיקה מגודרת בפלטפורמה, כי ההתנהגות עצמה מגודרת בה.** המקור
    // הוא `if (Platform.isWindows && await isFullScreen()) return;`
    // ב-`window_manager`, ולכן הצפייה ההפוכה — שהקריאה כן מגיעה לערוץ —
    // היא הנכונה בכל שאר הפלטפורמות. ניסוח שבדק רק את צד Windows היה
    // ירוק על מכונת המפתח ואדום ב-CI שרץ על ubuntu.
    boolResponses['isFullScreen'] = true;
    calls.clear();

    await controller.startDragging();

    expect(
      calls.map((c) => c.method),
      Platform.isWindows
          ? isNot(contains('startDragging'))
          : contains(
              'startDragging',
            ),
      reason: Platform.isWindows
          ? 'ב-Windows הספרייה בולעת את הגרירה במסך מלא'
          : 'מחוץ ל-Windows אין גידור, והגרירה חייבת להגיע לערוץ',
    );
  });

  test('השאילתות מחזירות את תשובת הערוץ', () async {
    boolResponses
      ..['isMinimized'] = true
      ..['isFullScreen'] = true;

    expect(await controller.isVisible(), isTrue);
    expect(await controller.isMaximized(), isTrue);
    expect(await controller.isMinimized(), isTrue);
    expect(await controller.isFullScreen(), isTrue);

    boolResponses['isVisible'] = false;
    expect(await controller.isVisible(), isFalse);
  });

  test('setTitleBarStyle מעביר את windowButtonVisibility הלאה', () async {
    // שלושת אתרי הקריאה באפליקציה מעבירים false; אילו הערך היה נבלע,
    // כפתורי המערכת היו חוזרים לצד הכפתורים המותאמים.
    calls.clear();
    await controller.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );

    final call = calls.single;
    expect(call.method, 'setTitleBarStyle');
    expect((call.arguments as Map)['windowButtonVisibility'], isFalse);
  });

  test('הגאומטריה מגיעה לערוץ', () async {
    await expectReachesChannel(
      () => controller.setBounds(const Rect.fromLTWH(1, 2, 3, 4)),
      'setBounds',
    );
    await expectReachesChannel(
      () => controller.setSize(const Size(300, 400)),
      // setSize מיושם ב-window_manager דרך setBounds.
      'setBounds',
    );
    await expectReachesChannel(
      () => controller.setMinimumSize(const Size(100, 200)),
      'setMinimumSize',
    );
    await expectReachesChannel(
      () => controller.setFullScreen(true),
      'setFullScreen',
    );
    await expectReachesChannel(controller.getBounds, 'getBounds');
  });
}
