import 'package:otzaria/plugins/declarative/commands/declarative_command_registry.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_value_checks.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';

class DeclarativeActionCompiler {
  /// תקרות אורך לפעולות שמזרימות טקסט של התוסף לממשק או לחיפוש.
  static const int maxRefLength = 256;
  static const int maxQueryLength = 500;
  static const int maxSnackLength = 200;

  /// תקרות לערכי JSON חופשיים (`storage.set.value`, `localService.post.body`)
  /// ולמפתחות אחסון.
  static const int maxJsonStringLength = 4096;
  static const int maxStorageKeyLength = 128;

  /// `localService.post`: נתיב קבוע (בלי query), גוף JSON קטן וזמן המתנה
  /// בגבולות של `network.fetchStream` (`PluginNetworkFetchService.maxTimeout`).
  static const int maxLocalServicePathLength = 256;
  static const int minLocalServiceTimeoutMs = 1000;
  static const int maxLocalServiceTimeoutMs = 120000;
  static final RegExp localServicePathPattern = RegExp(
    r'^/[A-Za-z0-9._~\-/]*$',
  );

  static const Set<String> snackSeverities = {'info', 'success', 'error'};

  final Set<String> declaredPermissions;

  const DeclarativeActionCompiler({required this.declaredPermissions});

  /// [allowMissingPort] — פעולת לחיצה, שבה `port` ריק (`$storage` שעוד לא
  /// נשמר) פירושו שהשירות לא עלה. בפקדים ובתכניות הוא נשאר שגיאה.
  CompiledDeclarativeAction compileResolved(
    Map<String, dynamic> json, {
    required String contextSignature,
    required int programGeneration,
    bool allowMissingPort = false,
  }) {
    assertOnlyKeys(json, const {'type', 'args'}, 'action');
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
      case 'localService.post':
        validateLocalServiceArgs(args, allowMissingPort: allowMissingPort);
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
      args: deepFreeze(args),
      requiredPermission: permission,
      contextSignature: contextSignature,
      programGeneration: programGeneration,
    );
  }

  void _validateOpenBookArgs(Map<String, dynamic> args) {
    final identity = _requiredMap(args['identity'], 'action.args.identity');
    assertOnlyKeys(
      identity,
      const {'id', 'bookId', 'type', 'source', 'external'},
      'action.args.identity',
    );
    final externalValue = identity['external'];
    Map<String, dynamic>? external;
    if (externalValue != null) {
      external = _requiredMap(externalValue, 'action.args.identity.external');
      assertOnlyKeys(
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

  /// היעד תמיד `http://127.0.0.1:<port><path>`: התוסף בוחר רק פורט ונתיב,
  /// ולכן אין דרך לבנות מכאן כתובת חיצונית. [allowMissingPort] — `port` ריק
  /// בפעולת לחיצה: המבצע מציג אז שהשירות אינו זמין.
  ///
  /// [template] — תבנית לחיצה שעוד לא נפתרה, בוולידציית ההתקנה: הפניה
  /// (`{"$storage": ...}` וכדומה) נבדקת רק בזמן הלחיצה, וכל ערך מילולי כבר
  /// עכשיו, כדי שהגדרה שגויה לא תיכשל בשקט בכל לחיצה.
  static void validateLocalServiceArgs(
    Map<String, dynamic> args, {
    bool template = false,
    bool allowMissingPort = false,
  }) {
    bool deferred(Object? value) => template && value is Map;

    final port = args['port'];
    if (!deferred(port) &&
        !(port == null && allowMissingPort && !template) &&
        (port is! int || port < 1 || port > 65535)) {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'localService.post.port must be an integer between 1 and 65535',
      );
    }
    final path = args['path'];
    if (!deferred(path) &&
        (path is! String ||
            path.length > maxLocalServicePathLength ||
            !localServicePathPattern.hasMatch(path) ||
            path.contains('//') ||
            path
                .split('/')
                .any((segment) => segment == '.' || segment == '..'))) {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'localService.post.path must be an absolute path such as '
            '"/text/search", without a query or dot segments',
      );
    }
    final body = args['body'];
    if (body != null) {
      if (body is! Map) {
        throw const DeclarativeProgramException(
          'declarative.invalid_args',
          'localService.post.body must be an object',
        );
      }
      // בתבנית, ערכי הגוף כבר נבדקו (DeclarativeSelectionAction); כאן אחרי
      // הפתרון.
      if (!template) _validateJsonValue(body, 'localService.post.body');
    }
    for (final field in const ['pendingMessage', 'unavailableMessage']) {
      if (args[field] != null && !deferred(args[field])) {
        _requiredShortString(
          args[field],
          'localService.post.$field',
          maxSnackLength,
        );
      }
    }
    final timeoutMs = args['timeoutMs'];
    if (timeoutMs != null &&
        !deferred(timeoutMs) &&
        (timeoutMs is! int ||
            timeoutMs < minLocalServiceTimeoutMs ||
            timeoutMs > maxLocalServiceTimeoutMs)) {
      throw DeclarativeProgramException(
        'declarative.invalid_args',
        'localService.post.timeoutMs must be an integer between '
            '$minLocalServiceTimeoutMs and $maxLocalServiceTimeoutMs',
      );
    }
  }

  static void _requiredShortString(
    Object? value,
    String context,
    int maxLength,
  ) {
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
        key.length > maxStorageKeyLength ||
        _hasControlChars(key)) {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'storage key must be a non-empty string of up to '
            '$maxStorageKeyLength characters',
      );
    }
    if (!requiresValue) return;
    if (args['value'] == null) {
      throw const DeclarativeProgramException(
        'declarative.invalid_args',
        'storage.set.value must not be null',
      );
    }
    _validateJsonValue(args['value'], 'storage.set.value');
  }

  static void _validateJsonValue(Object? value, String context) {
    var nodes = 0;
    void visit(Object? current, int depth) {
      nodes++;
      if (nodes > 256 || depth > 10) {
        throw DeclarativeProgramException(
          'declarative.value_too_large',
          '$context is limited in size and nesting depth',
        );
      }
      if (current is Map) {
        for (final entry in current.entries) {
          if (entry.key is! String) {
            throw DeclarativeProgramException(
              'declarative.invalid_args',
              '$context object keys must be strings',
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
          current.length <= maxJsonStringLength &&
          !_hasControlChars(current)) {
        return;
      }
      throw DeclarativeProgramException(
        'declarative.invalid_args',
        '$context must contain small JSON values only',
      );
    }

    visit(value, 0);
  }

  static bool _hasControlChars(String value) {
    for (final unit in value.codeUnits) {
      if (unit < 0x20 || unit == 0x7F) return true;
    }
    return false;
  }

  Map<String, dynamic> _requiredMap(Object? value, String context) =>
      requiredMap(value, context, code: 'declarative.invalid_action');

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
}
