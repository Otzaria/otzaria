import 'package:otzaria/plugins/declarative/commands/declarative_command_registry.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_value_checks.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/models/declarative_toolbar_template.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';

class DeclarativeToolbarTemplateCompiler {
  final Set<String> declaredPermissions;
  final Map<String, CompiledDeclarativeProgram> programs;

  const DeclarativeToolbarTemplateCompiler({
    required this.declaredPermissions,
    required this.programs,
  });

  static bool isDeclarative(Map<String, dynamic> item) =>
      item.containsKey('binding') ||
      item.containsKey('action') ||
      item.containsKey('childrenBinding');

  List<CompiledDeclarativeToolbarTemplate> compileAll(
    String pluginId,
    List<Map<String, dynamic>> items,
  ) {
    final compiled = <CompiledDeclarativeToolbarTemplate>[];
    for (var index = 0; index < items.length; index++) {
      compiled.add(_compile(pluginId, items[index], index));
    }
    if (compiled.map((item) => item.baseItem.id).toSet().length !=
        compiled.length) {
      throw const DeclarativeProgramException(
        'declarative.duplicate_toolbar_item',
        'Declarative toolbar item ids must be unique',
      );
    }
    return List.unmodifiable(compiled);
  }

  CompiledDeclarativeToolbarTemplate _compile(
    String pluginId,
    Map<String, dynamic> json,
    int index,
  ) {
    _assertValueBudget(json);
    assertOnlyKeys(json, const {
      'id',
      'type',
      'title',
      'icon',
      'contexts',
      'placement',
      'order',
      'binding',
      'action',
      'childrenBinding',
      'when',
    }, 'toolbarItems[$index]');
    final type = json['type'] ?? 'button';
    if (type != 'button' && type != 'menu' && type != 'split') {
      throw const DeclarativeProgramException(
        'declarative.invalid_toolbar_item',
        'Declarative toolbar type must be button, menu, or split',
      );
    }
    final basePayload = <String, dynamic>{
      for (final field in const [
        'id',
        'type',
        'title',
        'icon',
        'contexts',
        'placement',
        'order',
        'when',
      ])
        if (json.containsKey(field)) field: json[field],
      if (type != 'button')
        'children': [
          {'id': '__validation__', 'title': 'validation'},
        ],
    };
    final baseItem = PluginToolbarRegistry.detached().registerPayload(
      pluginId,
      basePayload,
    );
    final binding = _requiredMap(
      json['binding'],
      'toolbarItems[$index].binding',
    );
    assertOnlyKeys(
      binding,
      const {'program', 'visibleOutput'},
      'toolbarItems[$index].binding',
    );
    final programId = _requiredString(binding['program'], 'binding.program');
    final program = programs[programId];
    if (program == null) {
      throw DeclarativeProgramException(
        'declarative.program_not_found',
        'Toolbar item references unknown program "$programId"',
      );
    }
    final visibleOutput = _outputPath(
      binding['visibleOutput'],
      program,
      'binding.visibleOutput',
    );

    if (type != 'menu') {
      if (type == 'button' && json['childrenBinding'] != null) {
        throw const DeclarativeProgramException(
          'declarative.invalid_toolbar_item',
          'A button cannot declare childrenBinding',
        );
      }
      final action = _requiredMap(
        json['action'],
        'toolbarItems[$index].action',
      );
      _validateActionTemplate(
        action,
        program,
        referenceKey: r'$output',
      );
      return CompiledDeclarativeToolbarTemplate(
        baseItem: baseItem,
        programId: programId,
        visibleOutput: visibleOutput,
        actionTemplate: deepFreeze(action),
        childrenBinding: type == 'split'
            ? _compileChildrenBinding(json, program, index)
            : null,
      );
    }

    if (json['action'] != null) {
      throw const DeclarativeProgramException(
        'declarative.invalid_toolbar_item',
        'A menu action belongs on its children',
      );
    }
    return CompiledDeclarativeToolbarTemplate(
      baseItem: baseItem,
      programId: programId,
      visibleOutput: visibleOutput,
      actionTemplate: null,
      childrenBinding: _compileChildrenBinding(json, program, index),
    );
  }

