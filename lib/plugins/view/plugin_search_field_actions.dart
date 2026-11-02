import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/plugins/models/plugin_library_books_filter.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

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

  /// ההקשר שנשלח לתוסף עם `search.fieldAction.invoked`, נבנה בלחיצה.
  final Map<String, dynamic> Function()? invocationContext;

  @visibleForTesting
  final PluginSearchFieldActionsRegistry? registry;
  @visibleForTesting
  final PluginSearchFieldSessionService? sessions;
  @visibleForTesting
  final PluginLibraryBooksRegistry? libraryBooks;

  const PluginSearchFieldActions({
    super.key,
    required this.field,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.buttonSize = 32,
    this.iconSize = 20,
    this.invocationContext,
    this.registry,
    this.sessions,
    this.libraryBooks,
  });

  @override
  State<PluginSearchFieldActions> createState() =>
      _PluginSearchFieldActionsState();
}

class _PluginSearchFieldActionsState extends State<PluginSearchFieldActions>
    implements PluginSearchFieldBinding, PluginSearchFieldContextSource {
  PluginSearchFieldActionsRegistry get _registry =>
      widget.registry ?? PluginSearchFieldActionsRegistry.instance;
  PluginSearchFieldSessionService get _sessions =>
      widget.sessions ?? PluginSearchFieldSessionService.instance;
  PluginLibraryBooksRegistry get _libraryBooks =>
      widget.libraryBooks ?? PluginLibraryBooksRegistry.instance;

  // הכפתור יושב בתוך השדה, ובדסקטופ השדה מזיז את הסמן כבר ב-tap down (לפני
  // onPressed). הסשן צריך את הבחירה שהייתה ברגע הלחיצה.
  ({
    PointerEvent pointer,
    TextEditingController controller,
    PluginSearchFieldAction action,
    TextEditingValue value,
  })?
  _pointerSelection;

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
  Map<String, dynamic> get invocationContext =>
      widget.invocationContext?.call() ?? const {};

  /// כפתור עם סשן פתוח נשאר גלוי גם כשהטקסט התרוקן, כדי שאפשר יהיה לעצור אותו.
  bool _isShown(String pluginId, PluginSearchFieldAction action) =>
      (action.isVisibleFor(widget.controller.text) ||
          _sessions.sessionFor(this, pluginId, action.id) != null) &&
      (!action.isProviderBooksFilter || _libraryBooks.hasProviderFor(pluginId));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _registry,
        _sessions,
        if (widget.field == PluginSearchField.library) ...[
          _libraryBooks,
          _libraryBooks.sourceFilter,
        ],
      ]),
      builder: (context, _) {
        final registered = _registry.actionsFor(widget.field);
        // האזנה לכל הקשה רק כשיש כפתור שתלוי בטקסט.
        if (!registered.any((entry) => entry.$2.showOnlyWithText)) {
          return _buildRow(context, registered);
        }
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => _buildRow(context, registered),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    List<(String, PluginSearchFieldAction)> registered,
  ) {
    final actions = [
      for (final (pluginId, action) in registered)
        if (_isShown(pluginId, action)) (pluginId, action),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (pluginId, action) in actions)
          action.isProviderBooksFilter
              ? _buildFilterButton(context, pluginId, action)
              : _buildButton(context, pluginId, action),
      ],
    );
  }

  Widget _buildFilterButton(
    BuildContext context,
    String pluginId,
    PluginSearchFieldAction action,
  ) {
    final source = _libraryBooks.sourceFilter.value.sourceFor(pluginId);
    final icon =
        pluginIconFromName(action.icon) ?? FluentIcons.puzzle_piece_24_regular;
    final (iconData, state) = switch (source) {
      PluginLibraryBooksSource.all => (
        icon,
        context.settingsText('מציג את כולם'),
      ),
      PluginLibraryBooksSource.pluginOnly => (
        pluginIconFromName(action.activeIcon) ?? icon,
        context.settingsText('מציג רק ספרי התוסף'),
      ),
      PluginLibraryBooksSource.libraryOnly => (
        pluginIconFromName(action.libraryOnlyIcon) ?? icon,
        context.settingsText('מציג רק ספרי הספרייה'),
      ),
    };
    return _iconButton(
      context,
      key: ValueKey('plugin-search-field-action:$pluginId:${action.id}'),
      glyph: Icon(iconData, size: widget.iconSize),
      tooltip: '${action.title}: $state',
      selected: source != PluginLibraryBooksSource.all,
      onPressed: () => _libraryBooks.cycleSource(pluginId),
    );
  }

  Widget _iconButton(
    BuildContext context, {
    required Key key,
    required Widget glyph,
    required String tooltip,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: widget.buttonSize,
      height: widget.buttonSize,
      child: IconButton(
        key: key,
        icon: glyph,
        tooltip: tooltip,
        isSelected: selected,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildButton(
    BuildContext context,
    String pluginId,
    PluginSearchFieldAction action,
  ) {
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
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kPrimaryButton &&
            _pointerSelection?.pointer.down != true) {
          _pointerSelection = (
            pointer: event,
            controller: widget.controller,
            action: action,
            value: widget.controller.value,
          );
        }
      },
      onPointerCancel: (event) {
        if (_pointerSelection?.pointer.pointer == event.pointer) {
          _pointerSelection = null;
        }
      },
      onPointerUp: (event) {
        final pending = _pointerSelection;
        if (pending == null || pending.pointer.pointer != event.pointer) return;
        final released = (
          pointer: event,
          controller: pending.controller,
          action: pending.action,
          value: pending.value,
        );
        _pointerSelection = released;
        // onPressed רץ בסיום הפצת ה-pointer up, לפני המיקרוטאסק.
        scheduleMicrotask(() {
          if (identical(_pointerSelection?.pointer, event)) {
            _pointerSelection = null;
          }
        });
      },
      child: _iconButton(
        context,
        key: ValueKey('plugin-search-field-action:$pluginId:${action.id}'),
        glyph: glyph,
        tooltip: session?.tooltip ?? action.title,
        selected: session != null,
        onPressed: () {
          final gesture = _pointerSelection;
          if (gesture != null &&
              gesture.pointer is PointerUpEvent &&
              identical(gesture.controller, widget.controller) &&
              identical(gesture.action, action) &&
              gesture.value.text == widget.controller.text) {
            widget.controller.selection = gesture.value.selection;
          }
          _pointerSelection = null;
          _sessions.press(
            binding: this,
            viewId: View.of(context).viewId,
            windowKeys: AppWindowKeys.of(context),
            pluginId: pluginId,
            actionId: action.id,
          );
        },
      ),
    );
  }
}
