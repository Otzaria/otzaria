import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/app_card.dart';

/// כרטיס נפתח עצמאי — מרחיב [AppCard] עם תוכן נגלה ומונפש.
///
/// כאשר [isExpanded] הוא false (ברירת מחדל), הכרטיס מציג רק את [header].
/// כאשר [isExpanded] הוא true ו-[children] אינו ריק, הכרטיס פותח לעמודה
/// עם [header] ואחריו הילדים, מופרדים ע"י [AppCard.sectionDivider].
///
/// ההרחבה/כיווץ מונפשים ע"י [SizeTransition] עם [AnimationController] —
/// האנימציה מופעלת רק כשה-[isExpanded] עצמו משתנה, לא כשתוכן פנימי גדל.
/// זה מונע אנימציה כפולה בכרטיסים מקוננים.
///
/// כשה-[wrapInCard] הוא true (ברירת מחדל), הכרטיס עוטף ב-[Material] עם פינות מעוגלות.
/// כשהוא false, מוחזר [Column] חשוף — מתאים לשימוש בתוך כרטיס קיים (רמה 1+).
///
/// מיועד לשימוש עצמאי (לא בתוך [AppCard.section]).
/// לשימוש בתוך [AppCard.section], ראה [ExpandableSection].
class ExpandableCard extends StatefulWidget {
  const ExpandableCard({
    super.key,
    required this.header,
    required this.isExpanded,
    this.children = const [],
    this.margin,
    this.wrapInCard = true,
  });

  final Widget header;
  final bool isExpanded;
  final List<Widget> children;

  /// רווח חיצוני סביב הכרטיס. מוחל רק כש-[wrapInCard] הוא true.
  final EdgeInsetsGeometry? margin;

  /// כשהוא false, מוחזר Column חשוף ללא עטיפת Material — לשימוש בתוך כרטיס קיים.
  final bool wrapInCard;

  @override
  State<ExpandableCard> createState() => _ExpandableCardState();
}

class _ExpandableCardState extends State<ExpandableCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late CurvedAnimation _animation;

  // מטמון לתוכן — נשמר גם בזמן אנימציית סגירה
  List<Widget> _displayChildren = const [];

  @override
  void initState() {
    super.initState();
    _displayChildren = widget.children;
    _controller = AnimationController(
      duration: AppTokens.animNormal,
      vsync: this,
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    // מנקה את המטמון לאחר השלמת אנימציית הסגירה
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _displayChildren = const []);
      }
    });
  }

  @override
  void didUpdateWidget(ExpandableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.children.isNotEmpty) {
      _displayChildren = widget.children;
    }
    if (widget.isExpanded != oldWidget.isExpanded) {
      widget.isExpanded ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.duration(context, AppTokens.animNormal);
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = AppSurfaces.card(context);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.header,
        SizeTransition(
          sizeFactor: _animation,
          child: _displayChildren.isNotEmpty
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppCard.sectionDivider(context),
                    for (int i = 0; i < _displayChildren.length; i++) ...[
                      Material(
                        color: cardColor,
                        child: _displayChildren[i],
                      ),
                      if (i < _displayChildren.length - 1)
                        AppCard.sectionDivider(context),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );

    if (!widget.wrapInCard) return content;

    Widget card = Material(
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: AppCard.shape(Theme.of(context).colorScheme),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (widget.margin != null) {
      card = Padding(padding: widget.margin!, child: card);
    }

    return card;
  }
}
