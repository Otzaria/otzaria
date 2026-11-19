import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/navigation/view/tab_context_menu.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/theme/app_motion.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart'
    show AppMenuMetrics;
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/text/app_section_label.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
import 'package:otzaria/theme/app_shadows.dart';

const double _kMenuWidth = 320;
const double _kMenuMaxHeight = 420;

/// כפתור "חיפוש כרטיסיות" — חץ מטה בקצה רצועת הכרטיסיות, בנוסח דפדפן.
class TabSearchButton extends StatelessWidget {
  const TabSearchButton({super.key, this.tapTargetSize});

  /// ראו [AppIconButton.tapTargetSize].
  final MaterialTapTargetSize? tapTargetSize;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchorContext) => AppIconButton(
        icon: const Icon(FluentIcons.chevron_down_24_regular),
        size: AppIconButtonSize.small,
        tapTargetSize: tapTargetSize,
        tooltip: context.settingsText('חיפוש כרטיסיות'),
        onPressed: () =>
            showTabSearchMenu(context, anchorContext: anchorContext),
      ),
    );
  }
}

/// החלונית הפתוחה כרגע בכל חלון, אם יש. הקיצור עשוי להילחץ שוב לפני שנסגרה.
final _openRoutes = Expando<_TabSearchRoute>();

/// האם חלונית חיפוש הכרטיסיות היא ה-route העליון בחלון של [context].
bool isTabSearchMenuOnTop(BuildContext context) =>
    _openRoutes[AppWindowKeys.of(context)]?.isCurrent ?? false;

/// פותח את חלונית חיפוש הכרטיסיות, וסוגר אותה אם היא כבר פתוחה. בלי
/// [anchorContext] היא נפתחת ממורכזת בראש החלון — כך גם קיצור המקלדת מגיע
/// אליה בלי כפתור מוצג.
Future<void> showTabSearchMenu(
  BuildContext context, {
  BuildContext? anchorContext,
}) {
  // חלונית שכבר אינה פעילה (הניווט שלה פורק) אינה חוסמת פתיחה חדשה.
  final keys = AppWindowKeys.of(context);
  final open = _openRoutes[keys];
  _openRoutes[keys] = null;
  if (open != null && open.isActive) {
    open.navigator?.removeRoute(open);
    return Future<void>.value();
  }

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final overlaySize = overlay.size;

  Rect? anchorRect;
  final anchorBox = anchorContext?.findRenderObject() as RenderBox?;
  if (anchorBox != null && anchorBox.hasSize) {
    anchorRect = MatrixUtils.transformRect(
      anchorBox.getTransformTo(overlay),
      Offset.zero & anchorBox.size,
    );
  }

  final width = min(_kMenuWidth, overlaySize.width - 16);
  final top = (anchorRect?.bottom ?? 8) + 4;
  final height = min(_kMenuMaxHeight, max(120.0, overlaySize.height - top - 8));
  // ב-RTL הקצה הימני של החלונית מיושר לקצה הימני של הכפתור; אם ההתרחבות
  // חורגת מהחלון, החלונית נדחפת פנימה.
  final rawLeft = anchorRect == null
      ? (overlaySize.width - width) / 2
      : anchorRect.right - width;
  final left = rawLeft
      .clamp(0.0, max(0.0, overlaySize.width - width))
      .toDouble();

  final route = _TabSearchRoute(
    rect: Rect.fromLTWH(left, top, width, height),
    tabsBloc: context.read<TabsBloc>(),
    transitionDuration: AppMotion.duration(
      context,
      const Duration(milliseconds: 100),
    ),
  );
  _openRoutes[keys] = route;
  return Navigator.of(context).push<void>(route).whenComplete(() {
    if (identical(_openRoutes[keys], route)) _openRoutes[keys] = null;
  });
}

class _TabSearchRoute extends PopupRoute<void> {
  final Rect rect;
  final TabsBloc tabsBloc;

