import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_api_catalog.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';

void main() {
  final spec =
      jsonDecode(File('docs/plugin-sdk/spec.json').readAsStringSync())
          as Map<String, dynamic>;

  test('הקטלוג שומר בדיוק את השיטות והגרסאות שפורסמו', () {
    expect(pluginApiKnownMethods, (spec['apiMethods'] as List).toSet());
    expect(
      pluginApiUndocumentedMethods,
      (spec['undocumentedApiMethods'] as List).toSet(),
    );
    expect(pluginApiMinVersions, spec['methodMinVersions']);
    expect(pluginApiMethods.keys.toSet(), {
      ...pluginApiKnownMethods,
      ...pluginApiUndocumentedMethods,
    });
  });

  test('הרשאות הגשר והאריזה שומרות על החוזה שפורסם', () {
    final permissions = (spec['methodPermissions'] as Map)
        .cast<String, String>();
    for (final method in pluginApiMethods.keys) {
      final isNetwork = method.startsWith('network.');
      expect(
        pluginApiMethodPermissions[method],
        isNetwork
            ? pluginApiNoManifestPermission
            : permissions[method] ?? pluginApiNoManifestPermission,
        reason: method,
      );
      expect(
        pluginApiValidationPermissions[method],
        method == 'plugin.requestInstall' ? null : permissions[method],
        reason: method,
      );
    }
  });

  test('פעולות הרשת שומרות על הרשאה התלויה ביעד ורמז שימושי לאריזה', () {
    for (final method in const [
      'network.fetchStream',
      'network.download',
      'network.fetchFile',
    ]) {
      expect(pluginApiMethods[method]!.runtimePermission, isNull);
      expect(pluginApiValidationPermissions[method], 'network.access');
      expect(pluginApiPermissionHints[method], 'network.access');
      expect(pluginApiCallsWithoutPermission, contains(method));
    }
  });

  test('מפת הרמזים נשארת חלקית ולא כוללת API קריאה רגילים', () {
    expect(pluginApiPermissionHints.length, 115);
    for (final method in const [
      'reader.openBook',
      'search.query',
      'notes.list',
      'library.resolveCategoryPaths',
    ]) {
      expect(pluginApiMethods, contains(method));
      expect(pluginApiPermissionHints, isNot(contains(method)));
    }
    expect(
      pluginApiPermissionHints['reader.beginCorrectionSession'],
      pluginReaderLocalEditPermission,
    );
  });

  test('קריאת ההתקנה הפנימית זמינה בגשר בלי להיחשף כ-API מתועד', () {
    const method = 'plugin.requestInstall';
    expect(pluginApiMethodPermissions[method], 'app.info.read');
    expect(pluginApiUndocumentedMethods, {method});
    expect(pluginApiKnownMethods, isNot(contains(method)));
    expect(pluginApiMinVersions, isNot(contains(method)));
    expect(pluginApiValidationPermissions, isNot(contains(method)));
    expect(pluginApiPermissionHints, isNot(contains(method)));
  });

  test('הרשאות ורמזים בקטלוג תקפים וכל שיטה מתועדת בעלת גרסה', () {
    for (final entry in pluginApiMethods.entries) {
      final method = entry.value;
      if (method.documented) expect(method.minVersion, isNotNull);
      for (final permission in [
        method.runtimePermission,
        method.validationPermission,
      ].nonNulls) {
        expect(pluginValidPermissions, contains(permission), reason: entry.key);
      }
      if (method.hasPermissionHint) {
        expect(method.validationPermission, isNotNull, reason: entry.key);
      }
    }
  });

  test('הקטלוג והמפות הנגזרות מוגנים משינוי', () {
    expect(() => pluginApiMethods.clear(), throwsUnsupportedError);
    for (final map in [
      pluginApiMethodPermissions,
      pluginApiValidationPermissions,
      pluginApiMinVersions,
      pluginApiPermissionHints,
    ]) {
      expect(() => map.clear(), throwsUnsupportedError);
    }
    for (final set in [
      pluginApiKnownMethods,
      pluginApiUndocumentedMethods,
      pluginApiCallsWithoutPermission,
    ]) {
      expect(() => set.clear(), throwsUnsupportedError);
    }
  });
}
