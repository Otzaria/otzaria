import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// אישור מעבר לכתובת חיצונית שנלחצה בתוך עמוד PDF (issue #1482).
///
/// מחזיר `true` רק כשהמשתמש אישר במפורש.
Future<bool> showOpenUrlConfirmation(BuildContext context, Uri url) async {
  final confirmed = await showTwoActionsDialog(
    context: context,
    title: 'מעבר לכתובת חיצונית',
    confirmText: 'עבור',
    barrierDismissible: false,
    customContent: AppSelectionArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('האם לעבור לכתובת הבאה?'),
          const SizedBox(height: AppTokens.spaceXS),
          Text(
            url.toString(),
            // בפסקה RTL ה-bidi מסדר מחדש את הסלאש והפרמטרים, והמשתמש היה
            // מאשר יעד שנראה אחרת ממה שייפתח בפועל.
            textDirection: TextDirection.ltr,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    ),
  );
  return confirmed ?? false;
}
