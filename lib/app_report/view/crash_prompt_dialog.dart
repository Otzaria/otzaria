import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/app_report/view/app_report_result_snack.dart';
import 'package:otzaria/app_report/view/widgets/app_report_preview_section.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// מציג את ההצעה לדווח על קריסה של ההפעלה הקודמת.
Future<AppReportDeliveryResult?> showCrashPromptDialog(
  BuildContext context, {
  required CrashCandidate candidate,
  AppReportBloc Function()? createBloc,
  Future<void> Function(AppCrashReportMode mode)? saveMode,
}) {
  return showDialog<AppReportDeliveryResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CrashPromptDialog(
      candidate: candidate,
      createBloc: createBloc,
      saveMode: saveMode,
    ),
  );
}

/// "אוצריא נסגרה באופן לא צפוי": תיאור ומייל רשות, תצוגה מקדימה, ובחירה
/// מה לעשות בקריסות הבאות.
class CrashPromptDialog extends StatefulWidget {
  const CrashPromptDialog({
    super.key,
    required this.candidate,
    this.createBloc,
    this.saveMode,
  });

  final CrashCandidate candidate;
  final AppReportBloc Function()? createBloc;
  final Future<void> Function(AppCrashReportMode mode)? saveMode;

  static const String title = 'אוצריא נסגרה באופן לא צפוי';

  @override
  State<CrashPromptDialog> createState() => _CrashPromptDialogState();
}

class _CrashPromptDialogState extends State<CrashPromptDialog> {
  late final AppReportBloc _bloc;
  final _description = TextEditingController();
  final _email = TextEditingController();
  AppCrashReportMode _nextTime = AppCrashReportMode.ask;

  @override
  void initState() {
    super.initState();
    _bloc =
        (widget.createBloc?.call() ??
              AppReportBloc(
                trigger: AppReportTrigger.crashPrompt,
                initialType: AppReportType.crash,
                initialTitle: CrashReportDecision.titleFor(widget.candidate),
                signature: widget.candidate.signature,
              ))
          ..add(const AppReportAttachmentsRequested());
  }

  @override
  void dispose() {
    _bloc.close();
    _description.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _saveMode() async {
    if (_nextTime == AppCrashReportMode.ask) return;
    final save = widget.saveMode;
    if (save != null) return save(_nextTime);
    if (!Settings.isInitialized) return;
    await Settings.setValue(
      SettingsRepository.keyAppCrashReportMode,
      _nextTime.wireName,
    );
  }

  Future<void> _dismiss() async {
    await _saveMode();
    if (!mounted) return;
    UiSnack.show(ReportMessages.appReportCrashDismissed);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width < 600 ? size.width * 0.95 : 560.0;

    return BlocProvider.value(
      value: _bloc,
      child: BlocConsumer<AppReportBloc, AppReportState>(
        listenWhen: (previous, current) =>
            current is AppReportEditing &&
            current.isFinished &&
            !(previous is AppReportEditing && previous.isFinished),
        listener: (context, state) async {
          final result = (state as AppReportEditing).result;
          if (result == null) return;
          await _saveMode();
          if (!context.mounted) return;
          showAppReportResultSnack(result);
          Navigator.of(context).pop(result);
        },
        builder: (context, state) {
          final editing = state is AppReportEditing ? state : null;
          if (editing != null && _email.text != editing.email) {
            _email.text = editing.email;
          }
          return Dialog(
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: size.height * 0.9,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                    child: Text(
                      CrashPromptDialog.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildBody(context, editing),
                    ),
                  ),
                  _buildActions(context, editing),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppReportEditing? state) {
    final theme = Theme.of(context);
    final bloc = context.read<AppReportBloc>();
    final enabled = state != null && !state.isSending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'בהפעלה הקודמת התוכנה נסגרה בלי סגירה מסודרת. שליחת דיווח '
          'תעזור לנו למצוא את הסיבה ולתקן אותה.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        RtlTextField(
          key: const ValueKey('crash-prompt-description'),
          controller: _description,
          enabled: enabled,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'מה עשית לפני הסגירה? (לא חובה)',
            alignLabelWithHint: true,
          ),
          onChanged: (value) => bloc.add(AppReportDescriptionChanged(value)),
        ),
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.ltr,
          child: RtlTextField(
            key: const ValueKey('crash-prompt-email'),
            controller: _email,
            enabled: enabled,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'דואר אלקטרוני (לא חובה)',
              errorText: state?.invalidField == 'reporterEmail'
                  ? 'הכתובת אינה תקינה'
                  : null,
            ),
            onChanged: (value) => bloc.add(AppReportEmailChanged(value)),
          ),
        ),
        const SizedBox(height: 16),
        if (state == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          AppReportPreviewSection(
            diagnostics: state.diagnostics,
            errorLog: state.errorLog,
            includeDiagnostics: state.includeDiagnostics,
            includeErrorLog: state.includeErrorLog,
            enabled: enabled,
            onDiagnosticsChanged: (include) =>
                bloc.add(AppReportDiagnosticsToggled(include)),
            onErrorLogChanged: (include) =>
                bloc.add(AppReportErrorLogToggled(include)),
          ),
        const SizedBox(height: 16),
        Text('בפעם הבאה שזה יקרה:', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        AppSegmentedControl<AppCrashReportMode>(
          options: const [
            SegmentOption(value: AppCrashReportMode.ask, label: 'שאל אותי'),
            SegmentOption(
              value: AppCrashReportMode.always,
              label: 'תמיד לשלוח אוטומטית',
            ),
            SegmentOption(
              value: AppCrashReportMode.never,
              label: 'אל תשאל שוב',
            ),
          ],
          currentValue: _nextTime,
          expandToFillWidth: true,
          onChanged: (mode) => setState(() => _nextTime = mode),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildActions(BuildContext context, AppReportEditing? state) {
    final isSending = state?.isSending ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ActionButton.ghost(
            key: const ValueKey('crash-prompt-dismiss'),
            text: 'אל תשלח',
            onPressed: isSending ? null : _dismiss,
          ),
          const SizedBox(width: 8),
          ActionButton.recommended(
            key: const ValueKey('crash-prompt-send'),
            text: 'שלח דיווח',
            icon: FluentIcons.send_24_regular,
            isLoading: isSending,
            onPressed: state == null || isSending
                ? null
                : () => _bloc.add(const AppReportSubmitted()),
          ),
        ],
      ),
    );
  }
}