  CompiledDeclarativeChildrenBinding _compileChildrenBinding(
    Map<String, dynamic> json,
    CompiledDeclarativeProgram program,
    int index,
  ) {
    final children = _requiredMap(
      json['childrenBinding'],
      'toolbarItems[$index].childrenBinding',
    );
    assertOnlyKeys(
      children,
      const {'itemsOutput', 'itemTemplate', 'maxItems'},
      'toolbarItems[$index].childrenBinding',
    );
    final itemsOutput = _outputPath(
      children['itemsOutput'],
      program,
      'childrenBinding.itemsOutput',
    );
    final maxItems = children['maxItems'] ?? 20;
    if (maxItems is! int || maxItems < 1 || maxItems > 20) {
      throw const DeclarativeProgramException(
        'declarative.invalid_toolbar_item',
        'childrenBinding.maxItems must be between 1 and 20',
      );
    }
    final itemTemplate = _requiredMap(
      children['itemTemplate'],
      'childrenBinding.itemTemplate',
    );
    assertOnlyKeys(
      itemTemplate,
      const {'id', 'title', 'icon', 'action'},
      'childrenBinding.itemTemplate',
    );
    for (final required in const ['id', 'title', 'action']) {
      if (!itemTemplate.containsKey(required)) {
        throw DeclarativeProgramException(
          'declarative.invalid_toolbar_item',
          'childrenBinding.itemTemplate requires "$required"',
        );
      }
    }
    _validateExpression(itemTemplate['id'], program, r'$item', depth: 0);
    _validateExpression(itemTemplate['title'], program, r'$item', depth: 0);
    if (itemTemplate['icon'] != null) {
      _validateExpression(itemTemplate['icon'], program, r'$item', depth: 0);
    }
    _validateActionTemplate(
      _requiredMap(itemTemplate['action'], 'itemTemplate.action'),
      program,
      referenceKey: r'$item',
    );
    return CompiledDeclarativeChildrenBinding(
      itemsOutput: itemsOutput,
      itemTemplate: deepFreeze(itemTemplate),
      maxItems: maxItems,
    );
  }

  void _validateActionTemplate(
    Map<String, dynamic> action,
    CompiledDeclarativeProgram program, {
    required String referenceKey,
  }) {
    assertOnlyKeys(action, const {'type', 'args'}, 'action');
    final type = _requiredString(action['type'], 'action.type');
    final definition = DeclarativeCommandRegistry.require(type);
    if (definition.phase != DeclarativeCommandPhase.action ||
        definition.requiredPermission == null) {
      throw DeclarativeProgramException(
        'declarative.invalid_phase',
        'Command "$type" is not an action',
      );
    }
    final permission = definition.requiredPermission!;
    if (!declaredPermissions.contains(permission)) {
      throw DeclarativeProgramException(
        'declarative.permission_not_declared',
        'Action "$type" requires permission "$permission"',
      );
    }
    final args = _requiredMap(action['args'], 'action.args');
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
    _validateExpression(args, program, referenceKey, depth: 0);
  }

  void _validateExpression(
    Object? value,
    CompiledDeclarativeProgram program,
    String referenceKey, {
    required int depth,
  }) {
    if (depth > 10) {
      throw const DeclarativeProgramException(
        'declarative.value_too_large',
        'Toolbar expression is too deeply nested',
      );
    }
    if (value is Map) {
      final map = _requiredMap(value, 'expression');
      final special = map.keys.where((key) => key.startsWith(r'$')).toList();
      if (special.isNotEmpty) {
        if (map.length != 1) {
          throw const DeclarativeProgramException(
            'declarative.invalid_reference',
            'A toolbar reference must contain one field',
          );
        }
        final key = special.single;
        if (key == r'$literal') {
          _validateLiteral(map[key], depth: depth + 1);
          return;
        }
        if (key == r'$concat') {
          final parts = _requiredList(map[key], r'$concat');
          if (parts.isEmpty || parts.length > 8) {
            throw const DeclarativeProgramException(
              'declarative.invalid_reference',
              r'$concat must contain 1 to 8 parts',
            );
          }
          for (final part in parts) {
            _validateExpression(
              part,
              program,
              referenceKey,
              depth: depth + 1,
            );
          }
          return;
        }
        if (key != referenceKey) {
          throw DeclarativeProgramException(
            'declarative.invalid_reference',
            'Only "$referenceKey" is allowed in this toolbar template',
          );
        }
        final path = _requiredString(map[key], key);
        if (referenceKey == r'$output') {
          _assertOutputPath(path, program, key);
        } else {
          _assertPath(path, key);
        }
        return;
      }
      for (final entry in map.entries) {
        _validateExpression(
          entry.value,
          program,
          referenceKey,
          depth: depth + 1,
        );
      }
      return;
    }
    if (value is List) {
      if (value.length > 20) {
        throw const DeclarativeProgramException(
          'declarative.value_too_large',
          'Toolbar expression lists are limited to 20 values',
        );
      }
      for (final item in value) {
        _validateExpression(
          item,
          program,
          referenceKey,
          depth: depth + 1,
        );
      }
      return;
    }
    _validateScalar(value, 'expression');
  }

