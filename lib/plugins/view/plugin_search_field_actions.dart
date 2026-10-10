import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';

/// כפתורי התוספים בתוך שדה חיפוש [field]. ריק כשאין תוסף שתרם כפתור לשדה.
///
/// הווידג'ט הוא צד השדה בסשן: הוא כותב לשדה את מה שהתוסף שולח, מדווח על
/// עריכה של המשתמש, וסוגר את הסשן כשהשדה נסגר.
class PluginSearchFieldActions extends StatefulWidget {
  final PluginSearchField field;
  final TextEditingController controller;

  /// מופעל אחרי שהתוסף כתב לשדה, כדי שהשדה יגיב כמו להקלדה.
  final ValueChanged<String>? onChanged;

  /// מופעל כשהתוסף מסיים סשן עם `submit: true`.
  final ValueChanged<String>? onSubmitted;
  final double buttonSize;
  final double iconSize;

  @visibleForTesting
  final PluginSearchFieldActionsRegistry? registry;
  @visibleForTesting
  final PluginSearchFieldSessionService? sessions;

  const PluginSearchFieldActions({
    super.key,
    required this.field,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.buttonSize = 32,
    this.iconSize = 20,
    this.registry,
    this.sessions,
  });

  @override
  State<PluginSearchFieldActions> createState() =>
      _PluginSearchFieldActionsState();
}

class _PluginSearchFieldActionsState extends State<PluginSearchFieldActions>
    implements PluginSearchFieldBinding {
  PluginSearchFieldActionsRegistry get _registry =>
      widget.registry ?? PluginSearchFieldActionsRegistry.instance;
  PluginSearchFieldSessionService get _sessions =>
      widget.sessions ?? PluginSearchFieldSessionService.instance;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(PluginSearchFieldActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _sessions.onBindingDisposed(this);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _sessions.onBindingDisposed(this);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!_sessions.hasSessionsFor(this)) return;
    _sessions.onFieldTextChanged(this, widget.controller.text);
  }

  @override
  PluginSearchField get field => widget.field;

  @override
  TextEditingValue get currentValue => widget.controller.value;

  @override
  void applyPluginText(TextEditingValue value) {
    widget.controller.value = value;
    widget.onChanged?.call(value.text);
  }

  @override
  void submit() => widget.onSubmitted?.call(widget.controller.text);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_registry, _sessions]),
      builder: (context, _) {
        final actions = _registry.actionsFor(widget.field);
        if (actions.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (pluginId, action) in actions)
              _buildButton(context, pluginId, action),
          ],
        );
      },
    );
  }

  Widget _buildButton(
    BuildContext context,
    String pluginId,
    PluginSearchFieldAction action,
  ) {
    final cs = Theme.of(context).colorScheme;
    final session = _sessions.sessionFor(this, pluginId, action.id);
    final state = session?.state ?? PluginSearchFieldActionState.idle;
    final icon =
        pluginIconFromName(action.icon) ?? FluentIcons.puzzle_piece_24_regular;
    final activeIcon = pluginIconFromName(action.activeIcon) ?? icon;
    final Widget glyph = switch (state) {
      PluginSearchFieldActionState.busy => SizedBox.square(
        dimension: widget.iconSize * 0.8,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      PluginSearchFieldActionState.active => Icon(
        activeIcon,
        size: widget.iconSize,
      ),
      PluginSearchFieldActionState.idle => Icon(icon, size: widget.iconSize),
    };
    return SizedBox(
      width: widget.buttonSize,
      height: widget.buttonSize,
      child: IconButton(
        key: ValueKey('plugin-search-field-action:$pluginId:${action.id}'),
        icon: glyph,
        tooltip: session?.tooltip ?? action.title,
        isSelected: session != null,
        color: session != null ? cs.primary : cs.onSurfaceVariant,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: () => _sessions.press(
          binding: this,
          pluginId: pluginId,
          actionId: action.id,
        ),
      ),
    );
  }
}
