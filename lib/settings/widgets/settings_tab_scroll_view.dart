import 'package:flutter/material.dart';

/// אזור הגלילה של לשונית הגדרות.
///
/// ויופורט של slivers ולא `SingleChildScrollView`: שם כל פריסה מחדש בזמן
/// מתיחה אלסטית מוחקת את המתיחה, והמסך רועד (issue #1386, flutter#145078).
class SettingsTabScrollView extends StatelessWidget {
  const SettingsTabScrollView({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      primary: true,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
  }
}
