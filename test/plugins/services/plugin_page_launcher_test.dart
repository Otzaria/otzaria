import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

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
}
