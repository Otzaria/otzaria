import 'dart:collection';

import 'package:otzaria/plugins/declarative/commands/declarative_command_registry.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/services/plugin_settings_access_policy.dart';

class DeclarativeProgramCompiler {
  static const int maxCommands = 16;
  static const int maxOutputs = 16;
  static const int maxValueDepth = 12;
  static const int maxValueNodes = 256;
  static const int maxListLength = 100;
  static const int maxStringLength = 4096;
  static const int maxDatabaseWhereDepth = 5;
  static const int maxKeyLength = 128;

  static const supportedTriggers = {
    'reader.activeBookChanged',
    'settings.changed',
    'app.startup',
  };

  static const contextValueKinds = {
    'reader.context': DeclarativeValueKind.scalar,
    'reader.book.id': DeclarativeValueKind.scalar,
    'reader.book.bookId': DeclarativeValueKind.scalar,
    'reader.book.type': DeclarativeValueKind.scalar,
    'reader.book.source': DeclarativeValueKind.scalar,
    'reader.book.external.provider': DeclarativeValueKind.scalar,
    'reader.book.external.id': DeclarativeValueKind.scalar,
  };

  final Set<String> declaredPermissions;
  final Set<String> declaredSourceIds;

  const DeclarativeProgramCompiler({
    required this.declaredPermissions,
    required this.declaredSourceIds,
  });

  CompiledDeclarativeProgram compile(Map<String, dynamic> json) {
    _assertOnlyKeys(
      json,
      const {'id', 'version', 'triggers', 'when', 'commands', 'outputs'},
      'program',
    );
    final id = _requiredIdentifier(json['id'], 'program.id');
    final version = json['version'];
    if (version is! int || version < 1) {
      throw const DeclarativeProgramException(
        'declarative.invalid_program',
        'program.version must be a positive integer',
      );
    }
    final triggers = _stringList(json['triggers'], 'program.triggers');
    if (triggers.isEmpty || triggers.toSet().length != triggers.length) {
      throw const DeclarativeProgramException(
        'declarative.invalid_program',
        'program.triggers must contain unique values',
      );
    }
    final unknownTriggers = triggers
        .where((trigger) => !supportedTriggers.contains(trigger))
        .toList();
    if (unknownTriggers.isNotEmpty) {
      throw DeclarativeProgramException(
        'declarative.invalid_trigger',
        'Unsupported triggers: ${unknownTriggers.join(', ')}',
      );
    }

    final outputsByCommand = <String, DeclarativeCommandDefinition>{};
    final budget = _ValueBudget();
    final when = json['when'];
    if (when != null) {
      _validateCondition(when, outputsByCommand, budget, depth: 0);
    }

    final rawCommands = _requiredList(json['commands'], 'program.commands');
    if (rawCommands.isEmpty || rawCommands.length > maxCommands) {
      throw const DeclarativeProgramException(
        'declarative.invalid_program',
        'program.commands must contain between 1 and 16 commands',
      );
    }
    final commands = <CompiledDeclarativeCommand>[];
    final requiredPermissions = <String>{};
    for (var index = 0; index < rawCommands.length; index++) {
      final commandJson = _requiredMap(
        rawCommands[index],
        'program.commands[$index]',
      );
      _assertOnlyKeys(
        commandJson,
        const {'id', 'type', 'args'},
        'program.commands[$index]',
      );
      final commandId = _requiredIdentifier(
        commandJson['id'],
        'program.commands[$index].id',
      );
      if (outputsByCommand.containsKey(commandId)) {
        throw DeclarativeProgramException(
          'declarative.duplicate_command',
          'Duplicate command id "$commandId"',
        );
      }
      final type = _requiredString(
        commandJson['type'],
        'program.commands[$index].type',
      );
      final definition = DeclarativeCommandRegistry.require(type);
      if (definition.phase != DeclarativeCommandPhase.computation) {
        throw DeclarativeProgramException(
          'declarative.invalid_phase',
          'Action command "$type" cannot run inside a computation program',
        );
      }
      final permission = definition.requiredPermission;
      if (permission != null) {
        if (!declaredPermissions.contains(permission)) {
          throw DeclarativeProgramException(
            'declarative.permission_not_declared',
            'Command "$type" requires permission "$permission"',
          );
        }
        requiredPermissions.add(permission);
      }
      final args = _requiredMap(
        commandJson['args'],
        'program.commands[$index].args',
      );
      _validateCommandArgs(
        definition,
        args,
        outputsByCommand,
        budget,
        commandIndex: index,
      );
      commands.add(
        CompiledDeclarativeCommand(
          id: commandId,
          type: type,
          args: _freezeMap(args),
          requiredPermission: permission,
        ),
      );
      outputsByCommand[commandId] = definition;
    }

    final rawOutputs = _requiredMap(json['outputs'], 'program.outputs');
    if (rawOutputs.isEmpty || rawOutputs.length > maxOutputs) {
      throw const DeclarativeProgramException(
        'declarative.invalid_program',
        'program.outputs must contain between 1 and 16 values',
      );
    }
    for (final entry in rawOutputs.entries) {
      _assertIdentifier(entry.key, 'program.outputs key');
      _validateValue(
        entry.value,
        outputsByCommand,
        budget,
        depth: 0,
        allowRow: false,
      );
    }

    return CompiledDeclarativeProgram(
      id: id,
      version: version,
      triggers: List.unmodifiable(triggers),
      when: _freeze(when),
      commands: List.unmodifiable(commands),
      outputs: _freezeMap(rawOutputs),
      requiredPermissions: Set.unmodifiable(requiredPermissions),
    );
  }

