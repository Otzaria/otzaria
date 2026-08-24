import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/declarative/services/declarative_host_action_executor.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';

void main() {
  late _FakeRegistryRepository repository;
  late PluginConditionEvaluator evaluator;
  late PluginKvStorageWriter writer;

  setUp(() {
    repository = _FakeRegistryRepository();
    evaluator = PluginConditionEvaluator.forTesting();
    writer = PluginKvStorageWriter(
      repository: repository,
      conditions: evaluator,
    );
  });

  test('הכתיבה נעולה ל-namespace default ונשמרת כ-JSON', () async {
    await writer.set('my.plugin', 'flag', true);

    expect(repository.values['my.plugin/default/flag'], 'true');

    await writer.remove('my.plugin', 'flag');

    expect(repository.values, isEmpty);
    expect(repository.namespaces, ['default', 'default']);
  });

  test('כתיבה למפתח במעקב מעדכנת תנאי when ומודיעה למאזינים', () async {
    await evaluator.registerStorageKeys('my.plugin', {'flag'}, repository);
    final condition = PluginWhenCondition.fromJson({
      'storage': {'key': 'flag', 'equals': true},
    });
    var notified = 0;
    evaluator.addListener(() => notified++);

    expect(evaluator.evaluate('my.plugin', condition), isFalse);

    await writer.set('my.plugin', 'flag', true);

    expect(evaluator.evaluate('my.plugin', condition), isTrue);
    expect(notified, 1);

    await writer.remove('my.plugin', 'flag');

    expect(evaluator.evaluate('my.plugin', condition), isFalse);
    expect(notified, 2);
  });

  test('כתיבה למפתח שאינו במעקב אינה מפעילה מאזינים', () async {
    await evaluator.registerStorageKeys('my.plugin', {'other'}, repository);
    var notified = 0;
    evaluator.addListener(() => notified++);

    await writer.set('my.plugin', 'flag', 1);

    expect(notified, 0);
    expect(repository.values['my.plugin/default/flag'], '1');
  });
}

class _FakeRegistryRepository extends PluginRegistryRepository {
  final values = <String, String>{};
  final namespaces = <String>[];

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async {
    return values['$pluginId/$namespace/$key'];
  }

  @override
  Future<Map<String, String>> getKVMany(
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) async => {
    for (final key in keys)
      if (values['$pluginId/$namespace/$key'] != null)
        key: values['$pluginId/$namespace/$key']!,
  };

  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async {
    namespaces.add(namespace);
    values['$pluginId/$namespace/$key'] = valueJson;
  }

  @override
  Future<void> removeKV(String pluginId, String namespace, String key) async {
    namespaces.add(namespace);
    values.remove('$pluginId/$namespace/$key');
  }
}