  String _outputPath(
    Object? value,
    CompiledDeclarativeProgram program,
    String context,
  ) {
    final path = _requiredString(value, context);
    _assertOutputPath(path, program, context);
    return path;
  }

  void _assertOutputPath(
    String path,
    CompiledDeclarativeProgram program,
    String context,
  ) {
    final parts = _assertPath(path, context);
    if (!program.outputs.containsKey(parts.first)) {
      throw DeclarativeProgramException(
        'declarative.output_not_found',
        'Program "${program.id}" has no output "${parts.first}"',
      );
    }
  }

  List<String> _assertPath(String path, String context) {
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

  void _validateLiteral(Object? value, {required int depth}) {
    if (depth > 10) {
      throw const DeclarativeProgramException(
        'declarative.value_too_large',
        'Toolbar literal is too deeply nested',
      );
    }
    if (value is Map) {
      final map = _requiredMap(value, 'literal');
      for (final child in map.values) {
        _validateLiteral(child, depth: depth + 1);
      }
      return;
    }
    if (value is List) {
      for (final child in value) {
        _validateLiteral(child, depth: depth + 1);
      }
      return;
    }
    _validateScalar(value, 'literal');
  }

  void _validateScalar(Object? value, String context) {
    if (value == null || value is num || value is bool) return;
    if (value is String &&
        value.length <= 4096 &&
        !RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value)) {
      return;
    }
    throw DeclarativeProgramException(
      'declarative.invalid_value',
      '$context must contain small JSON values only',
    );
  }

  void _assertValueBudget(Object? value) {
    var nodes = 0;
    void visit(Object? current, int depth) {
      nodes++;
      if (nodes > 256 || depth > 10) {
        throw const DeclarativeProgramException(
          'declarative.value_too_large',
          'Toolbar templates are limited in size and nesting depth',
        );
      }
      if (current is Map) {
        if (current.length > 20) {
          throw const DeclarativeProgramException(
            'declarative.value_too_large',
            'Toolbar objects are limited to 20 fields',
          );
        }
        for (final entry in current.entries) {
          visit(entry.key, depth + 1);
          visit(entry.value, depth + 1);
        }
      } else if (current is List) {
        if (current.length > 20) {
          throw const DeclarativeProgramException(
            'declarative.value_too_large',
            'Toolbar lists are limited to 20 values',
          );
        }
        for (final child in current) {
          visit(child, depth + 1);
        }
      }
    }

    visit(value, 0);
  }

  Map<String, dynamic> _requiredMap(Object? value, String context) =>
      requiredMap(value, context, code: 'declarative.invalid_toolbar_item');

  List<dynamic> _requiredList(Object? value, String context) {
    if (value is! List) {
      throw DeclarativeProgramException(
        'declarative.invalid_toolbar_item',
        '$context must be an array',
      );
    }
    return value;
  }

  String _requiredString(Object? value, String context) {
    if (value is! String || value.isEmpty || value.length > 4096) {
      throw DeclarativeProgramException(
        'declarative.invalid_toolbar_item',
        '$context must be a non-empty string',
      );
    }
    return value;
  }
}
