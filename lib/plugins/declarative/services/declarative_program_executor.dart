import 'dart:convert';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/plugins/database/plugin_database_service.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_value_checks.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_settings_access_policy.dart';

abstract interface class DeclarativeBookResolver {
  /// מחזיר זהויות קנוניות לפי סדר הקלט; התאמה שאינה יחידה מוחזרת כ-null.
  Future<List<Map<String, dynamic>?>> resolveUniqueBatch(
    List<Map<String, dynamic>> identities,
  );
}

/// מחזיר את המהדורות המקבילות (מובנית + היברובוקס מקומיות) לזהות ספר,
/// כשורות `{title, isCompanion, identity}` — ראו ParallelEditionsService.
typedef DeclarativeParallelEditionsFinder =
    Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> identity);

Object? _defaultSettingReader(String key) => Settings.getValue(key);

class DeclarativeProgramExecutor {
  final PluginDatabaseService _databaseService;
  final PluginRegistryRepository _registryRepository;
  final PluginSettingReader _settingReader;
  final DeclarativeBookResolver? bookResolver;
  final DeclarativeParallelEditionsFinder? parallelEditionsFinder;

  DeclarativeProgramExecutor({
    PluginDatabaseService? databaseService,
    PluginRegistryRepository? registryRepository,
    PluginSettingReader? settingReader,
    this.bookResolver,
    this.parallelEditionsFinder,
  }) : _databaseService = databaseService ?? PluginDatabaseService(),
       _registryRepository = registryRepository ?? PluginRegistryRepository(),
       _settingReader = settingReader ?? _defaultSettingReader;

  Future<DeclarativeProgramResult> execute({
    required CompiledDeclarativeProgram program,
    required InstalledPlugin plugin,
    required Set<String> grantedPermissions,
    required Map<String, dynamic> context,
  }) async {
    if (!plugin.enabled) {
      throw const DeclarativeProgramException(
        'declarative.plugin_disabled',
        'The plugin is disabled',
      );
    }
    final missingPermissions = program.requiredPermissions
        .where((permission) => !grantedPermissions.contains(permission))
        .toList();
    if (missingPermissions.isNotEmpty) {
      throw DeclarativeProgramException(
        'declarative.permission_denied',
        'Missing granted permissions: ${missingPermissions.join(', ')}',
      );
    }

    final results = <String, Object?>{};
    if (program.when != null &&
        !_evaluateCondition(program.when, context: context, results: results)) {
      return DeclarativeProgramResult(
        programId: program.id,
        outputs: const {},
      );
    }

    for (final command in program.commands) {
      results[command.id] = await _executeCommand(
        command,
        plugin: plugin,
        context: context,
        results: results,
      );
    }

    final outputs = <String, dynamic>{};
    for (final entry in program.outputs.entries) {
      outputs[entry.key] = _resolveValue(
        entry.value,
        context: context,
        results: results,
      );
    }
    return DeclarativeProgramResult(
      programId: program.id,
      outputs: deepFreeze(outputs),
    );
  }

  Future<Object?> _executeCommand(
    CompiledDeclarativeCommand command, {
    required InstalledPlugin plugin,
    required Map<String, dynamic> context,
    required Map<String, Object?> results,
  }) async {
    switch (command.type) {
      case 'database.select':
        final resolved = _resolveValue(
          command.args,
          context: context,
          results: results,
        );
        final spec = Map<String, dynamic>.from(resolved as Map);
        spec.putIfAbsent('rowFormat', () => 'object');
        return _databaseService.query(plugin, spec);
      case 'data.first':
        final items = _resolveItems(
          command.args['items'],
          context: context,
          results: results,
          commandType: command.type,
        );
        return items.firstOrNull;
      case 'data.choose':
        final selected =
            _evaluateCondition(
              command.args['condition'],
              context: context,
              results: results,
            )
            ? command.args['whenTrue']
            : command.args['whenFalse'];
        return _resolveValue(
          selected,
          context: context,
          results: results,
        );
      case 'data.map':
        final items = _resolveItems(
          command.args['items'],
          context: context,
          results: results,
          commandType: command.type,
        );
        final maxItems = command.args['maxItems'] as int? ?? 20;
        return [
          for (final row in items.take(maxItems))
            _resolveValue(
              command.args['template'],
              context: context,
              results: results,
              row: row,
            ),
        ];
      case 'settings.get':
        final key = command.args['key'] as String;
        if (!PluginSettingsAccessPolicy.isReadable(key)) return null;
        return _settingReader(key);
      case 'storage.get':
        // נעול ל-namespace של הגשר — namespaces פנימיים
        // (user_file_grants, otzaria.startup) אינם חשופים לתוסף.
        final raw = await _registryRepository.getKV(
          plugin.pluginId,
          kDefaultStorageNamespace,
          command.args['key'] as String,
        );
        if (raw == null) return null;
        try {
          return jsonDecode(raw);
        } on FormatException {
          return raw;
        }
      case 'library.parallelEditions':
        final finder = parallelEditionsFinder;
        if (finder == null) {
          throw const DeclarativeProgramException(
            'declarative.service_unavailable',
            'library.parallelEditions is not available',
          );
        }
        final identity = _resolveValue(
          command.args['identity'],
          context: context,
          results: results,
        );
        if (identity is! Map) {
          throw const DeclarativeProgramException(
            'declarative.type_mismatch',
            'library.parallelEditions.identity must be an object',
          );
        }
        return finder(Map<String, dynamic>.from(identity));
      case 'library.resolveBooks':
        final resolver = bookResolver;
        if (resolver == null) {
          throw const DeclarativeProgramException(
            'declarative.service_unavailable',
            'library.resolveBooks is not available',
          );
        }
        final items = _resolveItems(
          command.args['items'],
          context: context,
          results: results,
          commandType: command.type,
        );
        final limit = command.args['limit'] as int? ?? 20;
        final keepInputFields = command.args['keepInputFields'] == true;
        final rows = <Object?>[];
        final identities = <Map<String, dynamic>>[];
        for (final row in items.take(limit)) {
          final identityValue = _resolveValue(
            command.args['identity'],
            context: context,
            results: results,
            row: row,
          );
          if (identityValue is! Map) continue;
          rows.add(row);
          identities.add(Map<String, dynamic>.from(identityValue));
        }
        final canonicalBooks = await resolver.resolveUniqueBatch(identities);
        if (canonicalBooks.length != identities.length) {
          throw const DeclarativeProgramException(
            'declarative.service_invalid_result',
            'library.resolveBooks returned an invalid result count',
          );
        }
        final resolvedBooks = <Map<String, dynamic>>[];
        for (var index = 0; index < canonicalBooks.length; index++) {
          final canonical = canonicalBooks[index];
          if (canonical == null) continue;
          final row = rows[index];
          final output = <String, dynamic>{};
          if (keepInputFields && row is Map) {
            output.addAll(Map<String, dynamic>.from(row));
          }
          output['identity'] = canonical;
          resolvedBooks.add(output);
        }
        return resolvedBooks;
      default:
        throw DeclarativeProgramException(
          'declarative.unknown_command',
          'Unknown computation command "${command.type}"',
        );
    }
  }

