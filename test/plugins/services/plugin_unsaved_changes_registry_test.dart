import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';

void main() {
  const key = (pluginId: 'p.editor', instanceId: 'tab-1');
  const other = (pluginId: 'p.editor', instanceId: 'tab-2');

  late PluginUnsavedChangesRegistry registry;
  late int notifications;

  setUp(() {
    registry = PluginUnsavedChangesRegistry.forTesting();
    notifications = 0;
    registry.addListener(() => notifications++);
  });

  test('סימון ומחיקה הם לכל מופע בנפרד', () {
    registry.set(key, hasChanges: true);

    expect(registry.hasUnsavedChanges(key), isTrue);
    expect(registry.hasUnsavedChanges(other), isFalse);

    registry.set(key, hasChanges: false);
    expect(registry.hasUnsavedChanges(key), isFalse);
  });

  test('ההודעה נשמרת, נגזמת מרווחים ונחתכת לאורך המרבי', () {
    registry.set(key, hasChanges: true, message: '  הטיוטה תאבד  ');
    expect(registry.messageFor(key), 'הטיוטה תאבד');

    final long = 'א' * (PluginUnsavedChangesRegistry.maxMessageLength + 50);
    registry.set(key, hasChanges: true, message: long);
    expect(
      registry.messageFor(key)!.length,
      PluginUnsavedChangesRegistry.maxMessageLength,
    );

    registry.set(key, hasChanges: true, message: '   ');
    expect(registry.hasUnsavedChanges(key), isTrue);
    expect(registry.messageFor(key), isNull);
  });

  test('מודיע למאזינים רק על שינוי אמיתי', () {
    registry.set(key, hasChanges: true);
    registry.set(key, hasChanges: true);
    expect(notifications, 1);

    registry.set(key, hasChanges: true, message: 'חדש');
    expect(notifications, 2);

    registry.removeInstance(key);
    registry.removeInstance(key);
    expect(notifications, 3);
  });

  test('removeInstance מנקה גם מופע שנרשם בלי הודעה', () {
    registry.set(key, hasChanges: true);
    registry.removeInstance(key);
    expect(registry.hasUnsavedChanges(key), isFalse);
  });
}
