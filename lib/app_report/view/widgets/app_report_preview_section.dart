import 'dart:convert';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

/// תצוגה מקדימה של מה שיישלח: מפת האבחון וקטע יומן השגיאות, כל אחד עם
/// תיבת סימון להחרגה. הטקסטים טכניים ולכן מוצגים LTR.
class AppReportPreviewSection extends StatefulWidget {
  const AppReportPreviewSection({
    super.key,
    required this.diagnostics,
    required this.errorLog,
    required this.includeDiagnostics,
    required this.includeErrorLog,
    required this.onDiagnosticsChanged,
    required this.onErrorLogChanged,
    this.enabled = true,
  });

  final Map<String, dynamic>? diagnostics;
  final String? errorLog;
  final bool includeDiagnostics;
  final bool includeErrorLog;
  final ValueChanged<bool> onDiagnosticsChanged;
  final ValueChanged<bool> onErrorLogChanged;
  final bool enabled;

  static const String privacyNote =
      'הכותרת, התיאור, פרטי הגרסה וצילומי המסך נכנסים למעקב התקלות של '
      'מפתחי אוצריא ב-GitHub. מידע האבחון, יומן השגיאות וכתובת הדואר '
      'נשארים אצל צוות אוצריא בלבד.';

  /// מפת האבחון כטקסט מסודר לתצוגה.
  static String prettyJson(Map<String, dynamic> diagnostics) {
    try {
      return const JsonEncoder.withIndent('  ').convert(diagnostics);
    } catch (error) {
      return '$error';
    }
  }

  @override
  State<AppReportPreviewSection> createState() =>
      _AppReportPreviewSectionState();
}

class _AppReportPreviewSectionState extends State<AppReportPreviewSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diagnostics = widget.diagnostics;
    final errorLog = widget.errorLog;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          key: const ValueKey('app-report-include-diagnostics'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          value: widget.includeDiagnostics && diagnostics != null,
          onChanged: widget.enabled && diagnostics != null
              ? (value) => widget.onDiagnosticsChanged(value ?? false)
              : null,
          title: const Text('לצרף מידע אבחון על התוכנה והמערכת'),
          subtitle: diagnostics == null
              ? const Text('לא ניתן היה לאסוף מידע אבחון')
              : null,
        ),
        CheckboxListTile(
          key: const ValueKey('app-report-include-error-log'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          value: widget.includeErrorLog && (errorLog?.isNotEmpty ?? false),
          onChanged: widget.enabled && (errorLog?.isNotEmpty ?? false)
              ? (value) => widget.onErrorLogChanged(value ?? false)
              : null,
          title: const Text('לצרף קטע מיומן השגיאות'),
          subtitle: (errorLog?.isEmpty ?? true)
              ? const Text('אין רשומות ביומן השגיאות')
              : null,
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionButton.ghost(
            key: const ValueKey('app-report-toggle-preview'),
            onPressed: () => setState(() => _isExpanded = !_isExpanded),
            icon: _isExpanded
                ? FluentIcons.chevron_up_24_regular
                : FluentIcons.chevron_down_24_regular,
            text: _isExpanded ? 'הסתר את מה שיישלח' : 'הצג את מה שיישלח',
          ),
        ),
        if (_isExpanded) ...[
          if (diagnostics != null)
            _PreviewBox(
              title: 'diagnostics.json',
              content: AppReportPreviewSection.prettyJson(diagnostics),
            ),
          if (errorLog != null && errorLog.isNotEmpty)
            _PreviewBox(title: 'errors.txt', content: errorLog),
        ],
        const SizedBox(height: 8),
        Text(
          AppReportPreviewSection.privacyNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: AppTokens.borderRadiusAll,
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
