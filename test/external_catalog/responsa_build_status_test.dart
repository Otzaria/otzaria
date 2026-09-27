import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_build_service.dart';
import 'package:otzaria/external_catalog/responsa/view/responsa_build_progress_view.dart';

/// מה שמוצג בזמן בנייה — ובעיקר מה **אינו** מוצג כשאין לו בסיס.
void main() {
  ResponsaBuildProgress scanning(int nodes, {int done = 0, int total = 0}) =>
      ResponsaBuildProgress(
        stage: ResponsaBuildStage.scanning,
        scannedNodes: nodes,
        sectionsDone: done,
        sectionsTotal: total,
      );

  test('עם מכנה מהבנייה הקודמת — X מתוך Y, אחוז, והערכת זמן', () {
    final status = ResponsaBuildStatus.of(
      scanning(250000),
      expectedNodes: 1000000,
      scanElapsed: const Duration(minutes: 1),
    );
    expect(status.headline.template, 'נסרקו {nodes} מתוך כ-{total} רשומות');
    expect(status.headline.args, {'nodes': '250,000', 'total': '1,000,000'});
    expect(status.fraction, 0.25);
    // רבע בדקה — שלוש דקות נותרו.
    expect(status.remaining, const Duration(minutes: 3));
    expect(
      status.detail(const Duration(minutes: 1, seconds: 20)).args,
      {'percent': 25, 'elapsed': '1:20', 'remaining': '3:00'},
    );
  });

  test('בשניות הראשונות אין הערכת זמן — הקצב עוד לא התייצב', () {
    final status = ResponsaBuildStatus.of(
      scanning(2000),
      expectedNodes: 1000000,
      scanElapsed: const Duration(seconds: 3),
    );
    expect(status.remaining, isNull);
    expect(
      status.detail(const Duration(seconds: 5)).template,
      '{percent}% · עברו {elapsed}',
    );
  });

  test('בין המכנה ל-5% מעליו — בלי "נותרו כ-0:00"', () {
    final status = ResponsaBuildStatus.of(
      scanning(1020000),
      expectedNodes: 1000000,
      scanElapsed: const Duration(minutes: 5),
    );
    expect(status.fraction, 0.99);
    expect(status.remaining, isNull);
  });

  test('הסריקה עברה את המכנה — הוא כבר אינו מכנה', () {
    final status = ResponsaBuildStatus.of(
      scanning(1200000, done: 3, total: 20),
      expectedNodes: 1000000,
      scanElapsed: const Duration(minutes: 5),
    );
    expect(status.headline.template, contains('קטגוריה'));
    expect(status.remaining, isNull);
  });

  test('בנייה ראשונה — הקטגוריות הן ההתקדמות, בלי הערכת זמן', () {
    final status = ResponsaBuildStatus.of(
      scanning(40000, done: 5, total: 20),
      scanElapsed: const Duration(minutes: 2),
    );
    expect(status.headline.args, {
      'nodes': '40,000',
      'current': 6,
      'sections': 20,
    });
    expect(status.fraction, 0.25);
    expect(status.remaining, isNull);
  });

  test('אחרי הקטגוריה האחרונה — לא "21 מתוך 20"', () {
    final status = ResponsaBuildStatus.of(scanning(90000, done: 20, total: 20));
    expect(status.headline.args['current'], 20);
  });

  test('לפני הסריקה ובזמן הזיהוי — סרגל בלתי קצוב', () {
    for (final stage in [
      ResponsaBuildStage.starting,
      ResponsaBuildStage.classifying,
    ]) {
      final status = ResponsaBuildStatus.of(
        ResponsaBuildProgress(stage: stage, scannedNodes: 1251889),
        expectedNodes: 1251889,
      );
      expect(status.fraction, isNull, reason: stage.name);
      expect(
        status.detail(const Duration(seconds: 7)).template,
        'עברו {elapsed}',
      );
    }
  });

  test('clock ו-grouped', () {
    expect(ResponsaBuildStatus.clock(const Duration(seconds: 65)), '1:05');
    expect(
      ResponsaBuildStatus.clock(
        const Duration(hours: 1, minutes: 2, seconds: 3),
      ),
      '1:02:03',
    );
    expect(ResponsaBuildStatus.grouped(1251889), '1,251,889');
    expect(ResponsaBuildStatus.grouped(999), '999');
  });
}
