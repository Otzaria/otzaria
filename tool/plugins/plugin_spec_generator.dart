// ignore_for_file: avoid_print, depend_on_referenced_packages
//
// analyzer מגיע דרך dependency_overrides ולא כתלות ישירה — סקריפט תחזוקה
// בלבד, שאינו נכנס ל-build של האפליקציה.
//
// מחולל `docs/plugin-sdk/spec.json` — המפרט המכונה-קריא של ממשק התוספים.
// המקור היחיד לאמת הוא קוד האפליקציה: הקבועים ב-lib/plugins/**. הסקריפט
// מפרסר את ה-AST של אותם קבצים ולא מקודד אף רשימה בעצמו, כדי שהוספת API
// חדש בקוד תשתקף במפרט בלי לגעת כאן.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// גרסת סכימה של `spec.json`. מעלים אותה רק כששדה קיים משנה משמעות.
/// אזהרה: צרכני ה-JS (knownApi.js בוולידטור, pluginValidation.js באתר) זורקים
/// ברמת המודול כשהערך אינו מוכר — כלומר העלאה כאן משביתה את ה-Action ואת החנות
/// עד שהעותקים המצורפים והקבוע SUPPORTED_SPEC_SCHEMA מסונכרנים. אין נפילה רכה.
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
    // throwIfDiagnostics: true — מקור פגום (למשל `}` מוקדם שסוגר רשימה בטרם עת)
    // עדיין נותן AST בר-שחזור אך מקצר רשימות בשקט; חובה לזרוק כאן, אחרת המפרט
    // ייצא חלקי והוולידטורים יתירו API/הגדרות אסורים.
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
    'lib/plugins/bridge/plugin_bridge_handler.dart',
    'lib/plugins/services/plugin_manifest_validator.dart',
    'lib/plugins/services/plugin_settings_access_policy.dart',
    'lib/settings/engine/settings_repository.dart',
  ]) {
    env.addFile(p.join(root.path, p.joinAll(p.posix.split(relative))));
  }

  final knownMethods = env.stringCollection('_knownApiMethods');
  final undocumented = env.stringCollection('_knownUndocumentedMethods');
  final bridgePermissions = env.stringMap(
    'PluginBridgeHandler.methodPermissions',
  );
  final noManifestPermission = env.stringConst(
    'PluginBridgeHandler.noManifestPermission',
  );

  // מיפוי ההרשאות מגיע משני מקומות: הטבלה הנאכפת בגשר, והמפה שהוולידטור
  // משתמש בה. הגשר גובר — הוא מה שנאכף בזמן ריצה.
  final methodPermissions = <String, String>{
    ...env.stringMap('_methodRequiredPermission'),
  };
  for (final entry in bridgePermissions.entries) {
    if (entry.value == noManifestPermission) continue;
    methodPermissions[entry.key] = entry.value;
  }

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
    'apiMethods': sorted(knownMethods),
    'undocumentedApiMethods': sorted(undocumented),
    'methodPermissions': sortedMap(methodPermissions),
    'methodMinVersions': sortedMap(env.stringMap('_methodMinVersion')),
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
    },
    'versions': {
      'whenCondition': env.stringConst('_whenConditionMinVersion'),
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
