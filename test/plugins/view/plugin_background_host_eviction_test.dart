import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
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
    lazy.beginWork('p1');
    lazy.endWork('p1');
    expect(pick(['p1', 'p2', 'p3', 'p4']), 'p1');
  });

  test('RPC מקונן — רק ה-endWork האחרון משחרר', () {
    lazy.beginWork('p1');
    lazy.beginWork('p1');
    lazy.endWork('p1');
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
}
