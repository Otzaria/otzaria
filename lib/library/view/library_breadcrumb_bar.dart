import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

/// שורת פירורי-לחם המציגה את הנתיב המלא של המיקום הנוכחי בקטלוג.
///
/// [chain] — שרשרת הקטגוריות מהעליונה ועד הנוכחית, ללא קטגוריית השורש.
/// לחיצה על קטע מנווטת אליו; הקטע האחרון (המיקום הנוכחי) אינו לחיץ.
class LibraryBreadcrumbBar extends StatelessWidget {
  final List<Category> chain;
  final void Function(Category category) onNavigate;
  final VoidCallback onNavigateHome;

  const LibraryBreadcrumbBar({
    super.key,
    required this.chain,
    required this.onNavigate,
    required this.onNavigateHome,
  });

  /// מעבר לכמות זו — הקטעים האמצעיים מוחלפים ב"…" כדי שהשורה תישאר קצרה.
  static const int maxVisibleSegments = 4;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final linkStyle = textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final currentStyle = textTheme.bodySmall?.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w600,
    );

    final children = <Widget>[
      _segment(
        tooltip: 'חזרה לתיקיה הראשית',
        onTap: onNavigateHome,
        child: Icon(
          FluentIcons.home_16_regular,
          size: 16,
          color: cs.onSurfaceVariant,
        ),
      ),
    ];

    final visible = chain.length <= maxVisibleSegments
        ? chain
        : [
            chain.first,
            null,
            chain[chain.length - 2],
            chain.last,
          ];

    for (final category in visible) {
      children.add(
        RtlIcon(
          FluentIcons.chevron_left_16_regular,
          size: 13,
          color: cs.outline,
        ),
      );
      if (category == null) {
        children.add(_segment(child: Text('…', style: linkStyle)));
      } else if (identical(category, chain.last)) {
        children.add(
          _segment(child: Text(category.title, style: currentStyle)),
        );
      } else {
        children.add(
          _segment(
            onTap: () => onNavigate(category),
            child: Text(category.title, style: linkStyle),
          ),
        );
      }
    }

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 0),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }

  Widget _segment({
    required Widget child,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: child,
    );
    if (onTap == null) return content;
    final button = InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: content,
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }
}
