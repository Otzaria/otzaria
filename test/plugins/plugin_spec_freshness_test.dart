import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/plugins/plugin_spec_generator.dart';

/// `docs/plugin-sdk/spec.json` הוא המפרט שכלי הוולידציה החיצוניים (אתר החנות
/// ו-otzaria-plugin-validator) צורכים. הבדיקה מריצה את המחולל ומשווה לדיסק,
/// כך ש-API חדש בקוד בלי הרצת המחולל מפיל את הבנייה במקום לסחוף בשקט.
void main() {
  final root = Directory.current;
  final specFile = File('${root.path}/$specRelativePath');

  group('spec.json', () {
    test('מעודכן מול קבועי האפליקציה', () {
      final result = generatePluginSpec(root, check: true);
      expect(
        result.changed,
        isFalse,
        reason:
            'הקובץ ${result.outputPath} מיושן. הרץ: '
            'dart run tool/plugins/generate_plugin_spec.dart',
      );
    });

    test('קיים ומכיל את כל השדות שהצרכנים מסתמכים עליהם', () {
      expect(specFile.existsSync(), isTrue);
      final spec =
          jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;

      expect(spec['schemaVersion'], specSchemaVersion);
      for (final key in const [
        'permissions',
        'baselinePermissions',
        'legacyPermissionAliases',
        'apiMethods',
        'undocumentedApiMethods',
        'methodPermissions',
        'methodMinVersions',
        'events',
        'settings',
        'manifest',
        'versions',
      ]) {
        expect(spec.containsKey(key), isTrue, reason: 'שדה חסר: $key');
      }

      expect((spec['manifest'] as Map)['stability'], contains('stable'));
      expect((spec['versions'] as Map)['whenCondition'], isA<String>());
    });

    // מקור פגום שנותר בר-שחזור (למשל `}` מוקדם) מקצר רשימה בשקט. `isNotEmpty`
    // לא תופס זאת — רשימה שנחתכה לאיבר אחד עוברת. הרצפות נגזרות מהמצב בפועל
    // עם שוליים כלפי מטה; הורדת רשימה מתחת לרצפה מחייבת עדכון מודע כאן.
    test('לכל רשימה במפרט יש רצפה מספרית — קיצור בשקט נחסם', () {
      final spec =
          jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;
      final settings = spec['settings'] as Map;
      expect(settings['policy'], 'blocklist');

      int sizeOf(Object? value) => switch (value) {
        List() => value.length,
        Map() => value.length,
        _ => fail('לא רשימה ולא מפה: $value'),
      };

      // שם השדה -> רצפה. המצב בפועל בעת הכתיבה מופיע בהערה.
      final floors = <String, ({Object? value, int floor, int actual})>{
        'permissions': (value: spec['permissions'], floor: 45, actual: 50),
        'baselinePermissions': (
          value: spec['baselinePermissions'],
          floor: 5,
          actual: 6,
        ),
        'legacyPermissionAliases': (
          value: spec['legacyPermissionAliases'],
          floor: 1,
          actual: 1,
        ),
        'apiMethods': (value: spec['apiMethods'], floor: 110, actual: 121),
        'undocumentedApiMethods': (
          value: spec['undocumentedApiMethods'],
          floor: 2,
          actual: 2,
        ),
        'methodPermissions': (
          value: spec['methodPermissions'],
          floor: 100,
          actual: 112,
        ),
        'methodMinVersions': (
          value: spec['methodMinVersions'],
          floor: 110,
          actual: 121,
        ),
        'events': (value: spec['events'], floor: 22, actual: 24),
        'settings.blockedSubstrings': (
          value: settings['blockedSubstrings'],
          floor: 11,
          actual: 11,
        ),
        'settings.blockedPrefixes': (
          value: settings['blockedPrefixes'],
          floor: 11,
          actual: 11,
        ),
        'settings.blockedKeys': (
          value: settings['blockedKeys'],
          floor: 10,
          actual: 10,
        ),
        'manifest.stability': (
          value: (spec['manifest'] as Map)['stability'],
          floor: 3,
          actual: 3,
        ),
      };

      for (final entry in floors.entries) {
        expect(
          sizeOf(entry.value.value),
          greaterThanOrEqualTo(entry.value.floor),
          reason:
              '${entry.key} התכווץ מתחת לרצפה ${entry.value.floor} '
              '(היה ${entry.value.actual}). אם הצמצום מכוון — עדכן את הרצפה; '
              'אחרת זהו סימן למקור פגום שקיצר את הרשימה.',
        );
      }
    });

    // הרשימות הנחתכות ביותר בסכנה הן ה-blocklist: כלל שנעלם הופך
    // settings.get('…token') למותר בשני הוולידטורים. מוודאים ערכי-עוגן ולא
    // רק ספירה, כדי שגם החלפת תוכן תיתפס.
    test('כללי blocklist קריטיים קיימים בפועל', () {
      final settings =
          (jsonDecode(specFile.readAsStringSync())
                  as Map<String, dynamic>)['settings']
              as Map;
      final substrings = (settings['blockedSubstrings'] as List).cast<String>();
      for (final part in const [
        'token',
        'password',
        'secret',
        'credential',
        'apikey',
        'api-key',
        'email',
        'path',
      ]) {
        expect(
          substrings,
          contains(part),
          reason: 'כלל חסימה קריטי נעלם: $part',
        );
      }
      expect((settings['blockedKeys'] as List), contains('key-bookmarks'));
      expect((settings['blockedPrefixes'] as List), contains('sz:'));
    });

    // המחולל מקודד בשמן את שלוש רשימות המדיניות. רשימה רביעית שתתווסף
    // ל-PluginSettingsAccessPolicy תישמט מהמפרט בשקט — הבדיקה סורקת את הקובץ
    // ומוודאת שהמחולל מכסה בדיוק את הרשימות שקיימות שם.
    test('המחולל מכסה בדיוק את רשימות PluginSettingsAccessPolicy', () {
      final policySource = File(
        '${root.path}/lib/plugins/services/plugin_settings_access_policy.dart',
      ).readAsStringSync();

      final declared = RegExp(
        r'static\s+const\s+Set<String>\s+(\w+)\s*=',
      ).allMatches(policySource).map((m) => m.group(1)!).toSet();

      final covered =
          (jsonDecode(specFile.readAsStringSync())
                  as Map<String, dynamic>)['settings']
              as Map;
      final coveredNames = covered.keys
          .cast<String>()
          .where((k) => k != 'policy')
          .toSet();

      expect(
        declared,
        equals(coveredNames),
        reason:
            'רשימות המדיניות בקוד: $declared, אך המפרט מכסה: $coveredNames. '
            'עדכן את buildPluginSpec ב-tool/plugins/plugin_spec_generator.dart.',
      );
    });

    // הבדיקה הפנימית של המחולל: method שנאכף בגשר עם noManifestPermission
    // ונשכח ב-_knownApiMethods לא ייעלם מהמפרט בלי להיתפס.
    test('כל method בטבלת ההרשאות של הגשר מוכר במפרט', () {
      final spec =
          jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;
      final known = {
        ...(spec['apiMethods'] as List).cast<String>(),
        ...(spec['undocumentedApiMethods'] as List).cast<String>(),
      };
      final bridgeSource = File(
        '${root.path}/lib/plugins/bridge/plugin_bridge_handler.dart',
      ).readAsStringSync();
      final table = RegExp(
        r"methodPermissions\s*=\s*\{([\s\S]*?)\n\s*\};",
      ).firstMatch(bridgeSource);
      expect(table, isNotNull, reason: 'לא אותרה methodPermissions בגשר');

      final methods = RegExp(
        r"'([\w.]+)'\s*:",
      ).allMatches(table!.group(1)!).map((m) => m.group(1)!).toSet();
      expect(
        methods.length,
        greaterThanOrEqualTo(100),
        reason: 'טבלת ההרשאות בגשר נקראה חלקית — ייתכן מקור פגום',
      );
      expect(
        methods.where((m) => !known.contains(m)),
        isEmpty,
        reason: 'method נאכף בגשר אך אינו ברשימות ה-methods המוכרים במפרט',
      );
    });

    test('פנימית עקבי: כל method מוכר ובעל גרסה, וכל הרשאה מוכרת', () {
      final spec =
          jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;
      final known = {
        ...(spec['apiMethods'] as List).cast<String>(),
        ...(spec['undocumentedApiMethods'] as List).cast<String>(),
      };
      final permissions = (spec['permissions'] as List).cast<String>().toSet();
      final methodPermissions = (spec['methodPermissions'] as Map)
          .cast<String, dynamic>();
      final methodMinVersions = (spec['methodMinVersions'] as Map)
          .cast<String, dynamic>();

      expect(
        methodPermissions.keys.where((m) => !known.contains(m)),
        isEmpty,
        reason: 'הרשאה ממופה ל-method שאינו ברשימת ה-methods המוכרים',
      );
      expect(
        methodMinVersions.keys.where((m) => !known.contains(m)),
        isEmpty,
        reason: 'גרסת מינימום ל-method שאינו ברשימת ה-methods המוכרים',
      );
      expect(
        methodPermissions.values.where((p) => !permissions.contains(p)),
        isEmpty,
        reason: 'method דורש הרשאה שאינה ברשימת ההרשאות התקפות',
      );
      expect(
        (spec['apiMethods'] as List).cast<String>().where(
          (m) => !methodMinVersions.containsKey(m),
        ),
        isEmpty,
        reason: 'method מתועד ללא גרסת מינימום',
      );
    });
  });
}
