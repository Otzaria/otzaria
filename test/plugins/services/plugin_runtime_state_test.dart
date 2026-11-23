import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_runtime_state.dart';

void main() {
  group('PluginRuntimeInstance', () {
    late PluginRuntimeInstance instance;

    setUp(() {
      instance = PluginRuntimeInstance(
        pluginId: 'test-plugin',
        instanceId: 'foreground',
      );
    });

    test(
      'resetEventOptions clears page-scoped options and readiness',
      () async {
        instance.ready = true;
        instance.rawDivineNamesTopics.add('reader.getText');
        instance.eventOptionsGeneration = 7;

        instance.resetEventOptions();
        await instance.lifecycleLock;

        expect(instance.rawDivineNamesTopics, isEmpty);
        expect(instance.eventOptionsGeneration, 8);
        expect(instance.ready, isFalse);
      },
    );

    test('clearQueue removes coalesced events and one-shot count', () {
      instance.queued['theme.changed'] = const PluginQueuedEvent(
        'theme.changed',
        '{}',
        targeted: false,
      );
      instance.queuedOneShots = 3;

      instance.clearQueue();

      expect(instance.queued, isEmpty);
      expect(instance.queuedOneShots, 0);
    });

    test('background identity is derived from the instance id', () {
      expect(instance.isBackground, isFalse);
      final background = PluginRuntimeInstance(
        pluginId: 'test-plugin',
        instanceId: 'background',
      );
      expect(background.isBackground, isTrue);
    });
  });

  test('window visibility distinguishes hidden and foreground states', () {
    final visibility = PluginWindowVisibility();

    expect(visibility.isForeground, isTrue);
    expect(visibility.showsPlugins, isFalse);

    visibility.minimized = true;

    expect(visibility.isForeground, isFalse);
    expect(visibility.showsPlugins, isFalse);
  });
}
