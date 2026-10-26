// ignore_for_file: avoid_print, depend_on_referenced_packages
//
// analyzer משמש לקריאת קבועי manifest/settings; שיטות ה-SDK מיובאות מהקטלוג.
// מחולל את docs/plugin-sdk/spec.json מקוד האפליקציה, בלי רשימות מקומיות.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/models/plugin_api_catalog.dart';

/// גרסת סכימה של `spec.json`; שינוי מחייב סנכרון עם צרכני ה-JS לפני פרסום.
const int specSchemaVersion = 1;

const String specRelativePath = 'docs/plugin-sdk/spec.json';

class PluginSpecError implements Exception {
  final String message;
  const PluginSpecError(this.message);
  @override
  String toString() => message;
}

class PluginSpecResult {
  final String json;
  final bool changed;
  final String outputPath;
  const PluginSpecResult({
    required this.json,
    required this.changed,
    required this.outputPath,
  });
}

// ===== קריאת קבועים מקוד Dart =====

/// אוסף הצהרות `const`/`static const` מקובץ Dart, ממופות לפי שם פשוט
/// ולפי `Class.field`, כדי שהפניה בין קבצים (SettingsRepository.keyX) תיפתר.
class _ConstEnv {
  final Map<String, Expression> byName = {};

  void addFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw PluginSpecError('קובץ מקור חסר: $path');
    }
    final source = file.readAsStringSync();
    // AST בר-שחזור עלול לקצר רשימות בשקט; מקור פגום חייב לעצור את המחולל.
    final ParseStringResult parsed;
    try {
      parsed = parseString(content: source, throwIfDiagnostics: true);
    } on ArgumentError catch (e) {
      throw PluginSpecError(
        'שגיאת תחביר במקור $path — המחולל לא ירוץ על קוד פגום כדי לא לייצר '
        'מפרט חלקי בשקט:\n$e',
      );
    }

    parsed.unit.accept(_VariableCollector(source, this));
  }

  void _put(String name, Expression? initializer) {
    if (initializer == null) return;
    byName.putIfAbsent(name, () => initializer);
  }

  Expression require(String name) {
    final expr = byName[name];
    if (expr == null) {
      throw PluginSpecError(
        'לא נמצאה הצהרת const בשם "$name" — ייתכן ששמה שונה בקוד. '
        'עדכן את tool/plugins/plugin_spec_generator.dart.',
      );
    }
    return expr;
  }

  /// פותר ביטוי למחרוזת. זורק אם אינו ליטרל או הפניה לקבוע מחרוזת מוכר —
  /// כשל רועש עדיף על מפרט שמשמיט ערך בשקט.
  String resolveString(Expression expr, String context) {
    if (expr is SimpleStringLiteral) return expr.value;
    if (expr is SimpleIdentifier) {
      final target = byName[expr.name];
      if (target != null) return resolveString(target, context);
    }
    if (expr is PrefixedIdentifier) {
      final full = '${expr.prefix.name}.${expr.identifier.name}';
      final target = byName[full] ?? byName[expr.identifier.name];
      if (target != null) return resolveString(target, context);
    }
    throw PluginSpecError(
      'לא ניתן לפתור ערך מחרוזת ב-$context: "$expr". '
      'הוסף את הקובץ המצהיר אותו לרשימת המקורות של המחולל.',
    );
  }

  List<String> stringCollection(String name) {
    final expr = require(name);
    final elements = switch (expr) {
      SetOrMapLiteral(:final elements) => elements,
      ListLiteral(:final elements) => elements,
      _ => throw PluginSpecError('"$name" אינו ליטרל של אוסף.'),
    };
    final out = <String>[];
    for (final element in elements) {
      if (element is! Expression) {
        throw PluginSpecError('אלמנט לא נתמך ב-"$name": $element');
      }
      out.add(resolveString(element, name));
    }
    if (out.isEmpty) throw PluginSpecError('האוסף "$name" יצא ריק.');
    return out;
  }

  Map<String, String> stringMap(String name) {
    final expr = require(name);
    if (expr is! SetOrMapLiteral) {
      throw PluginSpecError('"$name" אינו ליטרל של מפה.');
    }
    final out = <String, String>{};
    for (final element in expr.elements) {
      if (element is! MapLiteralEntry) {
        throw PluginSpecError('אלמנט לא נתמך במפה "$name": $element');
      }
      out[resolveString(element.key, name)] = resolveString(
        element.value,
        name,
      );
    }
    if (out.isEmpty) throw PluginSpecError('המפה "$name" יצאה ריקה.');
    return out;
  }

  String stringConst(String name) => resolveString(require(name), name);
}

/// אוסף כל הצהרת משתנה בקובץ, ורושם אותה גם תחת `Class.field` כשהיא בתוך
/// מחלקה. שם המחלקה נגזר מהטקסט שלפני ההצהרה ולא מצורת ה-AST, כי ייצוג
/// המחלקות ב-analyzer משתנה בין גרסאות.
class _VariableCollector extends RecursiveAstVisitor<void> {
  static final _classPattern = RegExp(
    r'(?:^|\n)\s*(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+)*class\s+([A-Za-z_$][\w$]*)',
  );

