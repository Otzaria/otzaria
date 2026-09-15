import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
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
  late UserStateDatabase database;
  late WindowSessionStore sessions;

  setUp(() async {
    WindowBus.namespace = _namespace;
    WindowRole.isSecondary = false;
    // ⚠️ בלי זה כל הסוויטה בודקת את מסלול חלון-יחיד. `windowCount` ו-
    // `closeSelf` מגודרים ב-`MultiWindowService.canOpenWindows`, שהוא
    // `Platform.isWindows` — כלומר על ubuntu (ה-CI) `windowCount` מחזיר
    // 1 בלי לגעת בערוץ המדומה, `_isLastWindowClosing` עונה "כן", והרצף
    // פונה לכיבוי התהליך במקום לסגירת החלון הבודד. הבדיקות היו ירוקות
    // על מכונת המפתח ואדומות ב-CI, ומה שהן מתארות אינו תלוי פלטפורמה:
    // ה-runner שמעבר לערוץ מדומה כאן ממילא.
    MultiWindowService.debugSupportedOverride = true;
    runner = _FakeRunner()..install();
    tmp = Directory.systemTemp.createTempSync('otzaria_secclose_');
    database = UserStateDatabase.openAt('${tmp.path}/user_state.db');
    await database.database;
    sessions = WindowSessionStore(database: database);
    TabsRepository.debugSessions = sessions;
  });

  tearDown(() async {
    TabsRepository.debugSessions = null;
    database.close();
    runner.uninstall();
    MultiWindowService.debugSupportedOverride = null;
    WindowRole.isSecondary = false;
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    WindowBus.namespace = 'otzaria.window';
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
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
    // כרטיסיות שמורות בסשן של החלון הזה.
    await TabsRepository().saveTabs(const [], 0);
    final slot = WindowBus.instance.slot!;
    expect(await sessions.load(slot), isNotNull);

    await AppWindowListener().handleWindowClose();

    expect(flushed, isTrue, reason: 'הכתיבות התלויות נשטפו');
    expect(runner.closeSelfCalls, 1, reason: 'רק החלון הזה נסגר');
    expect(
      await sessions.load(slot),
      isNull,
      reason:
          'הסשן נמחק — בלעדיו `adoptOrphanWindowSessions` היה מחזיר '
          'בהפעלה הבאה כרטיסיות שהמשתמש סגר במכוון',
    );
  });

  test('החלון הראשון שאינו האחרון: הסשן שלו נמחק כמו של כל חלון', () async {
    // ⚠️ ההצדקה זהה לזו של חלון משני — הוא נסגר במכוון בעוד אחרים
    // פתוחים — ולכן הכרטיסיות שלו אינן "פתוחות" יותר.
    WindowBus.instance.register();
    final slot = WindowBus.instance.slot!;
    await TabsRepository().saveTabs(const [], 0);

    await AppWindowListener().handleWindowClose();

    expect(runner.closeSelfCalls, 1);
    expect(await sessions.load(slot), isNull);
  });
}

/// ה-runner המדומה. `windowCount` מחזיר שניים — כלומר "אינך האחרון".
class _FakeRunner {
  int closeSelfCalls = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MultiWindowService.channel, (call) async {
          switch (call.method) {
            case 'windowCount':
              return {'count': 2, 'max': 4, 'engines': 2};
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

/// החלון הראשון של התהליך — תופס משבצת ואת כינוי המארח, ועונה לכל בקשה.
class _FakeOwner {
  _FakeOwner(this.slot);

  final int slot;
  late final ReceivePort _port;

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
    _port.listen((message) {
      final map = message as Map;
      (map['reply'] as SendPort).send({'ok': true, 'result': null});
    });
  }

  void dispose() {
    ui.IsolateNameServer.removePortNameMapping('$_namespace.$slot');
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    _port.close();
  }
}
