import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_input_tokens.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// שדה "דואר אלקטרוני לחזרה אליך" בטופסי הדיווח, באותו מראה כמו בדיווח על
/// תקלה בתוכנה: תווית עם אייקון מעל שדה שאפשר להקליד בו ישירות.
///
/// [validate] (דרך `GlobalKey<ReportSenderEmailFieldState>`) מציג שגיאה בשדה
/// ומחזיר false כשהכתובת לא תקינה, או ריקה כשהיא [isRequired].
class ReportSenderEmailField extends StatefulWidget {
  const ReportSenderEmailField({
    super.key,
    this.controller,
    this.initialValue = '',
    this.isRequired = false,
    this.enabled = true,
    this.onChanged,
  });

  /// null: השדה מחזיק controller משלו, שמתחיל ב-[initialValue].
  final TextEditingController? controller;
  final String initialValue;
  final bool isRequired;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  State<ReportSenderEmailField> createState() => ReportSenderEmailFieldState();
}

class ReportSenderEmailFieldState extends State<ReportSenderEmailField> {
  TextEditingController? _ownController;
  final _focusNode = FocusNode();
  String? _error;

  TextEditingController get _controller =>
      widget.controller ??
      (_ownController ??= TextEditingController(text: widget.initialValue));

  String get text => _controller.text.trim();

  bool validate() {
    final value = text;
    final String? error;
    if (value.isEmpty) {
      error = widget.isRequired ? 'נדרשת כתובת תקינה' : null;
    } else {
      error = DirectErrorReportService.isValidSenderEmail(value)
          ? null
          : 'נדרשת כתובת תקינה';
    }
    if (_error != error) setState(() => _error = error);
    if (error != null) _focusNode.requestFocus();
    return error == null;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('report-sender-email'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceXS),
          child: Row(
            children: [
              Icon(
                FluentIcons.mail_24_regular,
                size: AppTokens.iconSM,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Flexible(
                child: Text(
                  context.settingsText('דואר אלקטרוני לחזרה אליך'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        RtlTextField(
          key: const ValueKey('report-sender-email-field'),
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'name@example.com',
            errorText: _error == null ? null : context.settingsText(_error!),
          ).filledOnDialog(context),
          onChanged: (value) {
            if (_error != null) setState(() => _error = null);
            widget.onChanged?.call(value);
          },
        ),
      ],
    );
  }
}