  void _validateCommandArgs(
    DeclarativeCommandDefinition definition,
    Map<String, dynamic> args,
    Map<String, DeclarativeCommandDefinition> previousCommands,
    _ValueBudget budget, {
    required int commandIndex,
  }) {
    final allowed = {...definition.requiredArgs, ...definition.optionalArgs};
    _assertOnlyKeys(args, allowed, 'program.commands[$commandIndex].args');
    final missing = definition.requiredArgs
        .where((field) => !args.containsKey(field))
        .toList();
    if (missing.isNotEmpty) {
      throw DeclarativeProgramException(
        'declarative.invalid_args',
        'Command "${definition.type}" is missing: ${missing.join(', ')}',
      );
    }

    switch (definition.type) {
      case 'database.select':
        _validateDatabaseSelectArgs(args, previousCommands, budget);
      case 'data.first':
        _validateValue(
          args['items'],
          previousCommands,
          budget,
          depth: 0,
          allowRow: false,
          expectedKind: DeclarativeValueKind.list,
        );
      case 'data.choose':
        _validateCondition(
          args['condition'],
          previousCommands,
          budget,
          depth: 0,
        );
        _validateValue(
          args['whenTrue'],
          previousCommands,
          budget,
          depth: 0,
          allowRow: false,
        );
        _validateValue(
          args['whenFalse'],
          previousCommands,
          budget,
          depth: 0,
          allowRow: false,
        );
      case 'data.map':
        _validateValue(
          args['items'],
          previousCommands,
          budget,
          depth: 0,
          allowRow: false,
          expectedKind: DeclarativeValueKind.list,
        );
        final maxItems = args['maxItems'] ?? 20;
        if (maxItems is! int || maxItems < 1 || maxItems > 20) {
          throw const DeclarativeProgramException(
            'declarative.invalid_args',
            'data.map.maxItems must be an integer between 1 and 20',
          );
        }
        final template = _requiredMap(args['template'], 'data.map.template');
        _validateValue(
          template,
          previousCommands,
          budget,
          depth: 0,
          allowRow: true,
        );
      case 'settings.get':
        final settingKey = _requiredArgKey(args['key'], 'settings.get.key');
        if (!PluginSettingsAccessPolicy.isReadable(settingKey)) {
          throw DeclarativeProgramException(
            'declarative.setting_not_allowed',
            'Setting "$settingKey" is not readable by plugins',
          );
        }
      case 'storage.get':
        _requiredArgKey(args['key'], 'storage.get.key');
      case 'library.parallelEditions':
        final parallelIdentity = _requiredMap(
          args['identity'],
          'library.parallelEditions.identity',
        );
        _validateBookIdentityTemplate(
          parallelIdentity,
          previousCommands,
          budget,
          allowRow: false,
        );
      case 'library.resolveBooks':
        _validateValue(
          args['items'],
          previousCommands,
          budget,
          depth: 0,
          allowRow: false,
          expectedKind: DeclarativeValueKind.list,
        );
        final identity = _requiredMap(
          args['identity'],
          'library.resolveBooks.identity',
        );
        _validateBookIdentityTemplate(
          identity,
          previousCommands,
          budget,
          allowRow: true,
        );
        final limit = args['limit'] ?? 20;
        if (limit is! int || limit < 1 || limit > 20) {
          throw const DeclarativeProgramException(
            'declarative.invalid_args',
            'library.resolveBooks.limit must be between 1 and 20',
          );
        }
        final keepInputFields = args['keepInputFields'];
        if (keepInputFields != null && keepInputFields is! bool) {
          throw const DeclarativeProgramException(
            'declarative.invalid_args',
            'library.resolveBooks.keepInputFields must be a boolean',
          );
        }
      default:
        throw DeclarativeProgramException(
          'declarative.invalid_phase',
          'Command "${definition.type}" is not a computation command',
        );
    }
  }

