import 'package:otzaria/plugins/declarative/compiler/declarative_action_compiler.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_value_checks.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/models/declarative_toolbar_template.dart';
import 'package:otzaria/plugins/declarative/repository/declarative_program_repository.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';

typedef DeclarativeToolbarBindingErrorHandler =
    void Function(String pluginId, Object error, StackTrace stackTrace);

class DeclarativeToolbarBindingService {
  final DeclarativeProgramRepository programRepository;
  final PluginToolbarRegistry toolbarRegistry;
  final DeclarativeToolbarBindingErrorHandler? onError;

  DeclarativeToolbarBindingService({
    required this.programRepository,
    required this.toolbarRegistry,
    this.onError,
  }) {
    programRepository.addListener(_rebuildAll);
  }

  final Map<String, _ToolbarRegistration> _registrations = {};

  void syncPlugin({
    required InstalledPlugin plugin,
    required List<CompiledDeclarativeToolbarTemplate> templates,
    required Set<String> grantedPermissions,
  }) {
    final previousIds = _registrations[plugin.pluginId]?.managedIds ?? const {};
    final nextIds = templates.map((template) => template.baseItem.id).toSet();
    toolbarRegistry.replaceManagedItems(
      plugin.pluginId,
      managedIds: {...previousIds, ...nextIds},
      items: const [],
    );
    if (!plugin.enabled || templates.isEmpty) {
      _registrations.remove(plugin.pluginId);
      return;
    }
    _registrations[plugin.pluginId] = _ToolbarRegistration(
      plugin: plugin,
      templates: List.unmodifiable(templates),
      managedIds: Set.unmodifiable(nextIds),
      grantedPermissions: Set.unmodifiable(grantedPermissions),
    );
    _rebuildPlugin(plugin.pluginId);
  }

  void removePlugin(String pluginId) {
    final registration = _registrations.remove(pluginId);
    if (registration == null) return;
    toolbarRegistry.replaceManagedItems(
      pluginId,
      managedIds: registration.managedIds,
      items: const [],
    );
  }

  void dispose() {
    programRepository.removeListener(_rebuildAll);
  }

  void _rebuildAll() {
    for (final pluginId in _registrations.keys.toList()) {
      _rebuildPlugin(pluginId);
    }
  }

  void _rebuildPlugin(String pluginId) {
    final registration = _registrations[pluginId];
    if (registration == null) return;
    final contextSignature = programRepository.getContextSignature(pluginId);
    if (contextSignature == null) {
      _replace(registration, const []);
      return;
    }
    try {
      final items = <PluginToolbarItem>[];
      for (final template in registration.templates) {
        final outputs = programRepository.getProgramOutputs(
          pluginId,
          template.programId,
        );
        if (outputs == null ||
            !isNotEmptyValue(readValuePath(outputs, template.visibleOutput))) {
          _replace(registration, const []);
          return;
        }
        items.add(
          _buildItem(
            registration,
            template,
            outputs,
            contextSignature,
          ),
        );
      }
      _replace(registration, items);
    } catch (error, stackTrace) {
      onError?.call(pluginId, error, stackTrace);
      _replace(registration, const []);
    }
  }