  final String _source;
  final _ConstEnv _env;

  _VariableCollector(this._source, this._env);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final name = node.name.lexeme;
    _env._put(name, node.initializer);
    final className = _enclosingClass(node.offset);
    if (className != null) {
      _env._put('$className.$name', node.initializer);
    }
    super.visitVariableDeclaration(node);
  }

  String? _enclosingClass(int offset) {
    String? last;
    for (final match in _classPattern.allMatches(_source)) {
      if (match.start > offset) break;
      last = match.group(1);
    }
    return last;
  }
}

// ===== בניית המפרט =====

Map<String, Object?> buildPluginSpec(Directory root) {
  final env = _ConstEnv();
  for (final relative in const [
    'lib/plugins/services/plugin_extended_validator.dart',
    'lib/plugins/models/plugin_valid_permissions.dart',
    'lib/plugins/services/plugin_manifest_validator.dart',
    'lib/plugins/services/plugin_settings_access_policy.dart',
    'lib/settings/engine/settings_repository.dart',
  ]) {
    env.addFile(p.join(root.path, p.joinAll(p.posix.split(relative))));
  }

  final methodPermissions = <String, String>{
    for (final entry in pluginApiMethods.entries)
      entry.key:
          ?(entry.value.runtimePermission ?? entry.value.validationPermission),
  };

  List<String> sorted(Iterable<String> values) =>
      values.toSet().toList()..sort();

  Map<String, String> sortedMap(Map<String, String> map) {
    final keys = map.keys.toList()..sort();
    return {for (final key in keys) key: map[key]!};
  }

  return {
    'schemaVersion': specSchemaVersion,
    'generatedBy': 'tool/plugins/generate_plugin_spec.dart',
    'source':
        'Otzaria app constants (lib/plugins/**). Do not edit by hand — see docs/plugin-sdk/SPEC.md.',
    'permissions': sorted(env.stringCollection('pluginValidPermissions')),
    'baselinePermissions': sorted(
      env.stringCollection('pluginBaselinePermissions'),
    ),
    'legacyPermissionAliases': sortedMap(
      env.stringMap('pluginLegacyPermissionAliases'),
    ),
    'apiMethods': sorted(pluginApiKnownMethods),
    'undocumentedApiMethods': sorted(pluginApiUndocumentedMethods),
    'methodPermissions': sortedMap(methodPermissions),
    'methodMinVersions': sortedMap(pluginApiMinVersions),
    'events': sorted(env.stringCollection('_knownEvents')),
    // מדיניות blocklist: כל הגדרה קריאה למעט מה שחסום. הכללים משוקפים
    // כנתונים, כדי שכלי JS יוכלו לשחזר את PluginSettingsAccessPolicy.isBlocked.
    // הנחה: למדיניות בדיוק שלוש רשימות (Substrings/Prefixes/Keys). רשימה רביעית
    // שתתווסף שם תישמט כאן בשקט — נאכף ב-plugin_spec_freshness_test.dart.
    'settings': {
      'policy': 'blocklist',
      'blockedSubstrings': sorted(
        env.stringCollection('PluginSettingsAccessPolicy.blockedSubstrings'),
      ),
      'blockedPrefixes': sorted(
        env.stringCollection('PluginSettingsAccessPolicy.blockedPrefixes'),
      ),
      'blockedKeys': sorted(
        env.stringCollection('PluginSettingsAccessPolicy.blockedKeys'),
      ),
    },
    'manifest': {
      'stability': env.stringCollection(
        'PluginManifestValidator.validStabilityValues',
      ),
      'platforms': env.stringCollection(
        'PluginManifestValidator.validPlatformValues',
      ),
    },
    'versions': {
      'whenCondition': env.stringConst('_whenConditionMinVersion'),
      'headless': env.stringConst('_headlessMinVersion'),
    },
  };
}

String encodePluginSpec(Map<String, Object?> spec) =>
    '${const JsonEncoder.withIndent('  ').convert(spec)}\n';

/// מחשב את המפרט וכותב אותו ל-`docs/plugin-sdk/spec.json` אם השתנה.
/// עם [check] בלבד — לא כותב, רק מדווח על הפרש.
PluginSpecResult generatePluginSpec(Directory root, {bool check = false}) {
  final json = encodePluginSpec(buildPluginSpec(root));
  final output = File(
    p.join(root.path, p.joinAll(p.posix.split(specRelativePath))),
  );
  final existing = output.existsSync() ? output.readAsStringSync() : null;
  final changed = existing != json;
  if (changed && !check) {
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(json);
  }
  return PluginSpecResult(
    json: json,
    changed: changed,
    outputPath: specRelativePath,
  );
}