  /// מפתח חייב להיות ליטרל מחרוזת — כך ניתן לאכוף עליו policy בקומפילציה.
  String _requiredArgKey(Object? value, String context) {
    if (value is! String || value.isEmpty || value.length > maxKeyLength) {
      throw DeclarativeProgramException(
        'declarative.invalid_args',
        '$context must be a non-empty string of up to $maxKeyLength characters',
      );
    }
    _validateString(value, context);
    return value;
  }

  void _validateDatabaseSelectArgs(
    Map<String, dynamic> args,
    Map<String, DeclarativeCommandDefinition> previousCommands,
    _ValueBudget budget,
  ) {
    final sourceId = _requiredString(
      args['sourceId'],
      'database.select.sourceId',
    );
    if (!declaredSourceIds.contains(sourceId)) {
      throw DeclarativeProgramException(
        'declarative.source_not_declared',
        'Source "$sourceId" is not declared by the plugin',
      );
    }
    final rowFormat = args['rowFormat'] ?? 'object';
    if (rowFormat != 'object') {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'database.select.rowFormat must be "object"',
      );
    }
    for (final field in const [
      'from',
      'select',
      'joins',
      'orderBy',
      'limit',
      'offset',
      'rowFormat',
    ]) {
      if (args.containsKey(field)) {
        _validateLiteral(args[field], budget, depth: 0);
      }
    }
    if (args['where'] != null) {
      _validateDatabaseWhere(
        args['where'],
        previousCommands,
        budget,
        depth: 0,
      );
    }
  }

  void _validateDatabaseWhere(
    Object? value,
    Map<String, DeclarativeCommandDefinition> previousCommands,
    _ValueBudget budget, {
    required int depth,
  }) {
    if (depth > maxDatabaseWhereDepth) {
      throw const DeclarativeProgramException(
        'declarative.value_too_large',
        'database.select.where is too deeply nested',
      );
    }
    budget.visit(depth);
    final where = _requiredMap(value, 'database.select.where');
    final op = _requiredString(where['op'], 'database.select.where.op');
    if (op == 'and' || op == 'or') {
      _assertOnlyKeys(where, const {
        'op',
        'conditions',
      }, 'database.select.where');
      final conditions = _requiredList(
        where['conditions'],
        'database.select.where.conditions',
      );
      if (conditions.isEmpty || conditions.length > 32) {
        throw const DeclarativeProgramException(
          'declarative.invalid_args',
          'database.select.where.conditions must contain 1 to 32 items',
        );
      }
      budget.visit(depth + 1);
      for (final condition in conditions) {
        _validateDatabaseWhere(
          condition,
          previousCommands,
          budget,
          depth: depth + 1,
        );
      }
      return;
    }
    _assertOnlyKeys(where, const {
      'op',
      'left',
      'value',
    }, 'database.select.where');
    _requiredString(where['left'], 'database.select.where.left');
    if (where.containsKey('value')) {
      _validateValue(
        where['value'],
        previousCommands,
        budget,
        depth: depth + 1,
        allowRow: false,
      );
    }
  }

  void _validateBookIdentityTemplate(
    Map<String, dynamic> identity,
    Map<String, DeclarativeCommandDefinition> previousCommands,
    _ValueBudget budget, {
    required bool allowRow,
  }) {
    _assertOnlyKeys(
      identity,
      const {'id', 'bookId', 'type', 'source', 'external'},
      'book identity',
    );
    final external = identity['external'];
    Map<String, dynamic>? externalMap;
    if (external != null) {
      externalMap = _requiredMap(external, 'book identity.external');
      _assertOnlyKeys(
        externalMap,
        const {'provider', 'id'},
        'book identity.external',
      );
      if (!externalMap.containsKey('provider') ||
          !externalMap.containsKey('id')) {
        throw const DeclarativeProgramException(
          'declarative.invalid_identity',
          'External book identity requires provider and id',
        );
      }
    }
    if (!identity.containsKey('id') &&
        !identity.containsKey('bookId') &&
        externalMap == null) {
      throw const DeclarativeProgramException(
        'declarative.invalid_identity',
        'Book identity requires id, bookId, or external identity',
      );
    }
    _validateValue(
      identity,
      previousCommands,
      budget,
      depth: 0,
      allowRow: allowRow,
    );
  }

  void _validateCondition(
    Object? value,
    Map<String, DeclarativeCommandDefinition> previousCommands,
    _ValueBudget budget, {
    required int depth,
  }) {
    if (depth > 6) {
      throw const DeclarativeProgramException(
        'declarative.invalid_condition',
        'Condition is too deeply nested',
      );
    }
    budget.visit(depth);
    final condition = _requiredMap(value, 'condition');
    final op = _requiredString(condition['op'], 'condition.op');
    switch (op) {
      case 'and' || 'or':
        _assertOnlyKeys(condition, const {'op', 'conditions'}, 'condition');
        final conditions = _requiredList(
          condition['conditions'],
          'condition.conditions',
        );
        if (conditions.isEmpty || conditions.length > 16) {
          throw const DeclarativeProgramException(
            'declarative.invalid_condition',
            'condition.conditions must contain 1 to 16 items',
          );
        }
        budget.visit(depth + 1);
        for (final child in conditions) {
          _validateCondition(
            child,
            previousCommands,
            budget,
            depth: depth + 1,
          );
        }
      case 'not':
        _assertOnlyKeys(condition, const {'op', 'condition'}, 'condition');
        _validateCondition(
          condition['condition'],
          previousCommands,
          budget,
          depth: depth + 1,
        );
      case 'equals' || 'notEquals':
        _assertOnlyKeys(condition, const {'op', 'left', 'right'}, 'condition');
        _validateValue(
          condition['left'],
          previousCommands,
          budget,
          depth: depth + 1,
          allowRow: false,
        );
        _validateValue(
          condition['right'],
          previousCommands,
          budget,
          depth: depth + 1,
          allowRow: false,
        );
      case 'exists' || 'notEmpty':
        _assertOnlyKeys(condition, const {'op', 'value'}, 'condition');
        _validateValue(
          condition['value'],
          previousCommands,
          budget,
          depth: depth + 1,
          allowRow: false,
        );
      default:
        throw DeclarativeProgramException(
          'declarative.invalid_condition',
          'Unsupported condition operator "$op"',
        );
    }
  }

  DeclarativeValueKind _validateValue(
    Object? value,
    Map<String, DeclarativeCommandDefinition> previousCommands,
    _ValueBudget budget, {
    required int depth,
    required bool allowRow,
    DeclarativeValueKind expectedKind = DeclarativeValueKind.any,
  }) {
    budget.visit(depth);
    DeclarativeValueKind actualKind;
    if (value is Map) {
      final map = _requiredMap(value, 'value');
      final referenceKeys = map.keys
          .where((key) => key.startsWith(r'$'))
          .toList();
      if (referenceKeys.isNotEmpty) {
        if (map.length != 1) {
          throw const DeclarativeProgramException(
            'declarative.invalid_reference',
            'A reference object must contain exactly one field',
          );
        }
        final key = referenceKeys.single;
        switch (key) {
          case r'$literal':
            _validateLiteral(map[key], budget, depth: depth + 1);
            actualKind = _literalKind(map[key]);
          case r'$context':
            final path = _requiredString(map[key], r'$context');
            actualKind =
                contextValueKinds[path] ??
                (throw DeclarativeProgramException(
                  'declarative.context_not_allowed',
                  'Context path "$path" is not allowed',
                ));
          case r'$result':
            final reference = _requiredString(map[key], r'$result');
            actualKind = _resultKind(reference, previousCommands);
          case r'$row':
            if (!allowRow) {
              throw const DeclarativeProgramException(
                'declarative.row_out_of_scope',
                r'$row is only allowed inside a row template',
              );
            }
            _requiredReferencePath(map[key], r'$row');
            actualKind = DeclarativeValueKind.any;
          case r'$concat':
            final parts = _requiredList(map[key], r'$concat');
            if (parts.isEmpty || parts.length > 8) {
              throw const DeclarativeProgramException(
                'declarative.invalid_reference',
                r'$concat must contain 1 to 8 values',
              );
            }
            for (final part in parts) {
              _validateValue(
                part,
                previousCommands,
                budget,
                depth: depth + 1,
                allowRow: allowRow,
              );
            }
            actualKind = DeclarativeValueKind.scalar;
          default:
            throw DeclarativeProgramException(
              'declarative.invalid_reference',
              'Unsupported reference "$key"',
            );
        }
      } else {
        for (final entry in map.entries) {
          _validateString(entry.key, 'object key');
          _validateValue(
            entry.value,
            previousCommands,
            budget,
            depth: depth + 1,
            allowRow: allowRow,
          );
        }
        actualKind = DeclarativeValueKind.map;
      }
    } else if (value is List) {
      if (value.length > maxListLength) {
        throw const DeclarativeProgramException(
          'declarative.value_too_large',
          'A declarative list may contain at most 100 values',
        );
      }
      for (final item in value) {
        _validateValue(
          item,
          previousCommands,
          budget,
          depth: depth + 1,
          allowRow: allowRow,
        );
      }
      actualKind = DeclarativeValueKind.list;
    } else {
      _validateScalar(value, 'value');
      actualKind = DeclarativeValueKind.scalar;
    }
    _assertKind(expectedKind, actualKind);
    return actualKind;
  }

  DeclarativeValueKind _resultKind(
    String reference,
    Map<String, DeclarativeCommandDefinition> previousCommands,
  ) {
    final parts = _requiredReferencePath(reference, r'$result');
    final definition = previousCommands[parts.first];
    if (definition == null) {
      throw DeclarativeProgramException(
        'declarative.forward_reference',
        'Result "${parts.first}" is not produced by an earlier command',
      );
    }
    return definition.kindAtPath(parts.skip(1).toList());
  }

  void _assertKind(
    DeclarativeValueKind expected,
    DeclarativeValueKind actual,
  ) {
    if (expected == DeclarativeValueKind.any ||
        actual == DeclarativeValueKind.any ||
        expected == actual) {
      return;
    }
    throw DeclarativeProgramException(
      'declarative.type_mismatch',
      'Expected ${expected.name}, received ${actual.name}',
    );
  }

  void _validateLiteral(
    Object? value,
    _ValueBudget budget, {
    required int depth,
  }) {
    budget.visit(depth);
    if (value is Map) {
      final map = _requiredMap(value, 'literal');
      for (final entry in map.entries) {
        _validateString(entry.key, 'literal key');
        _validateLiteral(entry.value, budget, depth: depth + 1);
      }
      return;
    }
    if (value is List) {
      if (value.length > maxListLength) {
        throw const DeclarativeProgramException(
          'declarative.value_too_large',
          'A declarative list may contain at most 100 values',
        );
      }
      for (final item in value) {
        _validateLiteral(item, budget, depth: depth + 1);
      }
      return;
    }
    _validateScalar(value, 'literal');
  }

  DeclarativeValueKind _literalKind(Object? value) {
    if (value is Map) return DeclarativeValueKind.map;
    if (value is List) return DeclarativeValueKind.list;
    return DeclarativeValueKind.scalar;
  }

  List<String> _requiredReferencePath(Object? value, String context) {
    final path = _requiredString(value, context);
    final parts = path.split('.');
    if (parts.any(
      (part) => !RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(part),
    )) {
      throw DeclarativeProgramException(
        'declarative.invalid_reference',
        '$context contains an invalid path',
      );
    }
    return parts;
  }

  Map<String, dynamic> _requiredMap(Object? value, String context) {
    if (value is! Map) {
      throw DeclarativeProgramException(
        'declarative.invalid_program',
        '$context must be an object',
      );
    }
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      throw DeclarativeProgramException(
        'declarative.invalid_program',
        '$context keys must be strings',
      );
    }
  }

  List<dynamic> _requiredList(Object? value, String context) {
    if (value is! List) {
      throw DeclarativeProgramException(
        'declarative.invalid_program',
        '$context must be an array',
      );
    }
    return value;
  }

  List<String> _stringList(Object? value, String context) {
    final list = _requiredList(value, context);
    if (list.any((item) => item is! String)) {
      throw DeclarativeProgramException(
        'declarative.invalid_program',
        '$context must contain strings only',
      );
    }
    return List<String>.from(list);
  }

  String _requiredIdentifier(Object? value, String context) {
    final string = _requiredString(value, context);
    _assertIdentifier(string, context);
    return string;
  }

  void _assertIdentifier(String value, String context) {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,127}$').hasMatch(value)) {
      throw DeclarativeProgramException(
        'declarative.invalid_identifier',
        '$context contains an invalid identifier',
      );
    }
  }

  String _requiredString(Object? value, String context) {
    if (value is! String || value.isEmpty) {
      throw DeclarativeProgramException(
        'declarative.invalid_program',
        '$context must be a non-empty string',
      );
    }
    _validateString(value, context);
    return value;
  }

  void _validateString(String value, String context) {
    if (value.length > maxStringLength ||
        RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value)) {
      throw DeclarativeProgramException(
        'declarative.value_too_large',
        '$context contains an invalid string',
      );
    }
  }

  void _validateScalar(Object? value, String context) {
    if (value is String) {
      _validateString(value, context);
      return;
    }
    if (value == null || value is num || value is bool) return;
    throw DeclarativeProgramException(
      'declarative.invalid_value',
      '$context must contain JSON values only',
    );
  }

  void _assertOnlyKeys(
    Map<String, dynamic> value,
    Set<String> allowed,
    String context,
  ) {
    final unknown = value.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw DeclarativeProgramException(
        'declarative.unknown_field',
        '$context contains unsupported fields: ${unknown.join(', ')}',
      );
    }
  }

  Map<String, dynamic> _freezeMap(Map<String, dynamic> value) {
    return UnmodifiableMapView({
      for (final entry in value.entries) entry.key: _freeze(entry.value),
    });
  }

  Object? _freeze(Object? value) {
    if (value is Map) return _freezeMap(Map<String, dynamic>.from(value));
    if (value is List) return List.unmodifiable(value.map(_freeze));
    return value;
  }
}

class _ValueBudget {
  int nodes = 0;

  void visit(int depth) {
    if (depth > DeclarativeProgramCompiler.maxValueDepth) {
      throw const DeclarativeProgramException(
        'declarative.value_too_large',
        'Declarative value is too deeply nested',
      );
    }
    nodes++;
    if (nodes > DeclarativeProgramCompiler.maxValueNodes) {
      throw const DeclarativeProgramException(
        'declarative.value_too_large',
        'Declarative program contains too many value nodes',
      );
    }
  }
}