  List<dynamic> _resolveItems(
    Object? value, {
    required Map<String, dynamic> context,
    required Map<String, Object?> results,
    required String commandType,
  }) {
    final resolved = _resolveValue(
      value,
      context: context,
      results: results,
    );
    if (resolved is! List) {
      throw DeclarativeProgramException(
        'declarative.type_mismatch',
        '$commandType expected a list at runtime',
      );
    }
    return resolved;
  }

  Object? _resolveValue(
    Object? value, {
    required Map<String, dynamic> context,
    required Map<String, Object?> results,
    Object? row,
  }) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.length == 1) {
        if (map.containsKey(r'$literal')) return _copy(map[r'$literal']);
        if (map.containsKey(r'$context')) {
          return _readPath(context, map[r'$context'] as String);
        }
        if (map.containsKey(r'$result')) {
          return _readPath(results, map[r'$result'] as String);
        }
        if (map.containsKey(r'$row')) {
          return _readPath(row, map[r'$row'] as String);
        }
        if (map.containsKey(r'$concat')) {
          final parts = map[r'$concat'] as List<dynamic>;
          return parts
              .map(
                (part) => _resolveValue(
                  part,
                  context: context,
                  results: results,
                  row: row,
                ),
              )
              .map((part) => part?.toString() ?? '')
              .join();
        }
      }
      return {
        for (final entry in map.entries)
          entry.key: _resolveValue(
            entry.value,
            context: context,
            results: results,
            row: row,
          ),
      };
    }
    if (value is List) {
      return [
        for (final item in value)
          _resolveValue(
            item,
            context: context,
            results: results,
            row: row,
          ),
      ];
    }
    return value;
  }

  bool _evaluateCondition(
    Object? value, {
    required Map<String, dynamic> context,
    required Map<String, Object?> results,
  }) {
    final condition = Map<String, dynamic>.from(value as Map);
    final op = condition['op'] as String;
    switch (op) {
      case 'and':
        return (condition['conditions'] as List<dynamic>).every(
          (child) => _evaluateCondition(
            child,
            context: context,
            results: results,
          ),
        );
      case 'or':
        return (condition['conditions'] as List<dynamic>).any(
          (child) => _evaluateCondition(
            child,
            context: context,
            results: results,
          ),
        );
      case 'not':
        return !_evaluateCondition(
          condition['condition'],
          context: context,
          results: results,
        );
      case 'equals':
        return _conditionValue(
              condition['left'],
              context: context,
              results: results,
            ) ==
            _conditionValue(
              condition['right'],
              context: context,
              results: results,
            );
      case 'notEquals':
        return _conditionValue(
              condition['left'],
              context: context,
              results: results,
            ) !=
            _conditionValue(
              condition['right'],
              context: context,
              results: results,
            );
      case 'exists':
        return _conditionValue(
              condition['value'],
              context: context,
              results: results,
            ) !=
            null;
      case 'notEmpty':
        return _isNotEmpty(
          _conditionValue(
            condition['value'],
            context: context,
            results: results,
          ),
        );
      default:
        throw DeclarativeProgramException(
          'declarative.invalid_condition',
          'Unsupported condition operator "$op"',
        );
    }
  }

  Object? _conditionValue(
    Object? value, {
    required Map<String, dynamic> context,
    required Map<String, Object?> results,
  }) {
    return _resolveValue(value, context: context, results: results);
  }

  bool _isNotEmpty(Object? value) {
    if (value is String) return value.isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return value != null;
  }

  Object? _readPath(Object? root, String path) {
    Object? current = root;
    for (final part in path.split('.')) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  Object? _copy(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries) entry.key: _copy(entry.value),
      };
    }
    if (value is List) return value.map(_copy).toList();
    return value;
  }
}
