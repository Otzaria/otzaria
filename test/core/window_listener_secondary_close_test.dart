import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/shared_hive_store.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.secondaryclose';

/// סגירת חלון שאינו האחרון — המסלול שעקף את Dart לגמרי.
///
/// ## מה היה שבור
///
/// `setPreventClose(true)` ורישום ה-listener נעשו ב-`_runAppBootstrap`
/// בלבד, כלומר בחלון הראשון. בחלון משני הפלאגין העביר את `WM_CLOSE` הלאה
/// ל-`Win32Window::MessageHandler`, שהסתיר את החלון — ואף שורת Dart של
/// הסגירה לא רצה: לא ה-flush של ההיסטוריה והכרטיסיות
/// ([PreCloseRegistry]), לא השאלה על שינויים שלא נשמרו, ולא מחיקת סשן
/// החלון. הבדיקות כאן מתארות את המסלול כפי שהוא **צריך** להיות, בשני
/// סוגי החלונות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late _FakeRunner runner;

  setUp(() async {
    WindowBus.namespace = _namespace;
    WindowRole.isSecondary = false;
    // ⚠️ בלי זה כל הסוויטה בודקת את מסלול חלון-יחיד. `windowCount` ו-
    // `closeSelf` מגודרים ב-`MultiWindowService.isSupported`, שהוא
    // `Platform.isWindows` — כלומר על ubuntu (ה-CI) `windowCount` מחזיר
    // 1 בלי לגעת בערוץ המדומה, `_isLastWindowClosing` עונה "כן", והרצף
    // פונה לכיבוי התהליך במקום לסגירת החלון הבודד. הבדיקות היו ירוקות
    // על מכונת המפתח ואדומות ב-CI, ומה שהן מתארות אינו תלוי פלטפורמה:
    // ה-runner שמעבר לערוץ מדומה כאן ממילא.
    MultiWindowService.debugSupportedOverride = true;
    runner = _FakeRunner()..install();
    tmp = Directory.systemTemp.createTempSync('otzaria_secclose_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('tabs');
  });

  tearDown(() async {
    runner.uninstall();
    MultiWindowService.debugSupportedOverride = null;
    WindowRole.isSecondary = false;
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    SharedHiveStore.instance.resetForTest();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    WindowBus.namespace = 'otzaria.window';
    await Hive.deleteFromDisk();
  });

  test('חלון משני שאינו האחרון: flush רץ, הסשן נמחק, ורק הוא נסגר', () async {
    final owner = _FakeOwner(1)..register();
    addTearDown(owner.dispose);

    var flushed = false;
    Future<void> flush() async => flushed = true;
    PreCloseRegistry.register(flush);
    addTearDown(() => PreCloseRegistry.unregister(flush));

    WindowRole.isSecondary = true;
    WindowBus.instance.register();
    // כרטיסיות שמורות תחת המפתח של החלון הזה.
    await TabsRepository().saveTabs(const [], 0);
    final sessionKey = SharedHiveStore.tabsKeyForWindow(
      WindowBus.instance.slot,
      'key-tabs',
    );
    expect(owner.box.containsKey(sessionKey), isTrue);

    await AppWindowListener().handleWindowClose();

    expect(flushed, isTrue, reason: 'הכתיבות התלויות נשטפו');
    expect(runner.closeSelfCalls, 1, reason: 'רק החלון הזה נסגר');
    expect(
      owner.box.containsKey(sessionKey),
      isFalse,
      reason:
          'הסשן נמחק — בלעדיו `adoptOrphanWindowSessions` היה מחזיר '
          'בהפעלה הבאה כרטיסיות שהמשתמש סגר במכוון',
    );
  });

  test('החלון הראשון שאינו האחרון: הסשן נכתב ריק ולא נמחק', () async {
    // ⚠️ ההצדקה זהה לזו של חלון משני — הוא נסגר במכוון בעוד אחרים
    // פתוחים — אבל המפתח שלו הוא ההיסטורי, ולכן הוא נכתב כרשימה ריקה:
    // `loadTabs` ו-`NavigationBloc` קוראים אותו בהפעלה קרה, ומפתח חסר
    // אינו מבחין בין "אין כרטיסיות" לבין "טרם נשמר".
    final box = Hive.box<dynamic>('tabs');
    await box.put('key-tabs', [
      {'type': 'ToolTab', 'toolId': 'builtin.calendar', 'title': 'לוח שנה'},
    ]);

    await AppWindowListener().handleWindowClose();

    expect(runner.closeSelfCalls, 1);
    expect(box.containsKey('key-tabs'), isTrue);
    expect(box.get('key-tabs'), isEmpty);
  });

  /// חלון שהתרוקן מכרטיסיות — בגרירת הכרטיסיה האחרונה לחלון אחר, או
  /// בסגירתה ב-X. עד כאן הוא נשאר פתוח על מסך הספרייה (issue #1187).
  group('closeIfEmptied', () {
    void asSecondaryWindow() {
      final owner = _FakeOwner(1)..register();
      addTearDown(owner.dispose);
      WindowRole.isSecondary = true;
      WindowBus.instance.register();
    }

    test('חלון משני שהתרוקן ואינו האחרון — נסגר', () async {
      asSecondaryWindow();

      await AppWindowListener().closeIfEmptied();

      expect(runner.closeSelfCalls, 1);
    });

    test('החלון הגלוי האחרון נשאר פתוח על מסך הספרייה', () async {
      asSecondaryWindow();
      runner.visibleWindows = 1;

      await AppWindowListener().closeIfEmptied();

      expect(
        runner.closeSelfCalls,
        0,
        reason: 'סגירתו הייתה מכבה את התוכנה בעוד המשתמש רק רוקן חלון',
      );
    });

    test('החלון הראשי נשאר פתוח — אפס כרטיסיות הוא מצב הספרייה שלו', () async {
      await AppWindowListener().closeIfEmptied();

      expect(runner.closeSelfCalls, 0);
    });
  });
}

/// ה-runner המדומה. `windowCount` מחזיר שניים — כלומר "אינך האחרון".
class _FakeRunner {
  int closeSelfCalls = 0;

  /// מספר החלונות **הגלויים**. `1` הוא "אתה האחרון".
  int visibleWindows = 2;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MultiWindowService.channel, (call) async {
          switch (call.method) {
            case 'windowCount':
              return {'count': visibleWindows, 'max': 4, 'engines': 2};
            case 'closeSelf':
              closeSelfCalls++;
              return null;
            case 'setBusSlot':
              return null;
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

/// בעלים אמיתי — מריץ את `handleRequest`, הקוד שמשרת כל חלון משני.
class _FakeOwner {
  _FakeOwner(this.slot);

  final int slot;
  final SharedHiveStore store = SharedHiveStore.owner();
  late final ReceivePort _port;

  Box<dynamic> get box => Hive.box<dynamic>('tabs');

  void register() {
    _port = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.$slot',
    );
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.owner',
    );
    _port.listen((message) async {
      final map = message as Map;
      final reply = map['reply'] as SendPort;
      final body = Map<String, dynamic>.from(map['body'] as Map);
      try {
        reply.send({'ok': true, 'result': await store.handleRequest(body)});
      } catch (e) {
        reply.send({'ok': false, 'error': '$e'});
      }
    });
  }

  void dispose() {
    ui.IsolateNameServer.removePortNameMapping('$_namespace.$slot');
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    _port.close();
  }
}
