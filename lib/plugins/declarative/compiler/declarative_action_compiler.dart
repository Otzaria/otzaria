import 'dart:collection';

import 'package:otzaria/plugins/declarative/commands/declarative_command_registry.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';

class DeclarativeActionCompiler {
  /// תקרות אורך לפעולות שמזרימות טקסט של התוסף לממשק או לחיפוש.
  static const int maxRefLength = 256;
  static const int maxQueryLength = 500;
  static const int maxSnackLength = 200;

  static const Set<String> snackSeverities = {'info', 'success', 'error'};

  final Set<String> declaredPermissions;

  const DeclarativeActionCompiler({required this.declaredPermissions});

  CompiledDeclarativeAction compileResolved(
    Map<String, dynamic> json, {
    required String contextSignature,
    required int programGeneration,
  }) {
    _assertOnlyKeys(json, const {'type', 'args'}, 'action');
    if (contextSignature.isEmpty) {
      throw const DeclarativeProgramException(
        'declarative.invalid_action',
        'Action context signature must not be empty',
      );
    }
    if (programGeneration < 1) {
      throw const DeclarativeProgramException(
        'declarative.invalid_action',
        'Action program generation must be positive',
      );
    }
    final type = _requiredString(json['type'], 'action.type');
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
    final args = _requiredMap(json['args'], 'action.args');
    _assertOnlyKeys(
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
    switch (type) {
      case 'reader.openBook':
      case 'reader.openBookInSidePane':
        _validateOpenBookArgs(args);
      case 'storage.set':
      case 'storage.remove':
        _validateStorageArgs(args, requiresValue: type == 'storage.set');
      case 'reader.scrollToRef':
        _requiredShortString(
          args['ref'],
          'reader.scrollToRef.ref',
          maxRefLength,
        );
        _optionalBool(args['highlight'], 'reader.scrollToRef.highlight');
      case 'search.open':
        _requiredShortString(
          args['query'],
          'search.open.query',
          maxQueryLength,
        );
        _optionalBool(args['autoSearch'], 'search.open.autoSearch');
      case 'ui.showSnack':
        _requiredShortString(
          args['message'],
          'ui.showSnack.message',
          maxSnackLength,
        );
        final severity = args['severity'];
        if (severity != null && !snackSeverities.contains(severity)) {
          throw const DeclarativeProgramException(
            'declarative.invalid_args',
            'ui.showSnack.severity must be info, success or error',
          );
        }
      default:
        throw DeclarativeProgramException(
          'declarative.invalid_phase',
          'Unsupported action "$type"',
        );
    }
    return CompiledDeclarativeAction(
      type: type,
      args: _freezeMap(args),
      requiredPermission: permission,
      contextSignature: contextSignature,
      programGeneration: programGeneration,
    );
  }

  void _validateOpenBookArgs(Map<String, dynamic> args) {
    final identity = _requiredMap(args['identity'], 'action.args.identity');
    _assertOnlyKeys(
      identity,
      const {'id', 'bookId', 'type', 'source', 'external'},
      'action.args.identity',
    );
    final externalValue = identity['external'];
    Map<String, dynamic>? external;
    if (externalValue != null) {
      external = _requiredMap(externalValue, 'action.args.identity.external');
      _assertOnlyKeys(
        external,
        const {'provider', 'id'},
        'action.args.identity.external',
      );
      _requiredString(external['provider'], 'external.provider');
      _requiredIdentityId(external['id'], 'external.id');
    }
    if (!identity.containsKey('id') &&
        !identity.containsKey('bookId') &&
        external == null) {
      throw const DeclarativeProgramException(
        'declarative.invalid_identity',
        'Book identity requires id, bookId, or external identity',
      );
    }
    if (identity.containsKey('id')) {
      _requiredIdentityId(identity['id'], 'identity.id');
    }
    for (final field in const ['bookId', 'type', 'source']) {
      if (identity.containsKey(field)) {
        _requiredString(identity[field], 'identity.$field');
      }
    }
    final index = args['index'];
    if (index != null && (index is! int || index < 0)) {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'reader.openBook.index must be a non-negative integer',
      );
    }
    final searchQuery = args['searchQuery'];
    if (searchQuery != null &&
        (searchQuery is! String || searchQuery.length > 4096)) {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'reader.openBook.searchQuery must be a short string',
      );
    }
    final matchPages = args['matchPages'];
    if (matchPages != null &&
        (matchPages is! List ||
            matchPages.length > 10000 ||
            matchPages.any((page) => page is! int || page < 1))) {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'reader.openBook.matchPages must be a list of positive page numbers',
      );
    }
    final matchedTerms = args['matchedTerms'];
    if (matchedTerms != null &&
        (matchedTerms is! List ||
            matchedTerms.length > 64 ||
            matchedTerms.any(
              (term) => term is! String || term.isEmpty || term.length > 256,
            ))) {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'reader.openBook.matchedTerms must be a list of short strings',
      );
    }
  }

  void _requiredShortString(Object? value, String context, int maxLength) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > maxLength ||
        _hasControlChars(value)) {
      throw DeclarativeProgramException(
        'declarative.invalid_args',
        '$context must be a non-empty string of up to $maxLength characters',
      );
    }
  }

  void _optionalBool(Object? value, String context) {
    if (value != null && value is! bool) {
      throw DeclarativeProgramException(
        'declarative.invalid_args',
        '$context must be a boolean',
      );
    }
  }

  void _validateStorageArgs(
    Map<String, dynamic> args, {
    required bool requiresValue,
  }) {
    final key = args['key'];
    if (key is! String ||
        key.isEmpty ||
        key.length > 128 ||
        _hasControlChars(key)) {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'storage key must be a non-empty string of up to 128 characters',
      );
    }
    if (!requiresValue) return;
    if (args['value'] == null) {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'storage.set.value must not be null',
      );
    }
    _validateStorageValue(args['value']);
  }

  void _validateStorageValue(Object? value) {
    var nodes = 0;
    void visit(Object? current, int depth) {
      nodes++;
      if (nodes > 256 || depth > 10) {
        throw const DeclarativeProgramException(
          'declarative.value_too_large',
          'storage.set.value is limited in size and nesting depth',
        );
      }
      if (current is Map) {
        for (final entry in current.entries) {
          if (entry.key is! String) {
            throw const DeclarativeProgramException(
              'declarative.invalid_args',
              'storage.set.value object keys must be strings',
            );
          }
          visit(entry.value, depth + 1);
        }
        return;
      }
      if (current is List) {
        for (final child in current) {
          visit(child, depth + 1);
        }
        return;
      }
      if (current == null || current is num || current is bool) return;
      if (current is String &&
          current.length <= 4096 &&
          !_hasControlChars(current)) {
        return;
      }
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'storage.set.value must contain small JSON values only',
      );
    }

    visit(value, 0);
  }

  bool _hasControlChars(String value) {
    for (final unit in value.codeUnits) {
      if (unit < 0x20 || unit == 0x7F) return true;
    }
    return false;
  }

  Map<String, dynamic> _requiredMap(Object? value, String context) {
    if (value is! Map) {
      throw DeclarativeProgramException(
        'declarative.invalid_action',
        '$context must be an object',
      );
    }
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      throw DeclarativeProgramException(
        'declarative.invalid_action',
        '$context keys must be strings',
      );
    }
  }

  String _requiredString(Object? value, String context) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 4096 ||
        RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value)) {
      throw DeclarativeProgramException(
        'declarative.invalid_action',
        '$context must be a valid non-empty string',
      );
    }
    return value;
  }

  void _requiredIdentityId(Object? value, String context) {
    if (value is String && value.isNotEmpty) {
      _requiredString(value, context);
      return;
    }
    if (value is int) return;
    throw DeclarativeProgramException(
      'declarative.invalid_action',
      '$context must be an integer or a non-empty string',
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
