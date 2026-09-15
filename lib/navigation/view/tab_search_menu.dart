import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/navigation/view/tab_context_menu.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

const double _kMenuWidth = 320;
const double _kMenuMaxHeight = 420;
const double _kRowHeight = 32;

/// כפתור "חיפוש כרטיסיות" — חץ מטה בקצה רצועת הכרטיסיות, בנוסח דפדפן.
class TabSearchButton extends StatelessWidget {
  final double iconSize;
  final ButtonStyle? style;

  const TabSearchButton({super.key, this.iconSize = 18, this.style});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchorContext) => IconButton(
        icon: Icon(FluentIcons.chevron_down_24_regular, size: iconSize),
        tooltip: context.settingsText('חיפוש כרטיסיות'),
        style: style,
        visualDensity: style == null ? VisualDensity.compact : null,
        onPressed: () =>
            showTabSearchMenu(context, anchorContext: anchorContext),
      ),
    );
  }
}

/// החלונית הפתוחה כרגע, אם יש. הקיצור עשוי להילחץ שוב לפני שהיא נסגרה.
_TabSearchRoute? _openRoute;

/// פותח את חלונית חיפוש הכרטיסיות, וסוגר אותה אם היא כבר פתוחה. בלי
/// [anchorContext] היא נפתחת ממורכזת בראש החלון — כך גם קיצור המקלדת מגיע
/// אליה בלי כפתור מוצג.
Future<void> showTabSearchMenu(
  BuildContext context, {
  BuildContext? anchorContext,
}) {
  // חלונית שכבר אינה פעילה (הניווט שלה פורק) אינה חוסמת פתיחה חדשה.
  final open = _openRoute;
  _openRoute = null;
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
  );
  _openRoute = route;
  return Navigator.of(context).push<void>(route).whenComplete(() {
    if (identical(_openRoute, route)) _openRoute = null;
  });
}

class _TabSearchRoute extends PopupRoute<void> {
  final Rect rect;
  final TabsBloc tabsBloc;

  _TabSearchRoute({required this.rect, required this.tabsBloc});

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 100);

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
            child: BlocProvider<TabsBloc>.value(
              value: tabsBloc,
              child: const TabSearchPanel(),
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_query == _controller.text) return;
      setState(() => _query = _controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _matches(OpenedTab tab) =>
      _query.isEmpty ||
      tab.title.toLowerCase().contains(_query.trim().toLowerCase());

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      elevation: 8,
      borderRadius: AppTokens.borderRadiusAll,
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

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: RtlTextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: context.settingsText('חיפוש כרטיסיות'),
                    isDense: true,
                    prefixIcon: const Icon(
                      FluentIcons.search_24_regular,
                      size: 18,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: AppTokens.borderRadiusAll,
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: openTabs.isEmpty && closedTabs.isEmpty
                    ? OtzariaEmptyState(
                        isCompact: true,
                        icon: FluentIcons.tab_desktop_multiple_24_regular,
                        title: context.settingsText('אין כרטיסיות תואמות'),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(top: 2, bottom: 8),
                        children: [
                          if (openTabs.isNotEmpty) ...[
                            _SectionHeader(
                              label: context.settingsText('כרטיסיות פתוחות'),
                            ),
                            for (final tab in openTabs)
                              _TabRow(
                                tab: tab,
                                isCurrent: identical(tab, state.currentTab),
                                onTap: () {
                                  final index = context
                                      .read<TabsBloc>()
                                      .state
                                      .tabs
                                      .indexOf(tab);
                                  if (index != -1) {
                                    context.read<TabsBloc>().add(
                                      SetCurrentTab(index),
                                    );
                                  }
                                  _close();
                                },
                                trailingIcon: FluentIcons.dismiss_24_regular,
                                trailingTooltip: context.settingsText(
                                  'סגור כרטיסיה',
                                ),
                                // הרשימה נבנית מחדש מה-BlocBuilder, ולכן
                                // השורה נעלמת והחלונית נשארת פתוחה.
                                onTrailing: () =>
                                    closeTabWithHistory(context, tab),
                              ),
                          ],
                          if (closedTabs.isNotEmpty) ...[
                            _SectionHeader(
                              label: context.settingsText('נסגרו לאחרונה'),
                            ),
                            for (final tab in closedTabs)
                              _TabRow(
                                tab: tab,
                                isCurrent: false,
                                onTap: () {
                                  context.read<TabsBloc>().add(
                                    RestoreClosedTab(tab),
                                  );
                                  _close();
                                },
                                trailingIcon: FluentIcons.arrow_undo_24_regular,
                                trailingTooltip: context.settingsText(
                                  'שחזר כרטיסיה',
                                ),
                                onTrailing: () => context.read<TabsBloc>().add(
                                  RestoreClosedTab(tab),
                                ),
                              ),
                          ],
                        ],
                      ),
              ),
              const Divider(height: 1),
              _HistoryFooter(onTap: _openHistory),
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
    showDialog(
      context: navigator.context,
      builder: (_) => const HistoryDialog(),
    );
  }
}

class _HistoryFooter extends StatelessWidget {
  final VoidCallback onTap;

  const _HistoryFooter({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              FluentIcons.history_24_regular,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              context.settingsText('הצג את כל ההיסטוריה'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  final OpenedTab tab;
  final bool isCurrent;
  final VoidCallback onTap;
  final IconData trailingIcon;
  final String trailingTooltip;
  final VoidCallback onTrailing;

  const _TabRow({
    required this.tab,
    required this.isCurrent,
    required this.onTap,
    required this.trailingIcon,
    required this.trailingTooltip,
    required this.onTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon =
        buildTabTypeIcon(context, tab, color: cs.onSurfaceVariant) ??
        buildTabFallbackIcon(context, color: cs.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Material(
        color: isCurrent ? cs.secondaryContainer : Colors.transparent,
        borderRadius: AppTokens.borderRadiusAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: _kRowHeight,
            padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: isCurrent
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(trailingIcon, size: 14),
                  tooltip: trailingTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: onTrailing,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
