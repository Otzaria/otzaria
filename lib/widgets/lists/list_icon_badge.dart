import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// תיבת האייקון של שורה ברשימה (היסטוריה, סימניות): אייקון על רקע בצבע ערכת
/// הנושא. האייקון עצמו יורש גודל וצבע מהתיבה.
class ListIconBadge extends StatelessWidget {
  final Widget icon;

  const ListIconBadge({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconTheme.merge(
          data: IconThemeData(size: 20, color: cs.onPrimaryContainer),
          child: Center(child: icon),
        ),
      ),
    );
  }
}
