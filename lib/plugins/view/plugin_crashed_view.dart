import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

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
                FluentIcons.warning_24_regular,
                size: 56,
                color: cs.error,
              ),
              const SizedBox(height: 16),
              Text(
                'התוסף "$pluginLabel" גרם לקריסת התוכנה',
                style: tt.titleLarge,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 12),
              Text(
                'בהפעלה הקודמת התוסף הזה הקריס את התוכנה בעת טעינתו. כדי '
                'למנוע קריסות חוזרות, אנחנו לא טוענים אותו אוטומטית.',
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
                      '1. אם עדכנת את התוכנה או את WebView2 — לחץ "נסה שוב" '
                      'כדי לבדוק אם הבעיה נפתרה.\n'
                      '2. אם הבעיה חוזרת — סביר שהתוסף לא תואם למכשיר שלך '
                      'כרגע. אפשר להמשיך להשתמש בשאר התוספים והכלים.\n'
                      '3. אם זה תוסף שעובד אצל אחרים — דווח לפיתוח עם מספר '
                      'הגרסה שלך.',
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
                    text: 'נסה שוב',
                    icon: FluentIcons.arrow_clockwise_24_regular,
                    isLoading: _retrying,
                    onPressed: _handleRetry,
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
