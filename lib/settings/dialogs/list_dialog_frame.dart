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

/// קו מפריד בין שורות בכרטיס רשימה.
BorderSide listDialogRowDivider(BuildContext context) =>
    BorderSide(color: AppSurfaces.subtleDivider(Theme.of(context).colorScheme));
