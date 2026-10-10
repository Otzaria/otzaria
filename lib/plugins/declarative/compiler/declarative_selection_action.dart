import 'package:otzaria/plugins/declarative/commands/declarative_command_registry.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_action_compiler.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_value_checks.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';

/// מה נלחץ: פריט בתפריט הקשר (`$selection`) או ספר של ספק בחיפוש הספרייה
/// (`$book`). כל מקור חושף רק את נתוני הלחיצה שלו.
enum DeclarativeClickSource { selection, libraryBook }

/// תבנית פעולת host על לחיצה: פריט תפריט הקשר, או ספר ספק במסך הספרייה.
/// נפתרת בזמן הלחיצה, בלי מנוע JS ובלי תכנית. ההפניות הן נתוני הלחיצה
/// (`$selection` או `$book`, לפי המקור) ו-`$storage` — ערך מאחסון התוסף,
/// לצד `$literal` ו-`$concat`.
class DeclarativeSelectionAction {
  static const int maxNodes = 128;
  static const int maxDepth = 10;

  /// הנתיבים המותרים ב-`$selection` — תת-קבוצה סקלרית של payload הלחיצה.
  static const Set<String> allowedSelectionPaths = {
    'selectedText',
    'currentRef',
    'currentBook',
    'currentBookId',
    'currentIndex',
    'id',
    'type',
    'source',
  };

  /// הנתיבים המותרים ב-`$book` — הספר שנבחר בחיפוש הספרייה.
  static const Set<String> allowedBookPaths = {
    'id',
    'title',
    'author',
    'provider',
  };

