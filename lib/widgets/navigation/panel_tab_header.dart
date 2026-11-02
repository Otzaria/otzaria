import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/app_motion.dart';
import 'package:otzaria/theme/app_shadows.dart';

/// טאב סטנדרטי לפנלים הימניים (ללא אייקון filled).
/// כאשר [label] הוא null — מוצג אייקון בלבד (מצב compact).
class PanelTab extends StatelessWidget {
  final IconData icon;
  final String? label;

  const PanelTab({super.key, required this.icon, this.label});

  @override
  Widget build(BuildContext context) =>
      buildTab(Icon(icon, size: AppTokens.panelTabIconSize), label);

  /// הטאב עם אייקון כלשהו — גם האייקון המונפש של `NavPanelTabHeader`.
  static Tab buildTab(Widget icon, String? label) {
    if (label == null) {
      return Tab(icon: icon, height: AppTokens.panelTabHeight);
    }
    return Tab(
      icon: icon,
      iconMargin: AppTokens.panelTabIconMargin,
      height: AppTokens.panelTabHeight,
      child: Text(
        label,
        style: const TextStyle(fontSize: AppTokens.panelTabFontSize),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// כפתור "פתח פאנל" — רצועה מונפשת בשולי המסך שמתרחבת עם hover.
class PanelOpenHandle extends StatefulWidget {
  final VoidCallback onTap;

  const PanelOpenHandle({super.key, required this.onTap});

  @override
  State<PanelOpenHandle> createState() => _PanelOpenHandleState();
}

class _PanelOpenHandleState extends State<PanelOpenHandle> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppTokens.animPanelOpacity),
          curve: Curves.easeOut,
          width: _isHovering ? 48 : 20,
          height: 80,
          decoration: ShapeDecoration(
            color: AppSurfaces.panelOpenHandle(cs, isHovering: _isHovering),
            shape: const _PanelOpenHandleBorder(),
            shadows: AppShadows.floating(cs),
          ),
          child: Center(
            child: AnimatedOpacity(
              duration: AppMotion.duration(context, AppTokens.animFast),
              opacity: _isHovering ? 1.0 : 0.6,
              child: Icon(
                FluentIcons.chevron_right_24_regular,
                size: _isHovering ? 24 : 18,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ב-Impeller, מלבן מעוגל שאחד מרדיוסיו גדול מחצי הרוחב מצויר עם "מדרגה" בפינות;
// לכן הצורה בנויה מקווים וקשתות — לא borderRadius ולא Path.addRRect (שמזוהה כמלבן מעוגל).
class _PanelOpenHandleBorder extends ShapeBorder {
  const _PanelOpenHandleBorder({this.radius = 40});

  final double radius;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    // אותו כיווץ רדיוס ש-RRect מבצע כשהידית צרה מהרדיוס.
    final r = math.min(radius, math.min(rect.width, rect.height / 2));
    final corner = Radius.circular(r);
    return Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + r), radius: corner)
      ..lineTo(rect.right, rect.bottom - r)
      ..arcToPoint(Offset(rect.right - r, rect.bottom), radius: corner)
      ..lineTo(rect.left, rect.bottom)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => _PanelOpenHandleBorder(radius: radius * t);

  @override
  bool operator ==(Object other) =>
      other is _PanelOpenHandleBorder && other.radius == radius;

  @override
  int get hashCode => radius.hashCode;
}

/// Header לפנלים הימניים — טאב בר וכפתור סגירה.
class PanelTabHeader extends StatelessWidget {
  final TabController controller;
  final List<Widget> tabs;
  final VoidCallback? onClose;
  final ValueChanged<int>? onTap;
  final List<Widget> extraActions;

  const PanelTabHeader({
    super.key,
    required this.controller,
    required this.tabs,
    this.onClose,
    this.onTap,
    this.extraActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTokens.panelTabHeight,
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: controller,
              tabs: tabs,
              splashBorderRadius: AppTokens.borderRadiusAll,
              onTap: onTap,
            ),
          ),
          ...extraActions,
          IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const Icon(FluentIcons.dismiss_24_regular),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
