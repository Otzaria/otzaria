import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';

class _FakeRegistryRepo extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;
}

class _RecordingController extends Fake implements InAppWebViewController {
  final List<String> jsCalls = [];

  /// משהה את הקריאה הראשונה — חושף מסירות מקביליות שעוקפות את הסדר.
  Duration? firstCallDelay;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    final delay = firstCallDelay;
    firstCallDelay = null;
    if (delay != null) await Future<void>.delayed(delay);
    jsCalls.add(source);
    return null;
  }
}

const _kPid = 'launcher.test.plugin';

void main() {
  final launcher = PluginPageLauncher.instance;
  final dispatcher = PluginRuntimeDispatcher.instance;
  late _RecordingController controller;
  late List<String> navigations;

  setUp(() {
    dispatcher.repositoryForTesting = _FakeRegistryRepo();
    controller = _RecordingController();
    dispatcher.registerController(_kPid, controller);
    navigations = [];
    launcher.navigator = navigations.add;
  });

  tearDown(() {
    launcher.markPageClosed(_kPid);
    launcher.navigator = null;
    dispatcher.unregisterController(_kPid);
    dispatcher.repositoryForTesting = PluginRegistryRepository();
  });

  Future<void> pumpMicrotasks() => Future<void>.delayed(Duration.zero);

  test(
    'דף מוכן בחלון אחר אינו גונב פתיחה שממתינה ל-boot בחלון המקור',
    () async {
      final aKeys = AppWindowKeys();
      final bKeys = AppWindowKeys();
      final bController = _RecordingController();
      final aNavigations = <String>[];
      final bNavigations = <String>[];
      launcher.register(aKeys, aNavigations.add);
      launcher.register(bKeys, bNavigations.add);
      dispatcher.registerController(
        _kPid,
        bController,
        instanceId: 'b',
        viewId: 2,
      );
      launcher.markPageReady(_kPid, viewId: 1);
      launcher.open(
        _kPid,
        topic: 'from.b',
        payload: const {'from': 'b'},
        viewId: 2,
        windowKeys: bKeys,
      );
      await pumpMicrotasks();
      expect(bNavigations, [_kPid]);
      expect(aNavigations, isEmpty);
      expect(controller.jsCalls, isEmpty);
      expect(bController.jsCalls, isEmpty);
      AppWindowKeys.activate(aKeys);
      launcher.markPageReady(_kPid, instanceId: 'b', viewId: 2);
      await pumpMicrotasks();
      expect(controller.jsCalls, isEmpty);
      expect(bController.jsCalls.single, contains('from.b'));
      launcher.markPageClosed(_kPid, instanceId: 'b');
      dispatcher.unregisterController(_kPid, instanceId: 'b');
      launcher.unregister(aKeys, aNavigations.add);
      launcher.unregister(bKeys, bNavigations.add);
      AppWindowKeys.resetForTest();
    },
  );

  test('סגירת דף לפני boot מנקה רק את ההמתנה בחלון שלו', () async {
    final bController = _RecordingController();
    dispatcher.registerController(
      _kPid,
      bController,
      instanceId: 'b',
      viewId: 2,
    );
    launcher.markPageReady(_kPid, viewId: 1);
    launcher.open(_kPid, topic: 'cancelled.b', viewId: 2);
    expect(launcher.hasPendingFor(_kPid), isTrue);
    launcher.markPageClosed(_kPid, instanceId: 'b', viewId: 2);
    expect(launcher.hasPendingFor(_kPid), isFalse);
    launcher.markPageReady(_kPid, instanceId: 'b', viewId: 2);
    launcher.open(_kPid, topic: 'still.a', viewId: 1);
    await pumpMicrotasks();
    expect(bController.jsCalls, isEmpty);
    expect(controller.jsCalls.single, contains('still.a'));
    launcher.markPageClosed(_kPid, instanceId: 'b', viewId: 2);
    dispatcher.unregisterController(_kPid, instanceId: 'b');
  });

  test('פירוק חלון לפני בניית דף מנקה את האירועים הממתינים שלו', () async {
    launcher.open(_kPid, topic: 'cancelled.view', viewId: 2);
    launcher.forgetWindow(2);
    expect(launcher.hasPendingFor(_kPid), isFalse);
  });

  test('אירוע מאוחר מחלון שנסגר אינו נרשם שוב כממתין', () {
    final closed = AppWindowKeys();
    launcher.open(_kPid, topic: 'closed.window', viewId: 2, windowKeys: closed);
    expect(launcher.hasPendingFor(_kPid), isFalse);
    expect(navigations, isEmpty);
  });

  test('open ללא topic — רק מנווט, בלי אירוע', () async {
    launcher.open(_kPid);
    await pumpMicrotasks();

    expect(navigations, [_kPid]);
    expect(controller.jsCalls, isEmpty);
  });

  test('open לפני שהדף מוכן — האירוע ממתין ונמסר ב-markPageReady', () async {
    launcher.open(_kPid, topic: 'plugin.page_opened', payload: {'param': 'x'});
    await pumpMicrotasks();

    expect(navigations, [_kPid]);
    expect(controller.jsCalls, isEmpty);

    launcher.markPageReady(_kPid);
    await pumpMicrotasks();

    expect(controller.jsCalls, hasLength(1));
    expect(controller.jsCalls.single, contains('plugin.page_opened'));
    expect(controller.jsCalls.single, contains('"param":"x"'));
  });

  test('open כשהדף כבר מוכן — האירוע נמסר מיד', () async {
    launcher.markPageReady(_kPid);
    launcher.open(_kPid, topic: 'plugin.page_opened', payload: {'param': 1});
    await pumpMicrotasks();

    expect(navigations, [_kPid]);
    expect(controller.jsCalls, hasLength(1));
    expect(controller.jsCalls.single, contains('"param":1'));
  });

  test('markPageReady חוזר אינו מוסר את אותו אירוע פעמיים', () async {
    launcher.open(_kPid, topic: 'plugin.page_opened', payload: {'param': 'x'});
    launcher.markPageReady(_kPid);
    launcher.markPageReady(_kPid);
    await pumpMicrotasks();

    expect(controller.jsCalls, hasLength(1));
  });

  test(
    'שני אירועים לפני טעינת הדף — שניהם נמסרים בסדרם גם כשהראשון איטי',
    () async {
      controller.firstCallDelay = const Duration(milliseconds: 20);
      launcher.open(
        _kPid,
        topic: 'plugin.page_opened',
        payload: {'param': 'a'},
      );
      launcher.open(
        _kPid,
        topic: 'reader.context_menu_item_clicked',
        payload: {'param': 'b'},
      );
      await pumpMicrotasks();
      expect(controller.jsCalls, isEmpty);

      launcher.markPageReady(_kPid);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(controller.jsCalls, hasLength(2));
      expect(controller.jsCalls[0], contains('plugin.page_opened'));
      expect(controller.jsCalls[0], contains('"param":"a"'));
      expect(
        controller.jsCalls[1],
        contains('reader.context_menu_item_clicked'),
      );
      expect(controller.jsCalls[1], contains('"param":"b"'));
    },
  );

  test('אירוע שמגיע בזמן ריקון הממתינים נמסר אחריהם, לא לפניהם', () async {
    controller.firstCallDelay = const Duration(milliseconds: 20);
    launcher.open(_kPid, topic: 'plugin.page_opened', payload: {'param': 'a'});

    launcher.markPageReady(_kPid);
    // הדף כבר מוכן — האירוע הזה נמסר במסלול המיידי, בזמן שהראשון עוד באוויר.
    launcher.open(_kPid, topic: 'plugin.page_opened', payload: {'param': 'b'});
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(controller.jsCalls, hasLength(2));
    expect(controller.jsCalls[0], contains('"param":"a"'));
    expect(controller.jsCalls[1], contains('"param":"b"'));
  });

  test('markPageClosed מנקה אירוע ממתין — לא יימסר בפתיחה עתידית', () async {
    launcher.open(_kPid, topic: 'plugin.page_opened', payload: {'param': 'x'});
    launcher.markPageClosed(_kPid);

    launcher.markPageReady(_kPid);
    await pumpMicrotasks();

    expect(controller.jsCalls, isEmpty);
  });

  test('אחרי markPageClosed — אירוע חדש חוזר להמתין לטעינת הדף', () async {
    launcher.markPageReady(_kPid);
    launcher.markPageClosed(_kPid);

    launcher.open(_kPid, topic: 'plugin.page_opened', payload: {'param': 2});
    await pumpMicrotasks();
    expect(controller.jsCalls, isEmpty);

    launcher.markPageReady(_kPid);
    await pumpMicrotasks();
    expect(controller.jsCalls, hasLength(1));
  });

  test('אירוע ממתין נמסר לדף שהודיע מוכנות — לא למופע אחר', () async {
    final second = _RecordingController();
    dispatcher.registerController(_kPid, second, instanceId: 'tab-2');
    addTearDown(() {
      launcher.markPageClosed(_kPid, instanceId: 'tab-2');
      dispatcher.unregisterController(_kPid, instanceId: 'tab-2');
    });

    launcher.open(_kPid, topic: 'plugin.page_opened', payload: {'param': 'x'});
    await pumpMicrotasks();

    launcher.markPageReady(_kPid, instanceId: 'tab-2');
    await pumpMicrotasks();

    expect(second.jsCalls, hasLength(1));
    expect(controller.jsCalls, isEmpty);
  });

  test('סגירת מופע אחד לא מוחקת את מצב התוסף כשנשאר דף מוכן', () async {
    final second = _RecordingController();
    dispatcher.registerController(_kPid, second, instanceId: 'tab-2');

    launcher.markPageReady(_kPid);
    launcher.markPageReady(_kPid, instanceId: 'tab-2');
    launcher.markPageClosed(_kPid, instanceId: 'tab-2');
    dispatcher.unregisterController(_kPid, instanceId: 'tab-2');

    // הדף הראשי עדיין מוכן — אירוע חדש נמסר מיד, לא ממתין לטעינה.
    launcher.open(_kPid, topic: 'plugin.page_opened', payload: {'param': 1});
    await pumpMicrotasks();
    expect(controller.jsCalls, hasLength(1));
  });
}