  PluginToolbarItem _buildItem(
    _ToolbarRegistration registration,
    CompiledDeclarativeToolbarTemplate template,
    Map<String, dynamic> outputs,
    String contextSignature,
  ) {
    final base = template.baseItem;
    final actionTemplate = template.actionTemplate;
    final primaryAction = actionTemplate == null
        ? null
        : _compileAction(
            registration.plugin,
            _resolveExpression(actionTemplate, outputs: outputs),
            contextSignature,
          );
    if (template.childrenBinding == null) {
      return PluginToolbarItem(
        id: base.id,
        type: 'button',
        title: base.title,
        icon: base.icon,
        contexts: base.contexts,
        hostAction: primaryAction,
        openPlugin: template.openPlugin,
        placement: base.placement,
        order: base.order,
        bookTypes: base.bookTypes,
        bookSources: base.bookSources,
      );
    }

    final binding = template.childrenBinding!;
    final sourceItems = readValuePath(outputs, binding.itemsOutput);
    if (sourceItems is! List || sourceItems.isEmpty) {
      throw const DeclarativeProgramException(
        'declarative.type_mismatch',
        'childrenBinding.itemsOutput must resolve to a non-empty list',
      );
    }
    final children = <PluginToolbarItem>[];
    for (final item in sourceItems.take(binding.maxItems)) {
      final resolved = _resolveExpression(
        binding.itemTemplate,
        outputs: outputs,
        item: item,
      );
      final childJson = Map<String, dynamic>.from(resolved as Map);
      final id = childJson['id'];
      final title = childJson['title'];
      final icon = childJson['icon'];
      if (id is! String ||
          title is! String ||
          (icon != null && icon is! String)) {
        throw const DeclarativeProgramException(
          'declarative.invalid_toolbar_item',
          'Resolved menu child requires string id and title',
        );
      }
      final action = _compileAction(
        registration.plugin,
        childJson['action'],
        contextSignature,
      );
      children.add(
        PluginToolbarItem(
          id: id,
          title: title,
          icon: icon as String?,
          contexts: base.contexts,
          hostAction: action,
        ),
      );
    }
    final menu = PluginToolbarItem(
      id: base.id,
      type: primaryAction == null ? 'menu' : 'split',
      title: base.title,
      icon: base.icon,
      contexts: base.contexts,
      children: children,
      hostAction: primaryAction,
      placement: base.placement,
      order: base.order,
      bookTypes: base.bookTypes,
      bookSources: base.bookSources,
    );
    PluginToolbarRegistry.detached().registerPayload(
      registration.plugin.pluginId,
      menu.toJson(),
    );
    return menu;
  }

  CompiledDeclarativeAction _compileAction(
    InstalledPlugin plugin,
    Object? value,
    String contextSignature,
  ) {
    if (value is! Map) {
      throw const DeclarativeProgramException(
        'declarative.invalid_action',
        'Resolved toolbar action must be an object',
      );
    }
    final action =
        DeclarativeActionCompiler(
          declaredPermissions: plugin.manifest.permissions.toSet(),
        ).compileResolved(
          Map<String, dynamic>.from(value),
          contextSignature: contextSignature,
          programGeneration: programRepository.getGeneration(plugin.pluginId),
        );
    final registration = _registrations[plugin.pluginId];
    if (registration == null ||
        !registration.grantedPermissions.contains(action.requiredPermission)) {
      throw DeclarativeProgramException(
        'declarative.permission_denied',
        'Action requires granted permission "${action.requiredPermission}"',
      );
    }
    return action;
  }

  Object? _resolveExpression(
    Object? value, {
    required Map<String, dynamic> outputs,
    Object? item,
  }) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.length == 1) {
        if (map.containsKey(r'$literal')) {
          return deepCopyValue(map[r'$literal']);
        }
        if (map.containsKey(r'$output')) {
          return readValuePath(outputs, map[r'$output'] as String);
        }
        if (map.containsKey(r'$item')) {
          return readValuePath(item, map[r'$item'] as String);
        }
        if (map.containsKey(r'$concat')) {
          return (map[r'$concat'] as List<dynamic>)
              .map(
                (part) => _resolveExpression(
                  part,
                  outputs: outputs,
                  item: item,
                ),
              )
              .map((part) => part?.toString() ?? '')
              .join();
        }
      }
      return {
        for (final entry in map.entries)
          entry.key: _resolveExpression(
            entry.value,
            outputs: outputs,
            item: item,
          ),
      };
    }
    if (value is List) {
      return [
        for (final child in value)
          _resolveExpression(child, outputs: outputs, item: item),
      ];
    }
    return value;
  }

  void _replace(
    _ToolbarRegistration registration,
    List<PluginToolbarItem> items,
  ) {
    toolbarRegistry.replaceManagedItems(
      registration.plugin.pluginId,
      managedIds: registration.managedIds,
      items: items,
    );
  }
}

class _ToolbarRegistration {
  final InstalledPlugin plugin;
  final List<CompiledDeclarativeToolbarTemplate> templates;
  final Set<String> managedIds;
  final Set<String> grantedPermissions;

  const _ToolbarRegistration({
    required this.plugin,
    required this.templates,
    required this.managedIds,
    required this.grantedPermissions,
  });
}
