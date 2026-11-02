import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';

/// המונה בכותרת של דיאלוג רשימה ([AppDialogFrame.trailing]).
class ListDialogCounter extends StatelessWidget {
  final String text;

  const ListDialogCounter(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// כרטיס שמחזיק את הרשימה בדיאלוגי הרשימות: צבע כרטיס מובחן מרקע הדיאלוג
/// ומסגרת עדינה, כדי שהשורות לא יישפכו על הרקע. [Material] ולא תיבה
/// מעוטרת, כדי שאפקט הלחיצה של השורות יצויר מעל צבע הכרטיס.
class ListDialogCard extends StatelessWidget {
  final Widget child;

  const ListDialogCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppSurfaces.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.borderRadiusAll,
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// קו מפריד בין שורות בכרטיס רשימה.
BorderSide listDialogRowDivider(BuildContext context) =>
    BorderSide(color: AppSurfaces.subtleDivider(Theme.of(context).colorScheme));
