import 'package:flutter/material.dart';
import 'package:otzaria/plugins/view/widgets/plugin_advice_box.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:otzaria/core/messages/plugin_messages.dart';
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
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        UiSnack.showError(PluginMessages.downloadLinkOpenFailed);
      }
    } catch (_) {
      UiSnack.showError(PluginMessages.downloadLinkOpenFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OtzariaErrorState(
      icon: FluentIcons.globe_prohibited_24_regular,
      title: 'להפעלת התוסף נדרש רכיב WebView2',
      details:
          'התוספים בתוכנה מוצגים באמצעות רכיב WebView2 של Microsoft, '
          'שאינו מותקן במחשב זה. ברוב מחשבי Windows 10/11 הרכיב מותקן '
          'מראש עם מערכת ההפעלה, אך כאן הוא חסר.',
      body: const PluginAdviceBox(
        text:
            '1. לחץ "הורד WebView2" כדי להוריד את קובץ ההתקנה הרשמי '
            'של Microsoft, והרץ אותו.\n'
            '2. בסיום ההתקנה לחץ "בדוק שוב" — אין צורך להפעיל את '
            'התוכנה מחדש.\n'
            '3. שאר התוספים והכלים שאינם דורשים WebView2 ממשיכים '
            'לעבוד כרגיל.',
      ),
      actions: [
        ActionButton.recommended(
          text: 'הורד WebView2',
          icon: FluentIcons.arrow_download_24_regular,
          onPressed: _download,
        ),
        ActionButton.neutral(
          text: 'בדוק שוב',
          icon: FluentIcons.arrow_clockwise_24_regular,
          onPressed: onRetry,
        ),
      ],
    );
  }
}