  _TabSearchRoute({
    required this.rect,
    required this.tabsBloc,
    required this.transitionDuration,
  });

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  final Duration transitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: FadeTransition(
            opacity: animation,
            // המסלול נדחף מעל ה-Navigator, ולכן ה-bloc מסופק לו מפורשות.
            // לחיצה בחלונית (למשל על X) משאירה את הפוקוס, וכך את החיצים, בשדה.
            child: TextFieldTapRegion(
              child: BlocProvider<TabsBloc>.value(
                value: tabsBloc,
                child: const TabSearchPanel(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// חלונית חיפוש הכרטיסיות: שדה חיפוש, הכרטיסיות הפתוחות, והנסגרות לאחרונה.
class TabSearchPanel extends StatefulWidget {
  const TabSearchPanel({super.key});

  @override
  State<TabSearchPanel> createState() => _TabSearchPanelState();
}

class _TabSearchPanelState extends State<TabSearchPanel> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  /// הרשומה שסומנה בחיצים (הפתוחות ואחריהן הנסגרות); ‎-1 — אין סימון.
  int _highlighted = -1;
  List<VoidCallback> _entryActions = const [];
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  int _openEntryCount = 0;
  late final _fieldFocus = FocusNode(onKeyEvent: _handleFieldKey);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_query == _controller.text) return;
      setState(() {
        _query = _controller.text;
        _highlighted = -1;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  bool _matches(OpenedTab tab) =>
      _query.isEmpty ||
      tab.title.toLowerCase().contains(_query.trim().toLowerCase());

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _selectTab(OpenedTab tab) {
    final bloc = context.read<TabsBloc>();
    final index = bloc.state.tabs.indexOf(tab);
    if (index != -1) bloc.add(SetCurrentTab(index));
    _close();
  }

  void _restoreTab(OpenedTab tab) {
    context.read<TabsBloc>().add(RestoreClosedTab(tab));
    _close();
  }

  /// חיצים ו-Enter בשדה, כמו ברשימות ההיסטוריה והסימניות: הפוקוס נשאר בשדה.
  KeyEventResult _handleFieldKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final int target;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        if (_entryActions.isEmpty) return KeyEventResult.handled;
        target = min(_highlighted + 1, _entryActions.length - 1);
      case LogicalKeyboardKey.arrowUp when _highlighted >= 0:
        target = _highlighted - 1;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when _highlighted >= 0:
        _entryActions[_highlighted]();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
    setState(() => _highlighted = target);
    _ensureHighlightedVisible();
    return KeyEventResult.handled;
  }

  void _ensureHighlightedVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _highlighted < 0 || !_itemScrollController.isAttached) {
        return;
      }
      final rowIndex =
          _highlighted +
          1 +
          (_openEntryCount > 0 && _highlighted >= _openEntryCount ? 1 : 0);
      for (final position in _itemPositionsListener.itemPositions.value) {
        if (position.index == rowIndex &&
            position.itemLeadingEdge >= 0 &&
            position.itemTrailingEdge <= 1) {
          return;
        }
      }
      // הרשומה עשויה להיות מחוץ לעץ אחרי גלילה ידנית.
      _itemScrollController.jumpTo(index: rowIndex, alignment: 0.4);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      elevation: AppTokens.elevation2,
      shadowColor: AppShadows.color(cs),
      shape: AppSurfaces.raisedShape(context),
      color: Theme.of(context).popupMenuTheme.color ?? cs.surface,
      clipBehavior: Clip.antiAlias,
      child: BlocBuilder<TabsBloc, TabsState>(
        builder: (context, state) {
          final openTabs = state.tabs.where(_matches).toList();
          final closedTabs = context
              .read<TabsBloc>()
              .recentlyClosedTabs
              .where(_matches)
              .toList();
          _entryActions = [
            for (final tab in openTabs) () => _selectTab(tab),
            for (final tab in closedTabs) () => _restoreTab(tab),
          ];
          // סינון או סגירה עשויים לקצר את הרשימה מתחת לסימון.
          _highlighted = min(_highlighted, _entryActions.length - 1);
          _openEntryCount = openTabs.length;
          final rows = <Widget>[
            if (openTabs.isNotEmpty) ...[
              _SectionHeader(label: context.settingsText('כרטיסיות פתוחות')),
              for (final (i, tab) in openTabs.indexed)
                _TabRow(
                  tab: tab,
                  isCurrent: identical(tab, state.currentTab),
                  isHighlighted: i == _highlighted,
                  onTap: _entryActions[i],
                  trailingIcon: FluentIcons.dismiss_24_regular,
                  trailingTooltip: context.settingsText('סגור כרטיסייה'),
                  onTrailing: () => closeTabWithHistory(context, tab),
                ),
            ],
            if (closedTabs.isNotEmpty) ...[
              _SectionHeader(
                label: context.settingsText('נסגרו לאחרונה'),
                actionIcon: FluentIcons.broom_24_regular,
                actionTooltip: context.settingsText('נקה את הרשימה'),
                onAction: () => context.read<TabsBloc>().add(
                  const ClearRecentlyClosedTabs(),
                ),
              ),
              for (final (i, tab) in closedTabs.indexed)
                _TabRow(
                  tab: tab,
                  isCurrent: false,
                  isHighlighted: openTabs.length + i == _highlighted,
                  onTap: _entryActions[openTabs.length + i],
                  trailingIcon: FluentIcons.arrow_undo_24_regular,
                  trailingTooltip: context.settingsText('שחזר כרטיסייה'),
                  onTrailing: () =>
                      context.read<TabsBloc>().add(RestoreClosedTab(tab)),
                ),
            ],
          ];

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppTokens.spaceSM),
                child: OtzariaSearchField(
                  controller: _controller,
                  focusNode: _fieldFocus,
                  autofocus: true,
                  hintText: context.settingsText('חיפוש כרטיסיות'),
                  // הניקוי עצמו מאפס את הסינון דרך מאזין הבקר.
                  onClear: () {},
                ),
              ),
              Expanded(
                child: openTabs.isEmpty && closedTabs.isEmpty
                    ? OtzariaEmptyState(
                        isCompact: true,
                        icon: FluentIcons.tab_desktop_multiple_24_regular,
                        title: context.settingsText('אין כרטיסיות תואמות'),
                      )
                    : ScrollablePositionedList.builder(
                        padding: const EdgeInsets.only(
                          bottom: AppTokens.spaceSM,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (context, index) => rows[index],
                        itemScrollController: _itemScrollController,
                        itemPositionsListener: _itemPositionsListener,
                        estimateExtent: (_, _) => _rowExtent(context),
                      ),
              ),
              Divider(
                height: AppTokens.borderThin,
                color: AppSurfaces.subtleDivider(cs),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTokens.spaceXS),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ActionButton.ghost(
                    text: context.settingsText('הצג את כל ההיסטוריה'),
                    icon: FluentIcons.history_24_regular,
                    onPressed: _openHistory,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openHistory() {
    // הדיאלוג נפתח מה-Navigator עצמו: הקונטקסט של החלונית נהרס עם סגירתה.
    final navigator = Navigator.of(context);
    navigator.pop();
    showDialogUntilTornDown<void>(
      context: navigator.context,
      builder: (_) => const HistoryDialog(),
    );
  }
}

/// גובה שורה בחלונית: גובה פריט תפריט, ובמגע שטח לחיצה של 48.
double _rowHeight(BuildContext context) {
  final theme = Theme.of(context);
  final metrics =
      theme.extension<AppMenuMetrics>() ??
      AppMenuMetrics.create(compactMenus: false);
  final touch = theme.materialTapTargetSize == MaterialTapTargetSize.padded;
  return touch ? kMinInteractiveDimension : metrics.itemHeight;
}

/// גובה שורה כולל המרווח שבין שורות, להערכת הגלילה.
double _rowExtent(BuildContext context) =>
    _rowHeight(context) + 2 * AppTokens.space2XS;

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.label,
    this.actionIcon,
    this.actionTooltip,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final action = onAction;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppTokens.spaceMD,
        end: AppTokens.spaceXS,
        top: AppTokens.spaceSM,
        bottom: AppTokens.space2XS,
      ),
      child: Row(
        children: [
          Expanded(child: AppSectionLabel(label)),
          if (action != null)
            AppIconButton(
              icon: Icon(actionIcon),
              size: AppIconButtonSize.small,
              tooltip: actionTooltip ?? '',
              onPressed: action,
            ),
        ],
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  final OpenedTab tab;
  final bool isCurrent;

  final bool isHighlighted;
  final VoidCallback onTap;
  final IconData trailingIcon;
  final String trailingTooltip;
  final VoidCallback onTrailing;

  const _TabRow({
    required this.tab,
    required this.isCurrent,
    this.isHighlighted = false,
    required this.onTap,
    required this.trailingIcon,
    required this.trailingTooltip,
    required this.onTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final icon =
        buildTabTypeIcon(context, tab, color: cs.onSurfaceVariant) ??
        buildTabFallbackIcon(context, color: cs.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceXS,
        vertical: AppTokens.space2XS,
      ),
      child: Material(
        color: isCurrent ? AppSurfaces.selectedRow(cs) : Colors.transparent,
        borderRadius: AppTokens.borderRadiusAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            color: isHighlighted ? AppSurfaces.focusedRow(cs) : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: _rowHeight(context)),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppTokens.spaceSMD,
                  end: AppTokens.space2XS,
                ),
                child: Row(
                  children: [
                    icon,
                    const SizedBox(width: AppTokens.spaceSM),
                    Expanded(
                      child: Text(
                        tabTitleBesideContentIcon(tab, tab.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isCurrent
                              ? AppSurfaces.onSelectedRow(cs)
                              : cs.onSurface,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    AppIconButton(
                      icon: Icon(trailingIcon),
                      size: AppIconButtonSize.small,
                      tooltip: trailingTooltip,
                      onPressed: onTrailing,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
