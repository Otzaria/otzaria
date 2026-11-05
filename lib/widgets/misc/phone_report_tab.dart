import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/models/phone_report_data.dart';
import 'package:otzaria/widgets/misc/reporting_numbers_widget.dart';

/// Tab widget for phone-based error reporting
class PhoneReportTab extends StatefulWidget {
  final String selectedText;
  final double fontSize;
  final String libraryVersion;
  final int? bookId;
  final int lineNumber;
  final VoidCallback? onCancel;

  const PhoneReportTab({
    super.key,
    required this.selectedText,
    required this.fontSize,
    required this.libraryVersion,
    required this.bookId,
    required this.lineNumber,
    this.onCancel,
  });

  @override
  State<PhoneReportTab> createState() => _PhoneReportTabState();
}

class _PhoneReportTabState extends State<PhoneReportTab> {
  ErrorType? _selectedErrorType;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<String> get _validationErrors {
    final errors = <String>[];

    if (widget.selectedText.isEmpty) {
      errors.add('בחירת הטקסט שבו נמצאת השגיאה');
    }

    if (_selectedErrorType == null) {
      errors.add('סוג השגיאה');
    }

    if (widget.bookId == null) {
      errors.add('לא ניתן למצוא את הספר במאגר הנתונים');
    }

    if (widget.libraryVersion == 'unknown') {
      errors.add('לא ניתן לקרוא את גירסת הספרייה');
    }

    return errors;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInstructions(context),
          const SizedBox(height: 12),
          _buildTextSelection(context),
          const SizedBox(height: 12),
          _buildErrorTypeSelection(context),
          const SizedBox(height: 12),
          _buildReportingNumbers(context),
          const SizedBox(height: 12),
          _buildValidationErrors(context),
          const SizedBox(height: 12),
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildInstructions(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.settingsText('הוראות לדיווח טלפוני:'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.settingsText(
                '1. בחר את סוג השגיאה   •  2. השתמש במספרים המוצגים למטה כשתתקשר',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextSelection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.settingsText('הטקסט שנבחר:'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(
            maxHeight: 150,
          ),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: SingleChildScrollView(
            child: Text(
              widget.selectedText,
              style: TextStyle(
                fontSize: widget.fontSize,
                fontFamily: AppFonts.renderFontFamily(
                  Settings.getValue('key-font-family') ?? AppFonts.defaultFont,
                ),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorTypeSelection(BuildContext context) {
    final isEnabled = widget.selectedText.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.settingsText('בחר סוג שגיאה:'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, // מרווח אופקי בין הכפתורים
          runSpacing: 8, // מרווח אנכי בין השורות
          children: ErrorType.errorTypes.map((errorType) {
            final isSelected = _selectedErrorType?.id == errorType.id;

            return FilterChip(
              label: Text(
                context.settingsText(errorType.hebrewLabel),
                style: TextStyle(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : isEnabled
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).disabledColor,
                ),
              ),
              selected: isSelected,
              onSelected: isEnabled
                  ? (bool selected) {
                      setState(() {
                        _selectedErrorType = selected ? errorType : null;
                      });
                    }
                  : null,
              backgroundColor: isEnabled
                  ? null
                  : Theme.of(context).disabledColor.withValues(alpha: 0.1),
              selectedColor: Theme.of(context).colorScheme.primary,
              checkmarkColor: Theme.of(context).colorScheme.onPrimary,
              side: BorderSide(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : isEnabled
                    ? Theme.of(context).colorScheme.outline
                    : Theme.of(context).disabledColor,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildReportingNumbers(BuildContext context) {
    return ReportingNumbersWidget(
      libraryVersion: widget.libraryVersion,
      bookId: widget.bookId,
      lineNumber: widget.lineNumber,
      errorId: _selectedErrorType?.id,
    );
  }

  Widget _buildValidationErrors(BuildContext context) {
    final errors = _validationErrors;
    if (errors.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  FluentIcons.error_circle_24_regular,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.settingsText(
                      'אי אפשר להתקדם... עדיין לא מילאתם בטופס...',
                    ),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...errors
                .take(errors.length - 1)
                .map(
                  (error) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            context.settingsText(error),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            // השורה האחרונה עם כפתור ביטול בצד שמאל
            if (errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        context.settingsText(errors.last),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // כפתור ביטול בצד שמאל של השורה האחרונה
                    Container(
                      padding: const EdgeInsets.all(
                        3,
                      ), // מרווח לבן מסביב הכפתור
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius:
                            AppTokens.borderRadiusAll, // עיגול כמו כפתור רגיל
                      ),
                      child: ActionButton.ghost(
                        onPressed: widget.onCancel,
                        text: context.settingsText('ביטול הדיווח'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    // אם יש שגיאות ולידציה, הכפתור ביטול מוצג במלבן השגיאות
    // אחרת, מציגים כפתור ביטול רגיל
    final errors = _validationErrors;
    if (errors.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ActionButton.ghost(
          onPressed: widget.onCancel,
          text: context.settingsText('ביטול הדיווח'),
        ),
      ],
    );
  }
}
