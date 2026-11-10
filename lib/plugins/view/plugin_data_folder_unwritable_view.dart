import 'package:flutter/material.dart';
import 'package:otzaria/plugins/view/widgets/plugin_advice_box.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

/// תצוגה שמופיעה במקום ה-WebView כשתיקיית הנתונים של WebView2 אינה ניתנת
/// לכתיבה — בדרך כלל תוכנה ניידת שיושבת תחת Program Files (issue #1031).
class PluginDataFolderUnwritableView extends StatelessWidget {
  /// התיקייה החסומה, כפי שהוחזרה מ-`checkDataFolderWritable`.
  final String folderPath;

  /// נקרא כשהמשתמש לוחץ "בדוק שוב" — מריץ מחדש את בדיקת ההרשאות.
  final VoidCallback onRetry;

  const PluginDataFolderUnwritableView({
    super.key,
    required this.folderPath,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return OtzariaErrorState(
      icon: FluentIcons.folder_prohibited_20_regular,
      title: 'לתוכנה אין הרשאת כתיבה לתיקיית הנתונים',
      details:
          'התוספים מוצגים באמצעות רכיב WebView2, שזקוק לתיקיית עבודה '
          'הניתנת לכתיבה. התיקייה שנבחרה חסומה להרשאות המשתמש הנוכחי, '
          'ולכן התוספים אינם נפתחים.',
      body: PluginAdviceBox(
        header: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMD),
            child: Text(
              folderPath,
              style: tt.bodySmall,
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
        text: _advice,
      ),
      actions: [
        ActionButton.neutral(
          text: 'בדוק שוב',
          icon: FluentIcons.arrow_clockwise_24_regular,
          onPressed: onRetry,
        ),
      ],
    );
  }

  String get _advice => AppPaths.isPortable
      ? '1. התוכנה רצה במצב נייד — כל נתוניה נשמרים לצידה, ולכן היא חייבת '
            'לשבת בתיקייה שניתן לכתוב אליה (לא Program Files).\n'
            '2. העבר את תיקיית התוכנה למיקום כזה — למשל לתיקיית המסמכים או '
            'לכונן נייד — והפעל מחדש.\n'
            '3. לחלופין, התקן את אוצריא עם קובץ ההתקנה הרגיל; הוא מפנה את '
            'הנתונים לתיקיית המשתמש.'
      : '1. ייתכן שהתיקייה נוצרה בהרשאות מנהל. התקנה מחדש עם קובץ ההתקנה '
            'הרגיל תיצור אותה מחדש בהרשאות תקינות.\n'
            '2. לחלופין, מחק את התיקייה המוצגת למעלה והפעל את התוכנה מחדש — '
            'היא תיווצר שוב באופן אוטומטי.';
}
