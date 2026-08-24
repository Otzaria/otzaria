import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_focus.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

/// בדיקות למסלול "אפשר להקליד בתוסף מיד בפתיחתו" (issue #958).
///
/// הפוקוס של ה-WebView חי מחוץ לעץ של Flutter, ולכן פתיחת טאב תוסף מבקשת
/// העברה נייטיבית דרך הדיספצ'ר. הבקשה מגיעה לפני שה-WebView נוצר ולפני
/// שההחייאה שלו הושלמה, ולכן היא נזכרת ומתבצעת ברגע שהמופע מוכן.

/// controller שמדמה את מסלול ווינדוס: `MoveFocus` מגיע דרך ערוץ
/// ה-platform view של ה-viewId, ולכן הספירה נעשית שם.
class _FocusController extends Fake implements InAppWebViewController {
  _FocusController() : viewId = ++_nextViewId {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == kPlatformViewRequestFocusMethod) focusCalls++;
          return null;
        });
  }

  static int _nextViewId = 0;

  final int viewId;
  int focusCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;

  /// מדמה את ההתנהגות בייצור: אחרי MoveFocus מוצלח הדף מחזיק את הפוקוס,
  /// ו-`document.hasFocus()` מדכא בקשה נוספת.
  bool pageHasFocusAfterFirst = false;

  /// שער לעיכוב ההחייאה — מדמה את חלון הזמן שבו המופע מוצג אך עוד מוקפא.
  Completer<void>? resumeGate;

  MethodChannel get _channel =>
      MethodChannel(customPlatformViewChannelName(viewId));

  @override
  dynamic getViewId() => viewId;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> resume() async {
    resumeCalls++;
    final gate = resumeGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains('document.hasFocus()')) {
      return pageHasFocusAfterFirst && focusCalls > 0;
    }
    return null;
  }
}

class _BareController extends Fake implements InAppWebViewController {}

const _pid = 'focus.test.plugin';
const _other = 'focus.test.other';

PluginRuntimeDispatcher get _d => PluginRuntimeDispatcher.instance;

