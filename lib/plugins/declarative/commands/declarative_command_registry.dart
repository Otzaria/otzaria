import 'package:otzaria/plugins/declarative/models/declarative_program.dart';

class DeclarativeCommandDefinition {
  final String type;
  final DeclarativeCommandPhase phase;
  final String? requiredPermission;
  final Set<String> requiredArgs;
  final Set<String> optionalArgs;
  final DeclarativeValueKind outputKind;
  final Map<String, DeclarativeValueKind> outputPaths;

  const DeclarativeCommandDefinition({
    required this.type,
    required this.phase,
    required this.requiredPermission,
    required this.requiredArgs,
    this.optionalArgs = const {},
    required this.outputKind,
    this.outputPaths = const {},
  });

  DeclarativeValueKind kindAtPath(List<String> path) {
    if (path.isEmpty) return outputKind;
    return outputPaths[path.join('.')] ?? DeclarativeValueKind.any;
  }
}

class DeclarativeCommandRegistry {
  static const Map<String, DeclarativeCommandDefinition> definitions = {
    'database.select': DeclarativeCommandDefinition(
      type: 'database.select',
      phase: DeclarativeCommandPhase.computation,
      requiredPermission: 'database.read',
      requiredArgs: {'sourceId', 'from', 'select'},
      optionalArgs: {
        'joins',
        'where',
        'orderBy',
        'limit',
        'offset',
        'rowFormat',
      },
      outputKind: DeclarativeValueKind.map,
      outputPaths: {
        'rows': DeclarativeValueKind.list,
        'columns': DeclarativeValueKind.list,
        'meta': DeclarativeValueKind.map,
      },
    ),
    'data.first': DeclarativeCommandDefinition(
      type: 'data.first',
      phase: DeclarativeCommandPhase.computation,
      requiredPermission: null,
      requiredArgs: {'items'},
      outputKind: DeclarativeValueKind.any,
    ),
    'data.choose': DeclarativeCommandDefinition(
      type: 'data.choose',
      phase: DeclarativeCommandPhase.computation,
      requiredPermission: null,
      requiredArgs: {'condition', 'whenTrue', 'whenFalse'},
      outputKind: DeclarativeValueKind.any,
    ),
    'data.map': DeclarativeCommandDefinition(
      type: 'data.map',
      phase: DeclarativeCommandPhase.computation,
      requiredPermission: null,
      requiredArgs: {'items', 'template'},
      optionalArgs: {'maxItems'},
      outputKind: DeclarativeValueKind.list,
    ),
    'settings.get': DeclarativeCommandDefinition(
      type: 'settings.get',
      phase: DeclarativeCommandPhase.computation,
      requiredPermission: 'settings.read',
      requiredArgs: {'key'},
      outputKind: DeclarativeValueKind.any,
    ),
    'storage.get': DeclarativeCommandDefinition(
      type: 'storage.get',
      phase: DeclarativeCommandPhase.computation,
      requiredPermission: 'plugin.storage.read',
      requiredArgs: {'key'},
      outputKind: DeclarativeValueKind.any,
    ),
    'library.resolveBooks': DeclarativeCommandDefinition(
      type: 'library.resolveBooks',
      phase: DeclarativeCommandPhase.computation,
      requiredPermission: 'library.books.read',
      requiredArgs: {'items', 'identity'},
      optionalArgs: {'keepInputFields', 'limit'},
      outputKind: DeclarativeValueKind.list,
    ),
    'library.parallelEditions': DeclarativeCommandDefinition(
      type: 'library.parallelEditions',
      phase: DeclarativeCommandPhase.computation,
      requiredPermission: 'library.books.read',
      requiredArgs: {'identity'},
      optionalArgs: {},
      outputKind: DeclarativeValueKind.list,
    ),
    'reader.openBook': DeclarativeCommandDefinition(
      type: 'reader.openBook',
      phase: DeclarativeCommandPhase.action,
      requiredPermission: 'reader.open',
      requiredArgs: {'identity'},
      optionalArgs: {'index', 'searchQuery', 'matchPages', 'matchedTerms'},
      outputKind: DeclarativeValueKind.any,
    ),
    'reader.openBookInSidePane': DeclarativeCommandDefinition(
      type: 'reader.openBookInSidePane',
      phase: DeclarativeCommandPhase.action,
      requiredPermission: 'reader.open',
      requiredArgs: {'identity'},
      optionalArgs: {'index', 'searchQuery', 'matchPages', 'matchedTerms'},
      outputKind: DeclarativeValueKind.any,
    ),
    'storage.set': DeclarativeCommandDefinition(
      type: 'storage.set',
      phase: DeclarativeCommandPhase.action,
      requiredPermission: 'plugin.storage.write',
      requiredArgs: {'key', 'value'},
      outputKind: DeclarativeValueKind.any,
    ),
    'reader.scrollToRef': DeclarativeCommandDefinition(
      type: 'reader.scrollToRef',
      phase: DeclarativeCommandPhase.action,
      requiredPermission: 'reader.open',
      requiredArgs: {'ref'},
      optionalArgs: {'highlight'},
      outputKind: DeclarativeValueKind.any,
    ),
    'search.open': DeclarativeCommandDefinition(
      type: 'search.open',
      phase: DeclarativeCommandPhase.action,
      requiredPermission: 'reader.open',
      requiredArgs: {'query'},
      optionalArgs: {'autoSearch'},
      outputKind: DeclarativeValueKind.any,
    ),
    'ui.showSnack': DeclarativeCommandDefinition(
      type: 'ui.showSnack',
      phase: DeclarativeCommandPhase.action,
      requiredPermission: 'notifications.send',
      requiredArgs: {'message'},
      optionalArgs: {'severity'},
      outputKind: DeclarativeValueKind.any,
    ),
    'storage.remove': DeclarativeCommandDefinition(
      type: 'storage.remove',
      phase: DeclarativeCommandPhase.action,
      requiredPermission: 'plugin.storage.write',
      requiredArgs: {'key'},
      outputKind: DeclarativeValueKind.any,
    ),
  };

  static DeclarativeCommandDefinition require(String type) {
    final definition = definitions[type];
    if (definition == null) {
      throw DeclarativeProgramException(
        'declarative.unknown_command',
        'Unknown declarative command "$type"',
      );
    }
    return definition;
  }
}
