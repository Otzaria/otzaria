import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_tokens.dart';

import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/layout/centered_scrollable_state.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// למה ה-WebView של התוסף אינו מוצג.
enum PluginWebViewFailureKind {
  /// יצירת רכיב הדפדפן נכשלה.
  creation,

  /// התהליך שמריץ את התוסף נפל שוב ושוב.
  crashed,
}

/// תצוגה שמופיעה במקום ה-WebView כשרכיב הדפדפן לא נוצר או נפל שוב ושוב —
/// מצבים שהסתיימו במסך ריק בלי שום הסבר. [isEmulatedOnArm] מחליף את ההסבר
/// הכללי בהסבר הספציפי למחשבי ARM, שם התקלה ידועה ואין למשתמש מה לתקן.
class PluginWebViewFailedView extends StatelessWidget {
  final String? pluginName;

  /// פרטי השגיאה מהשכבה הנייטיבית (כולל HRESULT) — להצגה מכווצת לדיווח.
  final String? errorDetails;

  final bool isEmulatedOnArm;

  final PluginWebViewFailureKind kind;

  final VoidCallback onRetry;

  const PluginWebViewFailedView({
    super.key,
    required this.onRetry,
    this.pluginName,
    this.errorDetails,
    this.isEmulatedOnArm = false,
    this.kind = PluginWebViewFailureKind.creation,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final label = pluginName == null ? 'התוסף' : 'התוסף "$pluginName"';
    final crashed = kind == PluginWebViewFailureKind.crashed;
    final arm = isEmulatedOnArm && !crashed;

    return CenteredScrollableState(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              FluentIcons.globe_prohibited_24_regular,
              size: AppTokens.iconXL,
              color: cs.error,
            ),
            const SizedBox(height: 16),
            Text(
              crashed
                  ? '$label הפסיק לפעול'
                  : arm
                  ? 'התוספים אינם נתמכים עדיין במחשב זה'
                  : 'לא ניתן להפעיל את $label',
              style: tt.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              crashed
                  ? 'רכיב הדפדפן שמריץ את $label נסגר שוב ושוב, ולכן הוא לא '
                        'נטען מחדש אוטומטית. שאר חלקי התוכנה ממשיכים לעבוד כרגיל.'
                  : arm
                  ? 'המחשב שלך מבוסס מעבד ARM, ואוצריא עדיין רצה עליו במצב '
                        'תאימות. במצב זה רכיב הדפדפן שמציג את התוספים אינו '
                        'נוצר, ולכן התוספים וחנות התוספים אינם זמינים. '
                        'התמיכה בגרסה ייעודית למחשבי ARM נמצאת בעבודה.'
                  : 'יצירת רכיב הדפדפן שמציג את התוספים נכשלה במחשב זה, ולכן '
                        '$label לא נטען. שאר חלקי התוכנה — ספרים, חיפוש וכלים '
                        'שאינם תוספים — ממשיכים לעבוד כרגיל.',
              style: tt.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('מה אפשר לעשות:', style: tt.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    crashed
                        ? '1. לחץ "נסה שוב" כדי לטעון את התוסף מחדש.\n'
                              '2. אם הבעיה חוזרת, ייתכן שהתוסף צורך יותר מדי זיכרון '
                              'או שיש בו תקלה — דווח למפתח התוסף.'
                        : arm
                        ? '1. אפשר להמשיך להשתמש בכל שאר חלקי התוכנה כרגיל.\n'
                              '2. כדאי לעקוב אחר עדכוני הגרסה — כשתצא גרסה '
                              'למחשבי ARM התוספים יעבדו.\n'
                              '3. אם ברצונך לסייע בבדיקת גרסה כזו — דווח לצוות '
                              'הפיתוח שברשותך מחשב ARM.'
                        : '1. לחץ "נסה שוב" — לעיתים מדובר בכשל חולף.\n'
                              '2. אם הבעיה חוזרת, הפעל מחדש את התוכנה, ואם גם '
                              'זה לא עזר — את המחשב.\n'
                              '3. אם הבעיה נמשכת, דווח לצוות הפיתוח וצרף את '
                              'פרטי השגיאה שלהלן.',
                    style: tt.bodySmall,
                  ),
                ],
              ),
            ),
            if (errorDetails != null) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('פרטי השגיאה', style: tt.titleSmall),
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppSelectionArea(
                      child: Text(
                        errorDetails!,
                        style: tt.bodySmall,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                ActionButton.recommended(
                  text: 'נסה שוב',
                  icon: FluentIcons.arrow_clockwise_24_regular,
                  onPressed: onRetry,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