PluginInstanceKey _fg(
  String pluginId, [
  String instanceId = PluginInstanceIds.defaultForeground,
]) => (pluginId: pluginId, instanceId: instanceId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await _d.prepareForAppRestart();
    // prepareForAppRestart משאיר את _shutdownMode ב-'restart'; רישום וביטול
    // של controller דמה מחזירים ל-idle.
    _d.registerController('__focus_reset__', _BareController());
    _d.unregisterController('__focus_reset__');
    _d.resetVisibilityForTesting();
    // ווינדוס: הפלטפורמה שבה הבאג חי, ובה גם pause/resume נייטיביים.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() {
    _d.unregisterController(_pid);
    _d.unregisterController(_pid, instanceId: 'second');
    _d.unregisterController(_pid, instanceId: PluginInstanceIds.background);
    _d.unregisterController(_other);
    debugDefaultTargetPlatformOverride = null;
  });

  group('מופע מוכן ומוצג', () {
    test('הפוקוס מועבר מיד', () async {
      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      expect(await _d.requestKeyboardFocus(_pid), isTrue);
      expect(controller.focusCalls, 1);
    });

    test('בקשה שנייה מדוכאת כשהדף כבר במיקוד', () async {
      // אחרי ההעברה הראשונה `document.hasFocus()` מחזיר true, ו-MoveFocus
      // נוסף היה מבטל את הפוקוס שכבר הושג.
      final controller = _FocusController()..pageHasFocusAfterFirst = true;
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      await _d.requestKeyboardFocus(_pid);
      await _d.requestKeyboardFocus(_pid);

      expect(controller.focusCalls, 1);
    });

    test('מזהה מופע לא מוכר — false ובלי מופע רפאים', () async {
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      expect(
        await _d.requestKeyboardFocus(_pid, instanceId: 'no-such'),
        isFalse,
      );
      // אין controller — סיום טעינה מדומה של אותו מזהה לא יפעיל פוקוס.
      final controller = _FocusController();
      _d.registerController(_pid, controller, instanceId: 'other');
      await _d.onForegroundInstanceReady(_pid, instanceId: 'other');
      expect(controller.focusCalls, 0);
      _d.unregisterController(_pid, instanceId: 'other');
      _d.unregisterController(_pid, instanceId: 'no-such');
    });
  });

  group('ה-WebView עוד לא נוצר', () {
    test('הבקשה נזכרת ומתבצעת בסיום הטעינה', () async {
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      expect(await _d.requestKeyboardFocus(_pid), isFalse);

      final controller = _FocusController();
      _d.registerController(_pid, controller);
      expect(
        controller.focusCalls,
        0,
        reason: 'רישום ה-controller לבדו מקדים את ה-autofocus של הדף',
      );

      await _d.onForegroundInstanceReady(_pid);
      expect(controller.focusCalls, 1);
    });

    test('בלי בקשה קודמת — סיום טעינה אינו חוטף פוקוס', () async {
      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      await _d.onForegroundInstanceReady(_pid);

      expect(controller.focusCalls, 0);
    });

    test('הבקשה מבוצעת פעם אחת בלבד', () async {
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();
      await _d.requestKeyboardFocus(_pid);

      final controller = _FocusController();
      _d.registerController(_pid, controller);
      await _d.onForegroundInstanceReady(_pid);
      await _d.onForegroundInstanceReady(_pid);

      expect(controller.focusCalls, 1);
    });

    test('הטעינה הסתיימה אחרי שהמשתמש עבר טאב — אין פוקוס', () async {
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();
      await _d.requestKeyboardFocus(_pid);

      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_other)});
      await pumpEventQueue();

      await _d.onForegroundInstanceReady(_pid);

      expect(controller.focusCalls, 0);
      expect(
        controller.pauseCalls,
        greaterThan(0),
        reason: 'המופע מושהה כרגיל',
      );
    });
  });

  group('מופע שאינו זכאי', () {
    test('אינו מוצג — לא מועבר ולא נזכר', () async {
      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_other)});
      await pumpEventQueue();

      expect(await _d.requestKeyboardFocus(_pid), isFalse);

      // גם סיום טעינה לא יעביר — הבקשה לא נזכרה.
      await _d.onForegroundInstanceReady(_pid);
      expect(controller.focusCalls, 0);
    });

    test('מסך העיון מוסתר — לא מועבר ולא נזכר', () async {
      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();
      _d.setReaderScreenVisible(false);
      await pumpEventQueue();

      expect(await _d.requestKeyboardFocus(_pid), isFalse);

      _d.setReaderScreenVisible(true);
      await pumpEventQueue();
      expect(
        controller.focusCalls,
        0,
        reason: 'חזרה למסך העיון אינה מריצה בקשה שלא נזכרה',
      );
    });

    test('מופע רקע — לעולם לא (WebView בלתי-נראה)', () async {
      final background = _FocusController();
      const key = (pluginId: _pid, instanceId: PluginInstanceIds.background);
      _d.registerController(
        _pid,
        background,
        instanceId: PluginInstanceIds.background,
      );
      // מסומן כגלוי בכוונה, כדי שרק שער ה"רקע" יוכל לחסום.
      _d.setVisiblePluginInstances({key});
      await pumpEventQueue();

      expect(
        await _d.requestKeyboardFocus(
          _pid,
          instanceId: PluginInstanceIds.background,
        ),
        isFalse,
      );
      expect(background.focusCalls, 0);
    });
  });

  // ── חיווט השערים ────────────────────────────────────────────────────────
  // המדיניות נבדקת כפונקציה טהורה במקום אחר; כאן מוודאים שהדיספצ'ר באמת
  // מזין לה את הפלטפורמה ואת מצב החלון, ולא רק מכריז עליהם.
  group('חיווט השערים', () {
    test('אנדרואיד — אין העברה גם כשהמופע מוכן ומוצג', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      expect(await _d.requestKeyboardFocus(_pid), isFalse);
      expect(controller.focusCalls, 0);

      // וגם לא נזכרת: סיום הטעינה לא יעביר פוקוס בדיעבד.
      await _d.onForegroundInstanceReady(_pid);
      expect(controller.focusCalls, 0);
    });

    test('iOS — אין העברה', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      expect(await _d.requestKeyboardFocus(_pid), isFalse);
      expect(controller.focusCalls, 0);
    });

    test('החלון אינו בחזית — אין העברה', () async {
      final binding = TestWidgetsFlutterBinding.instance;
      addTearDown(
        () => binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

      expect(await _d.requestKeyboardFocus(_pid), isFalse);
      expect(controller.focusCalls, 0);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(await _d.requestKeyboardFocus(_pid), isTrue);
    });
  });

  group('מופע מוצג אך עדיין מוקפא', () {
    test('הבקשה מתבצעת כשההחייאה מסתיימת', () async {
      final controller = _FocusController();
      _d.registerController(_pid, controller);

      // מעבר לטאב אחר משהה את המופע.
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();
      _d.setVisiblePluginInstances({_fg(_other)});
      await pumpEventQueue();
      expect(controller.pauseCalls, 1);

      // חזרה לטאב התוסף, עם החייאה מעוכבת — המצב שבו הבקשה מקדימה את resume.
      final gate = Completer<void>();
      controller.resumeGate = gate;
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      expect(await _d.requestKeyboardFocus(_pid), isFalse);
      expect(controller.focusCalls, 0);

      controller.resumeGate = null;
      gate.complete();
      await pumpEventQueue();

      expect(controller.focusCalls, 1);
    });

    test('השהיה מנקה בקשה שנזכרה — חזרה אינה יורה מעצמה', () async {
      // הבקשה נזכרת לפני שה-WebView נרשם, ולכן היא באמת ממתינה.
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();
      expect(await _d.requestKeyboardFocus(_pid), isFalse);

      final controller = _FocusController();
      _d.registerController(_pid, controller);

      // מעבר לטאב אחר משהה את המופע ומבטל את הבקשה.
      _d.setVisiblePluginInstances({_fg(_other)});
      await pumpEventQueue();
      // חזרה מחדשת את המופע; מעבר טאב מבקש פוקוס מחדש בעצמו, וההחייאה
      // לבדה אינה אמורה לירות בקשה עתיקה.
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      expect(controller.focusCalls, 0);
    });
  });

  group('ניקוי', () {
    test('סגירת הטאב מנקה בקשה שנזכרה', () async {
      // reload callback מחזיק את רשומת המופע גם אחרי ביטול ה-controller,
      // כך שהניקוי עצמו נבדק ולא רק הסרת הרשומה.
      _d.registerReloadCallback(_pid, () async {}, token: 'test');
      addTearDown(() => _d.unregisterReloadCallback(_pid, token: 'test'));
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();
      expect(await _d.requestKeyboardFocus(_pid), isFalse);

      _d.unregisterController(_pid);

      final reopened = _FocusController();
      _d.registerController(_pid, reopened);
      await _d.onForegroundInstanceReady(_pid);

      expect(reopened.focusCalls, 0);
    });

    test('cancelPendingKeyboardFocus מבטל בקשה שנזכרה', () async {
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();
      expect(await _d.requestKeyboardFocus(_pid), isFalse);

      // יציאה ממסך העיון — התוסף לא יהיה על המסך כשהטעינה תסתיים.
      _d.cancelPendingKeyboardFocus();

      final controller = _FocusController();
      _d.registerController(_pid, controller);
      await _d.onForegroundInstanceReady(_pid);

      expect(controller.focusCalls, 0);
    });

    test('resetVisibilityForTesting מנקה בקשות שנזכרו', () async {
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();
      await _d.requestKeyboardFocus(_pid);

      _d.resetVisibilityForTesting();

      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();
      await _d.onForegroundInstanceReady(_pid);

      expect(controller.focusCalls, 0);
    });
  });

  // ── שדה טקסט פעיל ────────────────────────────────────────────────────────
  // בקשה ישירה באה מיד אחרי שהמשתמש עבר לטאב התוסף — ואז שדה שהיה ממוקד
  // (חיפוש מגירת הכלים) הוא זה שהוא בדיוק עזב, ואין להיתלות בו. בקשה שנזכרה
  // ומתבצעת באיחור היא הסיכון: המשתמש כבר עלול להקליד במקום אחר.
  group('ה-UI של Flutter מחזיק את המקלדת', () {
    // testWidgets מאמת שאין override של פלטפורמה בסוף גוף הטסט, ולכן הוא
    // מנוקה כאן ולא ב-tearDown.
    Future<void> pumpTextField(WidgetTester tester, FocusNode node) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Material(child: TextField(focusNode: node)),
        ),
      );
      node.requestFocus();
      await tester.pump();
    }

    testWidgets('בקשה ישירה מתבצעת גם כששדה טקסט ממוקד', (tester) async {
      // המשתמש בדיוק הקליד בחיפוש מגירת הכלים ופתח את התוסף — השדה הזה הוא
      // מה שהוא עזב, ואין להיתלות בו.
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpTextField(tester, node);

      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await tester.pumpAndSettle();

      expect(await _d.requestKeyboardFocus(_pid), isTrue);
      expect(controller.focusCalls, 1);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('בקשה שנזכרה אינה גוזלת מקלדת משדה טקסט', (tester) async {
      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await tester.pumpAndSettle();

      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpTextField(tester, node);

      await _d.requestKeyboardFocus(_pid, deferred: true);

      expect(controller.focusCalls, 0);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('דיאלוג פתוח — בקשה שנזכרה אינה עוברת מתחתיו', (tester) async {
      final controller = _FocusController();
      _d.registerController(_pid, controller);
      _d.setVisiblePluginInstances({_fg(_pid)});
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('אישור')),
                  ],
                ),
              ),
              child: const Text('פתח'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      await _d.requestKeyboardFocus(_pid, deferred: true);

      expect(controller.focusCalls, 0);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  // ── התאמה למודל הטאבים ──────────────────────────────────────────────────
  // ToolTabScreen שולח (tab.toolId, tab.instanceId), ורשימת המופעים הגלויים
  // נבנית מ-ToolTab.visiblePluginInstancesOf. אי-התאמה בין השניים הייתה
  // משאירה את הבקשה בלי מופע גלוי — כלומר בלי פוקוס, בשקט.
  group('התאמה למודל הטאבים', () {
    test('טאב תוסף — המפתח שנשלח הוא המפתח שנרשם כגלוי', () async {
      final tab = ToolTab(toolId: _pid, title: 'תוסף');
      final controller = _FocusController();

      _d.registerController(tab.toolId, controller, instanceId: tab.instanceId);
      _d.setVisiblePluginInstances(ToolTab.visiblePluginInstancesOf(tab));
      await pumpEventQueue();

      expect(
        await _d.requestKeyboardFocus(
          tab.toolId,
          instanceId: tab.instanceId,
        ),
        isTrue,
      );
      expect(controller.focusCalls, 1);

      _d.unregisterController(tab.toolId, instanceId: tab.instanceId);
    });

    test('טאב מפוצל — כל חלונית מקבלת את הפוקוס שלה', () async {
      final right = ToolTab(toolId: _pid, title: 'ימין');
      final left = ToolTab(
        toolId: _other,
        title: 'שמאל',
        allowMultipleInstances: true,
      );
      final split = CombinedTab(rightTab: right, leftTab: left);
      final rightController = _FocusController();
      final leftController = _FocusController();

      _d.registerController(
        right.toolId,
        rightController,
        instanceId: right.instanceId,
      );
      _d.registerController(
        left.toolId,
        leftController,
        instanceId: left.instanceId,
      );
      _d.setVisiblePluginInstances(ToolTab.visiblePluginInstancesOf(split));
      await pumpEventQueue();

      await _d.requestKeyboardFocus(left.toolId, instanceId: left.instanceId);

      expect(leftController.focusCalls, 1);
      expect(rightController.focusCalls, 0);

      _d.unregisterController(right.toolId, instanceId: right.instanceId);
      _d.unregisterController(left.toolId, instanceId: left.instanceId);
    });
  });

  group('ריבוי מופעים של אותו תוסף', () {
    test('רק המופע המבוקש מקבל את הפוקוס', () async {
      final first = _FocusController();
      final second = _FocusController();
      _d.registerController(_pid, first);
      _d.registerController(_pid, second, instanceId: 'second');
      _d.setVisiblePluginInstances({_fg(_pid), _fg(_pid, 'second')});
      await pumpEventQueue();

      await _d.requestKeyboardFocus(_pid, instanceId: 'second');

      expect(second.focusCalls, 1);
      expect(first.focusCalls, 0);
    });

    test('מופע קדמי מקבל, מופע הרקע של אותו תוסף לא', () async {
      final foreground = _FocusController();
      final background = _FocusController();
      _d.registerController(_pid, foreground);
      _d.registerController(
        _pid,
        background,
        instanceId: PluginInstanceIds.background,
      );
      _d.setVisiblePluginInstances({_fg(_pid)});
      await pumpEventQueue();

      await _d.requestKeyboardFocus(_pid);

      expect(foreground.focusCalls, 1);
      expect(background.focusCalls, 0);
    });
  });
}
