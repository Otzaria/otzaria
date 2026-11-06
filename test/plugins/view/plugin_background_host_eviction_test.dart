import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/plugins/view/plugin_background_host.dart';

void main() {
  late PluginLazyActivationService lazy;

  setUp(() {
    lazy = PluginLazyActivationService.forTesting();
  });

  String? pick(
    List<String> ids, {
    Set<String> keepAlive = const {},
  }) => pickOnDemandEvictionCandidate(
    onDemandIds: ids,
    isKeepAlive: keepAlive.contains,
    lazyActivation: lazy,
  );

  test('מתחת לתקרה אין פינוי', () {
    expect(pick(['p1', 'p2', 'p3']), isNull);
  });

  test('בתקרה מפונה הוותיק ביותר', () {
    expect(pick(['p1', 'p2', 'p3', 'p4']), 'p1');
  });

  test('מופע עסוק ב-RPC אינו מפונה', () {
    lazy.beginWork('p1');
    expect(pick(['p1', 'p2', 'p3', 'p4']), 'p2');
  });

  test('סיום ה-RPC מחזיר את המופע לרשימת המועמדים', () {
    final finish = lazy.beginWork('p1');
    finish();
    expect(pick(['p1', 'p2', 'p3', 'p4']), 'p1');
  });

  test('RPC מקונן — רק הסיום האחרון משחרר', () {
    final finishFirst = lazy.beginWork('p1');
    lazy.beginWork('p1');
    finishFirst();
    expect(pick(['p1', 'p2', 'p3', 'p4']), 'p2');
  });

  test('keepAlive ועסוק יחד — מדלגים על שניהם', () {
    lazy.beginWork('p2');
    expect(pick(['p1', 'p2', 'p3', 'p4'], keepAlive: {'p1'}), 'p3');
  });

  test('כשכל המועמדים חסומים אין פינוי (התקרה רכה)', () {
    for (final id in ['p1', 'p2', 'p3', 'p4']) {
      lazy.beginWork(id);
    }
    expect(pick(['p1', 'p2', 'p3', 'p4']), isNull);
  });

  test('טיוטה במופע הרקע מוגנת מפינוי LRU עד שנשמרה', () {
    const key = (pluginId: 'p1', instanceId: PluginInstanceIds.background);
    final unsaved = PluginUnsavedChangesRegistry.instance;
    unsaved.set(key, hasChanges: true);
    try {
      expect(pick(['p1', 'p2', 'p3', 'p4']), 'p2');
      unsaved.removeInstance(key);
      expect(pick(['p1', 'p2', 'p3', 'p4']), 'p1');
    } finally {
      unsaved.removeInstance(key);
    }
  });

  test('סשן חיוני מוגן גם כשאין RPC פתוח', () {
    lazy = PluginLazyActivationService.forTesting(
      hasEssentialState: (pluginId) => pluginId == 'p1',
    );
    expect(pick(['p1', 'p2', 'p3', 'p4']), 'p2');
  });
}