  /// ולידציה מבנית של התבנית. עם [declaredPermissions] נבדקת גם הצהרת
  /// ההרשאה של הפעולה — בלעדיה (רישום בגשר) הבדיקה נדחית לזמן הלחיצה.
  static void validateTemplate(
    Map<String, dynamic> json, {
    Set<String>? declaredPermissions,
    DeclarativeClickSource source = DeclarativeClickSource.selection,
  }) {
    assertOnlyKeys(json, const {'type', 'args'}, 'action');
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw const DeclarativeProgramException(
        'declarative.invalid_action',
        'action.type must be a non-empty string',
      );
    }
    final definition = DeclarativeCommandRegistry.require(type);
    if (definition.phase != DeclarativeCommandPhase.action ||
        definition.requiredPermission == null) {
      throw DeclarativeProgramException(
        'declarative.invalid_phase',
        'Command "$type" is not an action',
      );
    }
    if (declaredPermissions != null &&
        !declaredPermissions.contains(definition.requiredPermission)) {
      throw DeclarativeProgramException(
        'declarative.permission_not_declared',
        'Action "$type" requires permission '
            '"${definition.requiredPermission}"',
      );
    }
    final args = _requiredMap(json['args'], 'action.args');
    assertOnlyKeys(
      args,
      {...definition.requiredArgs, ...definition.optionalArgs},
      'action.args',
    );
    final missing = definition.requiredArgs
        .where((field) => !args.containsKey(field))
        .toList();
    if (missing.isNotEmpty) {
      throw DeclarativeProgramException(
        'declarative.invalid_args',
        'Action "$type" is missing: ${missing.join(', ')}',
      );
    }
    final budget = _Budget();
    _validateExpression(args, budget, source: source, depth: 0);
    if (declaredPermissions != null &&
        storageKeys(json).isNotEmpty &&
        !declaredPermissions.contains('plugin.storage.read')) {
      throw const DeclarativeProgramException(
        'declarative.permission_not_declared',
        r'$storage requires permission "plugin.storage.read"',
      );
    }
    if (type == 'localService.post') {
      DeclarativeActionCompiler.validateLocalServiceArgs(args, template: true);
    }
  }

  /// מפתחות האחסון שהתבנית קוראת (`$storage`), כדי שהמבצע יקרא אותם לפני
  /// [resolve]. התבנית כבר עברה [validateTemplate].
  static Set<String> storageKeys(Map<String, dynamic> template) {
    final keys = <String>{};
    void visit(Object? value) {
      if (value is Map) {
        if (value.length == 1 && value.containsKey(r'$literal')) return;
        if (value.length == 1 && value[r'$storage'] is String) {
          keys.add(value[r'$storage'] as String);
          return;
        }
        value.values.forEach(visit);
      } else if (value is List) {
        value.forEach(visit);
      }
    }

    visit(template['args']);
    return keys;
  }

  /// פותר את הפניות התבנית מול [payload] של הלחיצה ומול ערכי [storage]
  /// (מפתח שאינו קיים ← `null`). הערכים המוחזרים עדיין עוברים את הולידציה
  /// המלאה של DeclarativeActionCompiler.
  static Map<String, dynamic> resolve(
    Map<String, dynamic> template,
    Map<String, dynamic> payload, {
    Map<String, Object?> storage = const {},
  }) {
    return {
      'type': template['type'],
      'args': _resolveValue(template['args'], payload, storage),
    };
  }

  static final RegExp _controlCharRuns = RegExp(r'[\u0000-\u001F\u007F]+');

  /// מסיר תווי בקרה ומגביל טקסט בלי לפצל זוג surrogate,
  /// כדי שסימון של כמה שורות יתאים לארגומנטים של הפעולה.
  static String _clickText(String text) {
    final flat = text.replaceAll(_controlCharRuns, ' ');
    const max = DeclarativeActionCompiler.maxJsonStringLength;
    if (flat.length <= max) return flat;
    final end = flat.codeUnitAt(max - 1) & 0xFC00 == 0xD800 ? max - 1 : max;
    return flat.substring(0, end);
  }

  static Object? _resolveValue(
    Object? value,
    Map<String, dynamic> payload,
    Map<String, Object?> storage,
  ) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.length == 1) {
        if (map.containsKey(r'$literal')) return _copy(map[r'$literal']);
        for (final root in const [r'$selection', r'$book']) {
          if (map.containsKey(root)) {
            final data = payload[map[root] as String];
            return data is String ? _clickText(data) : data;
          }
        }
        if (map.containsKey(r'$storage')) {
          return _copy(storage[map[r'$storage'] as String]);
        }
        if (map.containsKey(r'$concat')) {
          return (map[r'$concat'] as List<dynamic>)
              .map((part) => _resolveValue(part, payload, storage))
              .map((part) => part?.toString() ?? '')
              .join();
        }
      }
      return {
        for (final entry in map.entries)
          entry.key: _resolveValue(entry.value, payload, storage),
      };
    }
    if (value is List) {
      return [for (final item in value) _resolveValue(item, payload, storage)];
    }
    return value;
  }

  static void _validateExpression(
    Object? value,
    _Budget budget, {
    required DeclarativeClickSource source,
    required int depth,
  }) {
    budget.visit(depth);
    if (value is Map) {
      final map = _requiredMap(value, 'expression');
      final special = map.keys.where((key) => key.startsWith(r'$')).toList();
      if (special.isNotEmpty) {
        if (map.length != 1) {
          throw const DeclarativeProgramException(
            'declarative.invalid_reference',
            'A reference object must contain exactly one field',
          );
        }
        switch (special.single) {
          case r'$literal':
            _validateLiteral(map[r'$literal'], budget, depth: depth + 1);
          case r'$selection' when source == DeclarativeClickSource.selection:
            final path = map[r'$selection'];
            if (path is! String || !allowedSelectionPaths.contains(path)) {
              throw DeclarativeProgramException(
                'declarative.invalid_reference',
                'Selection path "$path" is not allowed',
              );
            }
          case r'$book' when source == DeclarativeClickSource.libraryBook:
            final path = map[r'$book'];
            if (path is! String || !allowedBookPaths.contains(path)) {
              throw DeclarativeProgramException(
                'declarative.invalid_reference',
                'Book path "$path" is not allowed',
              );
            }
          case r'$storage':
            final key = map[r'$storage'];
            if (key is! String ||
                key.isEmpty ||
                key.length > DeclarativeActionCompiler.maxStorageKeyLength ||
                _hasControlChars(key)) {
              throw const DeclarativeProgramException(
                'declarative.invalid_reference',
                r'$storage must be a storage key of up to '
                    '${DeclarativeActionCompiler.maxStorageKeyLength} '
                    'characters',
              );
            }
          case r'$concat':
            final parts = map[r'$concat'];
            if (parts is! List || parts.isEmpty || parts.length > 8) {
              throw const DeclarativeProgramException(
                'declarative.invalid_reference',
                r'$concat must contain 1 to 8 parts',
              );
            }
            for (final part in parts) {
              _validateExpression(
                part,
                budget,
                source: source,
                depth: depth + 1,
              );
            }
          default:
            throw DeclarativeProgramException(
              'declarative.invalid_reference',
              'Unsupported reference "${special.single}"',
            );
        }
        return;
      }
      for (final entry in map.entries) {
        _validateExpression(
          entry.value,
          budget,
          source: source,
          depth: depth + 1,
        );
      }
      return;
    }
    if (value is List) {
      if (value.length > 20) {
        throw const DeclarativeProgramException(
          'declarative.value_too_large',
          'Selection action lists are limited to 20 values',
        );
      }
      for (final item in value) {
        _validateExpression(item, budget, source: source, depth: depth + 1);
      }
      return;
    }
    _validateScalar(value);
  }

  static void _validateLiteral(
    Object? value,
    _Budget budget, {
    required int depth,
  }) {
    budget.visit(depth);
    if (value is Map) {
      for (final child in _requiredMap(value, 'literal').values) {
        _validateLiteral(child, budget, depth: depth + 1);
      }
      return;
    }
    if (value is List) {
      for (final child in value) {
        _validateLiteral(child, budget, depth: depth + 1);
      }
      return;
    }
    _validateScalar(value);
  }

  static void _validateScalar(Object? value) {
    if (value == null || value is num || value is bool) return;
    if (value is String && value.length <= 4096 && !_hasControlChars(value)) {
      return;
    }
    throw const DeclarativeProgramException(
      'declarative.invalid_value',
      'Selection action templates may contain small JSON values only',
    );
  }

  static bool _hasControlChars(String value) {
    for (final unit in value.codeUnits) {
      if (unit < 0x20 || unit == 0x7F) return true;
    }
    return false;
  }

  static Object? _copy(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries) entry.key: _copy(entry.value),
      };
    }
    if (value is List) return value.map(_copy).toList();
    return value;
  }

  static Map<String, dynamic> _requiredMap(Object? value, String context) =>
      requiredMap(value, context, code: 'declarative.invalid_action');
}

class _Budget {
  int nodes = 0;

  void visit(int depth) {
    if (depth > DeclarativeSelectionAction.maxDepth) {
      throw const DeclarativeProgramException(
        'declarative.value_too_large',
        'Selection action is too deeply nested',
      );
    }
    nodes++;
    if (nodes > DeclarativeSelectionAction.maxNodes) {
      throw const DeclarativeProgramException(
        'declarative.value_too_large',
        'Selection action contains too many value nodes',
      );
    }
  }
}
