import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/app_report/view/app_report_result_snack.dart';
import 'package:otzaria/app_report/view/widgets/app_report_preview_section.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

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

bool _crashPromptOpen = false;

/// מציג את ההצעה מעל ה-Navigator הראשי; false כשאין בו context, או כשהצעה
/// אחרת כבר פתוחה — הצעות אינן נערמות זו על זו.
Future<bool> showCrashPromptOnNavigator(
  CrashCandidate candidate, {
  @visibleForTesting
  Future<void> Function(BuildContext context, CrashCandidate candidate)? show,
}) async {
  if (_crashPromptOpen) return false;
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) return false;
  _crashPromptOpen = true;
  try {
    await (show ?? _showDefault)(context, candidate);
  } finally {
    _crashPromptOpen = false;
  }
  return true;
}

Future<void> _showDefault(BuildContext context, CrashCandidate candidate) =>
    showCrashPromptDialog(context, candidate: candidate);

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

  /// בקריסה מהפעלה קודמת החלון הנוכחי אינו מה שהיה פתוח בה.
  @visibleForTesting
  static AppReportCollector collectorFor(CrashCandidate candidate) =>
      AppReportCollector(
        includeCurrentContext: !candidate.occurredInPreviousRun,
      );

  static const String title = 'אוצריא נסגרה באופן לא צפוי';
  static const String hangTitle = 'אוצריא נתקעה';

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
                collector: CrashPromptDialog.collectorFor(widget.candidate),
                initialType: CrashReportDecision.reportTypeFor(
                  widget.candidate,
                ),
                initialTitle: CrashReportDecision.titleFor(widget.candidate),
                signature: widget.candidate.signature,
                minidumpFile: widget.candidate.minidump,
                details: widget.candidate.details ?? '',
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
    UiSnack.show(
      widget.candidate.isHang
          ? ReportMessages.appReportHangDismissed
          : ReportMessages.appReportCrashDismissed,
    );
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
                  _buildHeader(context, editing),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppTokens.spaceLG,
                        AppTokens.spaceMD,
                        AppTokens.spaceLG,
                        0,
                      ),
                      child: _buildBody(context, editing),
                    ),
                  ),
                  const Divider(height: 1),
                  _buildActions(context, editing),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _incidentText() {
    final candidate = widget.candidate;
    if (!candidate.isHang) {
      return 'בהפעלה הקודמת התוכנה נסגרה בלי סגירה מסודרת.';
    }
    if (candidate.occurredInPreviousRun) {
      return 'בהפעלה הקודמת התוכנה הפסיקה להגיב.';
    }
    final seconds = candidate.hangDuration?.inSeconds ?? 0;
    return seconds > 0
        ? 'התוכנה הפסיקה להגיב למשך $seconds שניות.'
        : 'התוכנה הפסיקה להגיב.';
  }

  /// כותרת בצורת כותרת הטופס [AppReportDialog]: אייקון מסומל, שם ותיאור המקרה.
  Widget _buildHeader(BuildContext context, AppReportEditing? state) {
    return AppDialogHeader(
      icon: FluentIcons.warning_24_regular,
      tone: AppDialogHeaderTone.error,
      title: widget.candidate.isHang
          ? CrashPromptDialog.hangTitle
          : CrashPromptDialog.title,
      subtitle: _incidentText(),
      closeEnabled: !(state?.isSending ?? false),
      onClose: _dismiss,
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
          'שליחת דיווח תעזור לנו למצוא את הסיבה ולתקן אותה.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppTokens.spaceMD),
        RtlTextField(
          key: const ValueKey('crash-prompt-description'),
          controller: _description,
          enabled: enabled,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppSurfaces.card(context),
            labelText: widget.candidate.isHang
                ? 'מה עשית לפני שהתוכנה נתקעה? (לא חובה)'
                : 'מה עשית לפני הסגירה? (לא חובה)',
            alignLabelWithHint: true,
          ),
          onChanged: (value) => bloc.add(AppReportDescriptionChanged(value)),
        ),
        const SizedBox(height: 12),
        RtlTextField(
          key: const ValueKey('crash-prompt-email'),
          controller: _email,
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppSurfaces.card(context),
            labelText: 'דואר אלקטרוני (לא חובה)',
            errorText: state?.invalidField == 'reporterEmail'
                ? 'הכתובת אינה תקינה'
                : null,
          ),
          onChanged: (value) => bloc.add(AppReportEmailChanged(value)),
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
            minidump: state.minidump,
            includeMinidump: state.includeMinidump,
            onMinidumpChanged: (include) =>
                bloc.add(AppReportMinidumpToggled(include)),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceMD,
      ),
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
