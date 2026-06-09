import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

/// כתובת ה-bootstrapper הרשמי של Microsoft להתקנת WebView2 Runtime.
/// קובץ התקנה קטן שמוריד ומתקין את הגרסה העדכנית (Evergreen).
const String _webView2DownloadUrl =
    'https://go.microsoft.com/fwlink/p/?LinkId=2124703';

/// תצוגה שמופיעה במקום ה-WebView כאשר WebView2 Runtime אינו מותקן במחשב
/// (Windows בלבד). מסבירה למשתמש מהי הבעיה ומציעה כפתור להורדת ה-Runtime
/// הרשמי, וכפתור "בדוק שוב" שיריץ מחדש את בדיקת הזמינות לאחר ההתקנה.
class PluginWebView2MissingView extends StatelessWidget {
  /// נקרא כשהמשתמש לוחץ "בדוק שוב" — האחראי על בדיקה מחדש של זמינות
  /// ה-Runtime (בדרך כלל rebuild של הטאב).
  final VoidCallback onRetry;

  const PluginWebView2MissingView({super.key, required this.onRetry});

  Future<void> _download() async {
    final uri = Uri.parse(_webView2DownloadUrl);
    // קוראים ישירות ל-launchUrl (ללא canLaunchUrl) ובודקים את ערך ההחזרה:
    // canLaunchUrl עלול להחזיר false שקרי כשאין הצהרת <queries> מתאימה.
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) UiSnack.showError('לא ניתן לפתוח את קישור ההורדה');
    } catch (_) {
      UiSnack.showError('לא ניתן לפתוח את קישור ההורדה');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FluentIcons.globe_prohibited_24_regular,
                size: 56,
                color: cs.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'להפעלת התוסף נדרש רכיב WebView2',
                style: tt.titleLarge,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 12),
              Text(
                'התוספים בתוכנה מוצגים באמצעות רכיב WebView2 של Microsoft, '
                'שאינו מותקן במחשב זה. ברוב מחשבי Windows 10/11 הרכיב מותקן '
                'מראש עם מערכת ההפעלה, אך כאן הוא חסר.',
                style: tt.bodyMedium,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'מה אפשר לעשות:',
                      style: tt.titleSmall,
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. לחץ "הורד WebView2" כדי להוריד את קובץ ההתקנה הרשמי '
                      'של Microsoft, והרץ אותו.\n'
                      '2. בסיום ההתקנה לחץ "בדוק שוב" — אין צורך להפעיל את '
                      'התוכנה מחדש.\n'
                      '3. שאר התוספים והכלים שאינם דורשים WebView2 ממשיכים '
                      'לעבוד כרגיל.',
                      style: tt.bodySmall,
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  RecommendedActionButton(
                    text: 'הורד WebView2',
                    icon: FluentIcons.arrow_download_24_regular,
                    onPressed: _download,
                  ),
                  const SizedBox(width: 12),
                  NeutralActionButton(
                    text: 'בדוק שוב',
                    icon: FluentIcons.arrow_clockwise_24_regular,
                    onPressed: onRetry,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
