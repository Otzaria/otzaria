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
    launcher.markPageClosed(_kPid, instanceId: 'first');
    launcher.markPageClosed(_kPid, instanceId: 'second');
    dispatcher.unregisterController(_kPid, instanceId: 'first');
    dispatcher.unregisterController(_kPid, instanceId: 'second');
    dispatcher.repositoryForTesting = PluginRegistryRepository();
    AppWindowKeys.resetForTest();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

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

    launcher.markPageReady(_kPid, instanceId: 'second');
    await settle();

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
}
