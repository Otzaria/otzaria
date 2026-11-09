import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';

/// תצוגה שמופיעה במקום WebView כשהתוסף הקריס את האפליקציה בהפעלה הקודמת
/// (נשאר ב-PluginCrashGuard). מספקת למשתמש כפתור "נסה שוב" שמסיר את
/// ה-quarantine ומבקש מהאפליקציה לטעון מחדש.
class PluginCrashedView extends StatefulWidget {
  final String pluginId;
  final String? pluginName;

  /// נקרא אחרי שהמשתמש לחץ "נסה שוב" — האחראי על rebuild של הטאב כך
  /// שניסיון טעינה חדש יתבצע.
  final VoidCallback onRetry;

  const PluginCrashedView({
    super.key,
    required this.pluginId,
    required this.onRetry,
    this.pluginName,
  });

  @override
  State<PluginCrashedView> createState() => _PluginCrashedViewState();
}

class _PluginCrashedViewState extends State<PluginCrashedView> {
  bool _retrying = false;

  Future<void> _handleRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await PluginCrashGuard.retry(widget.pluginId);
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
        widget.onRetry();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pluginLabel = widget.pluginName ?? widget.pluginId;

    return OtzariaErrorState(
      icon: FluentIcons.warning_24_regular,
      title: 'התוסף "$pluginLabel" גרם לקריסת התוכנה',
      details:
          'בהפעלה הקודמת התוסף הזה הקריס את התוכנה בעת טעינתו. כדי '
          'למנוע קריסות חוזרות, אנחנו לא טוענים אותו אוטומטית.',
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('מה אפשר לעשות:', style: tt.titleSmall),
              const SizedBox(height: AppTokens.spaceSM),
              Text(
                '1. אם עדכנת את התוכנה או את WebView2 — לחץ "נסה שוב" '
                'כדי לבדוק אם הבעיה נפתרה.\n'
                '2. אם הבעיה חוזרת — סביר שהתוסף לא תואם למכשיר שלך '
                'כרגע. אפשר להמשיך להשתמש בשאר התוספים והכלים.\n'
                '3. אם זה תוסף שעובד אצל אחרים — דווח לפיתוח עם מספר '
                'הגרסה שלך.',
                style: tt.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        ActionButton.recommended(
          text: 'נסה שוב',
          icon: FluentIcons.arrow_clockwise_24_regular,
          isLoading: _retrying,
          onPressed: _handleRetry,
        ),
      ],
    );
  }
}
