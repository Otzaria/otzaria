import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/info/app_info_service.dart';
import 'package:otzaria/core/info/info_topic.dart';

/// חוזה ה-JSON של הדוח הוא ממשק מכונה מתועד (`docs/deep_links.md`), ושני
/// הערוצים — הפופאפ ופקודת ה-CLI — מייצרים אותו מאותו [AppInfoReport].
/// הבדיקות כאן מקבעות את שדות השורש ואת מפתחות המקטעים.
void main() {
  AppInfoReport reportFor(InfoTopic topic, {bool settingsLoaded = true}) =>
      AppInfoReport(
        topic: topic,
        generatedAt: DateTime.parse('2026-08-20T14:32:00.000'),
        settingsLoaded: settingsLoaded,
        sections: {for (final section in topic.sections) section.slug: {}},
      );

  group('שדות השורש', () {
    test('כל דוח נושא topic, generatedAt ו-settingsLoaded', () {
      for (final topic in InfoTopic.values) {
        final json = reportFor(topic).toJson();

        expect(json['topic'], topic.slug, reason: topic.slug);
        expect(json['settingsLoaded'], isTrue, reason: topic.slug);
        expect(json['generatedAt'], isA<String>(), reason: topic.slug);
      }
    });

    test('generatedAt הוא UTC עם סיומת Z', () {
      final value = reportFor(InfoTopic.app).toJson()['generatedAt'] as String;

      expect(value, endsWith('Z'));
      expect(DateTime.parse(value).isUtc, isTrue);
      expect(
        DateTime.parse(value),
        DateTime.parse('2026-08-20T14:32:00.000').toUtc(),
      );
    });

    test('settingsLoaded=false משתקף ב-JSON', () {
      expect(
        reportFor(
          InfoTopic.all,
          settingsLoaded: false,
        ).toJson()['settingsLoaded'],
        isFalse,
      );
    });
  });

  group('מפתחות המקטעים', () {
    test('נושא בודד מייצר מקטע אחד בשמו', () {
      for (final topic in InfoTopic.values.where((t) => t != InfoTopic.all)) {
        final json = reportFor(topic).toJson();
        final sections = json.keys.where(
          (key) => !const {
            'topic',
            'generatedAt',
            'settingsLoaded',
          }.contains(key),
        );

        expect(sections, [topic.slug], reason: topic.slug);
      }
    });

    test('all מייצר בדיוק את חמשת המקטעים', () {
      final json = reportFor(InfoTopic.all).toJson();

      for (final slug in ['app', 'library', 'folders', 'plugins', 'errors']) {
        expect(json.containsKey(slug), isTrue, reason: slug);
      }
      expect(json.keys, hasLength(3 + 5));
    });

    test('שם מקטע אינו מתנגש עם שדה שורש', () {
      final rootFields = {'topic', 'generatedAt', 'settingsLoaded'};

      for (final topic in InfoTopic.values) {
        expect(rootFields.contains(topic.slug), isFalse, reason: topic.slug);
      }
    });
  });
}
