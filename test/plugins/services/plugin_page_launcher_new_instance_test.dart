import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

class _FakeRegistryRepo extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;
}

class _RecordingController extends Fake implements InAppWebViewController {
  final List<String> jsCalls = [];

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    jsCalls.add(source);
    return null;
  }
}

const _kPid = 'launcher.new.instance.plugin';

void main() {
  final launcher = PluginPageLauncher.instance;
  final dispatcher = PluginRuntimeDispatcher.instance;
  late _RecordingController first;
  late _RecordingController second;
  late AppWindowKeys keys;

  setUp(() {
    dispatcher.repositoryForTesting = _FakeRegistryRepo();
    first = _RecordingController();
    second = _RecordingController();
    dispatcher.registerController(_kPid, first, instanceId: 'first');
    dispatcher.registerController(_kPid, second, instanceId: 'second');
    keys = AppWindowKeys();
  });

  tearDown(() {
    launcher.clock = DateTime.now;
    launcher.markPageClosed(_kPid, instanceId: 'first');
    launcher.markPageClosed(_kPid, instanceId: 'second');
    dispatcher.unregisterController(_kPid, instanceId: 'first');
    dispatcher.unregisterController(_kPid, instanceId: 'second');
    dispatcher.repositoryForTesting = PluginRegistryRepository();
    AppWindowKeys.resetForTest();
  });

  /// ממתין (עד שתי שניות) עד שהתנאי מתקיים, במקום השהיה קבועה שעלולה להיות
  /// קצרה מדי ב-CI איטי.
  Future<void> settle(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('האירוע נמסר רק למופע החדש, גם כשמופע קיים כבר מוכן', () async {
    final opened = <String>[];
    String? opener(String pluginId) {
      opened.add(pluginId);
      return 'second';
    }

    launcher.registerInstanceOpener(keys, opener);
    launcher.markPageReady(_kPid, instanceId: 'first');

    final id = launcher.openNewInstance(
      _kPid,
      topic: 'plugin.page_opened',
      payload: const {'param': 7},
      windowKeys: keys,
    );

    expect(id, 'second');
    expect(opened, [_kPid]);
    expect(launcher.hasPendingFor(_kPid), isTrue);

    launcher.markPageReady(_kPid, instanceId: 'second', isPrimary: false);
    await settle(() => second.jsCalls.isNotEmpty);

    expect(launcher.hasPendingFor(_kPid), isFalse);
    expect(first.jsCalls, isEmpty);
    expect(second.jsCalls.single, contains('plugin.page_opened'));
    expect(second.jsCalls.single, contains('"param":7'));
    launcher.unregisterInstanceOpener(keys, opener);
  });

  test('פותח שדוחה (כלי לא זמין) — אין מופע ואין אירוע ממתין', () {
    String? refuse(String pluginId) => null;
    launcher.registerInstanceOpener(keys, refuse);

    expect(
      launcher.openNewInstance(
        _kPid,
        topic: 'plugin.page_opened',
        windowKeys: keys,
      ),
      isNull,
    );
    expect(launcher.hasPendingFor(_kPid), isFalse);
    launcher.unregisterInstanceOpener(keys, refuse);
  });

  test('חלון בלי פותח רשום — null', () {
    expect(
      launcher.openNewInstance(
        _kPid,
        topic: 'plugin.page_opened',
        windowKeys: keys,
      ),
      isNull,
    );
  });

  test('סגירת הכרטיסיה לפני ה-boot מנקה את האירוע הממתין', () {
    String? opener(String pluginId) => 'second';
    launcher.registerInstanceOpener(keys, opener);

    launcher.openNewInstance(
      _kPid,
      topic: 'plugin.page_opened',
      windowKeys: keys,
    );
    expect(launcher.hasPendingFor(_kPid), isTrue);

    launcher.markPageClosed(_kPid, instanceId: 'second');
    expect(launcher.hasPendingFor(_kPid), isFalse);
    launcher.unregisterInstanceOpener(keys, opener);
  });

  test('אירוע כללי שממתין לדף הראשי אינו נמסר למופע שנפתח', () async {
    String? opener(String pluginId) => 'second';
    void navigate(String pluginId) {}
    launcher.registerInstanceOpener(keys, opener);
    launcher.register(keys, navigate);

    // אין דף מוכן, ולכן openSelf רגיל נכנס לתור הכללי של התוסף.
    launcher.open(
      _kPid,
      topic: 'plugin.page_opened',
      payload: const {'param': 'primary'},
      windowKeys: keys,
    );
    launcher.openNewInstance(
      _kPid,
      topic: 'plugin.page_opened',
      payload: const {'param': 'spawned'},
      windowKeys: keys,
    );

    launcher.markPageReady(_kPid, instanceId: 'second', isPrimary: false);
    await settle(() => second.jsCalls.isNotEmpty);

    expect(second.jsCalls.single, contains('"param":"spawned"'));
    expect(
      launcher.hasPendingFor(_kPid),
      isTrue,
      reason: 'האירוע הכללי עדיין ממתין לדף הראשי',
    );

    launcher.markPageReady(_kPid, instanceId: 'first');
    await settle(() => first.jsCalls.isNotEmpty);

    expect(first.jsCalls.single, contains('"param":"primary"'));
    expect(second.jsCalls, hasLength(1));
    expect(launcher.hasPendingFor(_kPid), isFalse);
    launcher.unregisterInstanceOpener(keys, opener);
    launcher.unregister(keys, navigate);
  });

  test('שני מופעים חדשים רצופים — כל אחד מקבל רק את ה-param שלו', () async {
    final ids = ['first', 'second'];
    String? opener(String pluginId) => ids.removeAt(0);
    launcher.registerInstanceOpener(keys, opener);

    for (final param in ['a', 'b']) {
      launcher.openNewInstance(
        _kPid,
        topic: 'plugin.page_opened',
        payload: {'param': param},
        windowKeys: keys,
      );
    }
    launcher.markPageReady(_kPid, instanceId: 'second', isPrimary: false);
    launcher.markPageReady(_kPid, instanceId: 'first');
    await settle(
      () => first.jsCalls.isNotEmpty && second.jsCalls.isNotEmpty,
    );

    expect(first.jsCalls.single, contains('"param":"a"'));
    expect(second.jsCalls.single, contains('"param":"b"'));
    expect(launcher.hasPendingFor(_kPid), isFalse);
    launcher.unregisterInstanceOpener(keys, opener);
  });

  test('סגירת מופע אחד לפני ה-boot אינה מוחקת את האירוע של מופע אחר', () {
    final ids = ['first', 'second'];
    String? opener(String pluginId) => ids.removeAt(0);
    launcher.registerInstanceOpener(keys, opener);
    for (var i = 0; i < 2; i++) {
      launcher.openNewInstance(
        _kPid,
        topic: 'plugin.page_opened',
        windowKeys: keys,
      );
    }

    launcher.markPageClosed(_kPid, instanceId: 'first');

    expect(launcher.hasPendingFor(_kPid), isTrue);
    launcher.markPageClosed(_kPid, instanceId: 'second');
    expect(launcher.hasPendingFor(_kPid), isFalse);
    launcher.unregisterInstanceOpener(keys, opener);
  });

  test('טעינה חוזרת של מופע אינה מוסרת את האירוע שוב', () async {
    String? opener(String pluginId) => 'second';
    launcher.registerInstanceOpener(keys, opener);
    launcher.openNewInstance(
      _kPid,
      topic: 'plugin.page_opened',
      windowKeys: keys,
    );

    launcher.markPageReady(_kPid, instanceId: 'second', isPrimary: false);
    await settle(() => second.jsCalls.isNotEmpty);
    launcher.markPageReady(_kPid, instanceId: 'second', isPrimary: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(second.jsCalls, hasLength(1));
    launcher.unregisterInstanceOpener(keys, opener);
  });

  test('סגירת החלון לפני ה-boot מנקה את האירוע הממתין של המופע', () {
    String? opener(String pluginId) => 'second';
    launcher.registerInstanceOpener(keys, opener);
    launcher.openNewInstance(
      _kPid,
      topic: 'plugin.page_opened',
      viewId: 42,
      windowKeys: keys,
    );
    expect(launcher.hasPendingFor(_kPid), isTrue);

    launcher.forgetWindow(7);
    expect(launcher.hasPendingFor(_kPid), isTrue, reason: 'חלון אחר');

    launcher.forgetWindow(42);
    expect(launcher.hasPendingFor(_kPid), isFalse);
    launcher.unregisterInstanceOpener(keys, opener);
  });

  group('פתיחה רגילה מכוונת למופע הראשי בלבד', () {
    late List<String> navigations;
    late void Function(String) navigate;

    setUp(() {
      navigations = [];
      navigate = navigations.add;
      launcher.register(keys, navigate);
    });

    tearDown(() => launcher.unregister(keys, navigate));

    test('מופע נוסף שעלה ראשון אינו מקבל את האירוע', () async {
      launcher.markPageReady(_kPid, instanceId: 'second', isPrimary: false);
      launcher.markPageReady(_kPid, instanceId: 'first');

      launcher.open(
        _kPid,
        topic: 'contextMenu.itemClicked',
        payload: const {'param': 'menu'},
        windowKeys: keys,
      );
      await settle(() => first.jsCalls.isNotEmpty);

      expect(navigations, [_kPid]);
      expect(first.jsCalls.single, contains('"param":"menu"'));
      expect(second.jsCalls, isEmpty);
    });

    test('רק מופע נוסף מוכן — האירוע ממתין לראשי ולא נמסר לנוסף', () async {
      launcher.markPageReady(_kPid, instanceId: 'second', isPrimary: false);

      launcher.open(
        _kPid,
        topic: 'contextMenu.itemClicked',
        payload: const {'param': 'menu'},
        windowKeys: keys,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(navigations, [_kPid], reason: 'הכרטיסיה הראשית נפתחת או ממוקדת');
      expect(second.jsCalls, isEmpty);
      expect(launcher.hasPendingFor(_kPid), isTrue);

      launcher.markPageReady(_kPid, instanceId: 'first');
      await settle(() => first.jsCalls.isNotEmpty);

      expect(first.jsCalls.single, contains('"param":"menu"'));
      expect(second.jsCalls, isEmpty);
      expect(launcher.hasPendingFor(_kPid), isFalse);
    });

    test(
      'מופע נוסף שנטען מחדש (בלי אירוע ממוקד) אינו צורך אירוע כללי',
      () async {
        launcher.open(_kPid, topic: 'general', windowKeys: keys);

        launcher.markPageReady(_kPid, instanceId: 'second', isPrimary: false);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(second.jsCalls, isEmpty);
        expect(launcher.hasPendingFor(_kPid), isTrue);
      },
    );

    test('אחרי סגירת המופע הנוסף הראשי נשאר היעד', () async {
      launcher.markPageReady(_kPid, instanceId: 'first');
      launcher.markPageReady(_kPid, instanceId: 'second', isPrimary: false);
      launcher.markPageClosed(_kPid, instanceId: 'second');

      launcher.open(_kPid, topic: 'after.close', windowKeys: keys);
      await settle(() => first.jsCalls.isNotEmpty);

      expect(first.jsCalls.single, contains('after.close'));
    });
  });

  group('תפוגת אירוע ממוקד שמופע לא עלה עבורו', () {
    test('אחרי הזמן שנקבע האירוע נזנח ואינו חוסם פינוי', () {
      final start = DateTime(2026, 1, 1);
      launcher.clock = () => start;
      String? opener(String pluginId) => 'second';
      launcher.registerInstanceOpener(keys, opener);
      launcher.openNewInstance(
        _kPid,
        topic: 'plugin.page_opened',
        windowKeys: keys,
      );

      launcher.clock = () => start.add(
        PluginPageLauncher.pendingInstanceEventTtl - const Duration(seconds: 1),
      );
      expect(launcher.hasPendingFor(_kPid), isTrue);

      launcher.clock = () => start.add(
        PluginPageLauncher.pendingInstanceEventTtl + const Duration(seconds: 1),
      );
      expect(launcher.hasPendingFor(_kPid), isFalse);
      launcher.unregisterInstanceOpener(keys, opener);
    });

    test('מופע שעולה אחרי התפוגה אינו מקבל את האירוע הישן', () async {
      final start = DateTime(2026, 1, 1);
      launcher.clock = () => start;
      String? opener(String pluginId) => 'second';
      launcher.registerInstanceOpener(keys, opener);
      launcher.openNewInstance(
        _kPid,
        topic: 'plugin.page_opened',
        windowKeys: keys,
      );

      launcher.clock = () => start.add(const Duration(minutes: 5));
      launcher.hasPendingFor(_kPid);
      launcher.markPageReady(_kPid, instanceId: 'second', isPrimary: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(second.jsCalls, isEmpty);
      launcher.unregisterInstanceOpener(keys, opener);
    });
  });
}
