import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/reports/view_scope.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/view/app_report_result_snack.dart';
import 'package:otzaria/app_report/view/widgets/app_report_images_section.dart';
import 'package:otzaria/app_report/view/widgets/app_report_preview_section.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// פותח את טופס הדיווח על התוכנה. מחזיר את תוצאת השליחה, או null בביטול.
Future<AppReportDeliveryResult?> showAppReportDialog(
  BuildContext context, {
  AppReportBloc Function()? createBloc,
  WidgetBuilder Function(BuildContext, WidgetBuilder)? dialogBuilder,
}) {
  WidgetBuilder builder = (_) => AppReportDialog(createBloc: createBloc);
  if (dialogBuilder != null) builder = dialogBuilder(context, builder);
  builder = reportDialogBuilder(context, builder);
  return showDialog<AppReportDeliveryResult>(
    context: context,
    barrierDismissible: false,
    builder: builder,
  );
}

/// תוויות סוגי הדיווח בטופס.
String appReportTypeLabel(AppReportType type) => switch (type) {
  AppReportType.bug => 'תקלה',
  AppReportType.crash => 'קריסה',
  AppReportType.performance => 'ביצועים',
  AppReportType.suggestion => 'הצעה',
};

/// האייקון של כל סוג דיווח בבורר. הבורר הוא הפקד הראשון בטופס, והאייקון
/// הוא מה שמבדיל בין ארבע התוויות הקצרות במבט.
IconData appReportTypeIcon(AppReportType type) => switch (type) {
  AppReportType.bug => FluentIcons.bug_24_regular,
  AppReportType.crash => FluentIcons.error_circle_24_regular,
  AppReportType.performance => FluentIcons.top_speed_24_regular,
  AppReportType.suggestion => FluentIcons.lightbulb_24_regular,
};

/// טופס דיווח ידני על התוכנה: סוג, כותרת, תיאור, שלבי שחזור, מייל (חובה)
/// ותצוגה מקדימה של הצרופות.
class AppReportDialog extends StatefulWidget {
  const AppReportDialog({super.key, this.createBloc});

  final AppReportBloc Function()? createBloc;

  @override
  State<AppReportDialog> createState() => _AppReportDialogState();
}

class _AppReportDialogState extends State<AppReportDialog> {
  late final AppReportBloc _bloc;
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _steps = TextEditingController();
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bloc =
        (widget.createBloc?.call() ??
              AppReportBloc(trigger: AppReportTrigger.manual))
          ..add(const AppReportAttachmentsRequested());
  }

  @override
  void dispose() {
    _bloc.close();
    _title.dispose();
    _description.dispose();
    _steps.dispose();
    _email.dispose();
    super.dispose();
  }

  void _syncControllers(AppReportEditing state) {
    if (_email.text != state.email) _email.text = state.email;
    if (_title.text != state.title) _title.text = state.title;
    if (_description.text != state.description) {
      _description.text = state.description;
    }
    if (_steps.text != state.steps) _steps.text = state.steps;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isNarrow = WindowClass.of(context).isCompact;
    final maxWidth = isNarrow ? size.width * 0.95 : 640.0;

    return BlocProvider.value(
      value: _bloc,
      child: BlocConsumer<AppReportBloc, AppReportState>(
        listenWhen: (previous, current) =>
            current is AppReportEditing &&
            (previous is! AppReportEditing ||
                previous.invalidField != current.invalidField ||
                previous.isFinished != current.isFinished ||
                previous.draftSaved != current.draftSaved ||
                previous.draftDiscarded != current.draftDiscarded),
        listener: (context, state) {
          if (state is! AppReportEditing) return;
          if (state.draftDiscarded) {
            UiSnack.show(
              context.settingsText(ReportMessages.appReportDraftDiscarded),
            );
            Navigator.of(context).pop();
            return;
          }
          if (state.draftSaved) {
            if (state.hasDraft) {
              UiSnack.showSuccess(
                context.settingsText(ReportMessages.appReportDraftSaved),
              );
            }
            Navigator.of(context).pop();
            return;
          }
          if (state.isFinished && state.result != null) {
            showAppReportResultSnack(state.result!, context: context);
            Navigator.of(context).pop(state.result);
            return;
          }
          final invalid = state.invalidField;
          if (invalid != null) {
            UiSnack.showError(
              appReportInvalidFieldMessage(
                invalid,
                emailEmpty: state.email.trim().isEmpty,
                context: context,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is AppReportEditing) _syncControllers(state);
          final dialog = Dialog(
            insetPadding: isNarrow ? AppDialogSize.compactInset : null,
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
                  _buildHeader(context, state),
                  Flexible(
                    child: switch (state) {
                      AppReportCollecting() => const Padding(
                        padding: EdgeInsets.all(AppTokens.spaceXL),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      // הפס גלוי מההתחלה: בחלון נמוך אין סימן אחר לכך שיש
                      // עוד שדות מתחת.
                      AppReportEditing() => PanelScrollableContent(
                        thumbVisibility: true,
                        padding: const EdgeInsets.fromLTRB(
                          AppTokens.spaceLG,
                          AppTokens.spaceMD,
                          AppTokens.spaceLG,
                          0,
                        ),
                        child: _buildForm(context, state),
                      ),
                    },
                  ),
                  const Divider(height: 1),
                  _buildActions(context, state),
                ],
              ),
            ),
          );
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) _leave();
            },
            child: dialog,
          );
        },
      ),
    );
  }

  /// כותרת הטופס: אייקון מסומל, שם הטופס ומשפט שמסביר מה עוזר בדיווח.
  /// הפס הצבוע מפריד אותה מהטופס עצמו, כמו בשאר הדיאלוגים המורכבים.
  Widget _buildHeader(BuildContext context, AppReportState state) {
    return AppDialogHeader(
      icon: FluentIcons.person_feedback_24_regular,
      title: context.settingsText('דיווח על תקלה בתוכנה'),
      onClose: _leave,
      subtitle: context.settingsText(
        'ככל שהתיאור מדויק יותר, כך קל יותר לאתר את התקלה ולתקן אותה',
      ),
      closeEnabled: !(state is AppReportEditing && state.isSending),
    );
  }

  /// תווית שדה: אייקון שמזהה את סוג המידע, ולצידו שם השדה. הצורה זהה
  /// לשורת ההגדרה שבמסך ההגדרות, ולכן הטופס נקרא כחלק מאותה מערכת.
  Widget _fieldLabel(
    BuildContext context,
    IconData icon,
    String label, {
    String? hint,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceXS),
      child: Row(
        children: [
          Icon(
            icon,
            size: AppTokens.iconSM,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppTokens.spaceSM),
          // בטלפון התווית וההערה יורדות שורה, ולא גולשות.
          Flexible(
            child: Text.rich(
              TextSpan(
                text: context.settingsText(label),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  if (hint != null)
                    TextSpan(
                      text: ' ${context.settingsText(hint)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context, AppReportEditing state) {
    final bloc = context.read<AppReportBloc>();
    final enabled =
        !state.isSending &&
        state.invalidField != 'draftFinalize' &&
        state.invalidField != 'draftLoad';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.hasDraft) ...[
          _buildDraftNotice(context, enabled: enabled),
          const SizedBox(height: AppTokens.spaceMD),
        ],
        _fieldLabel(context, FluentIcons.tag_24_regular, 'סוג הדיווח'),
        AppSegmentedControl<AppReportType>(
          options: [
            for (final type in AppReportType.values)
              SegmentOption(
                value: type,
                label: context.settingsText(appReportTypeLabel(type)),
                icon: appReportTypeIcon(type),
              ),
          ],
          currentValue: state.type,
          expandToFillWidth: true,
          onChanged: enabled
              ? (type) => bloc.add(AppReportTypeChanged(type))
              : (_) {},
        ),
        const SizedBox(height: AppTokens.spaceMD),
        _fieldLabel(context, FluentIcons.textbox_24_regular, 'כותרת'),
        RtlTextField(
          key: const ValueKey('app-report-title'),
          controller: _title,
          enabled: enabled,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.settingsText('משפט אחד שמתאר את הבעיה'),
            errorText: state.invalidField == 'title'
                ? context.settingsText('יש למלא כותרת')
                : null,
          ).filledOnDialog(context),
          onChanged: (value) => bloc.add(AppReportTitleChanged(value)),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        _fieldLabel(
          context,
          OtzariaIcons.alef_exclamation_24_filled,
          'מה קרה?',
        ),
        RtlTextField(
          key: const ValueKey('app-report-description'),
          controller: _description,
          enabled: enabled,
          // השדה גדל עם הטקסט, והטופס הוא אזור הגלילה היחיד: שדה שגולל בעצמו
          // לוכד את הגלגלת ואת הגרירה, ובחלון נמוך הוא כמעט כל הגובה.
          minLines: 3,
          maxLines: null,
          decoration: InputDecoration(
            hintText: context.settingsText('מה ציפית שיקרה, ומה קרה בפועל'),
            alignLabelWithHint: true,
            errorText: state.invalidField == 'description'
                ? context.settingsText('יש לתאר את התקלה')
                : null,
          ).filledOnDialog(context),
          onChanged: (value) => bloc.add(AppReportDescriptionChanged(value)),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        _fieldLabel(
          context,
          OtzariaIcons.text_number_list_24_regular,
          'שלבים לשחזור',
          hint: '(לא חובה)',
        ),
        RtlTextField(
          key: const ValueKey('app-report-steps'),
          controller: _steps,
          enabled: enabled,
          minLines: 2,
          maxLines: null,
          decoration: InputDecoration(
            hintText: context.settingsText('מה עשית לפני שהתקלה הופיעה'),
            alignLabelWithHint: true,
          ).filledOnDialog(context),
          onChanged: (value) => bloc.add(AppReportStepsChanged(value)),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        _fieldLabel(
          context,
          FluentIcons.mail_24_regular,
          'דואר אלקטרוני לחזרה אליך',
        ),
        RtlTextField(
          key: const ValueKey('app-report-email'),
          controller: _email,
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'name@example.com',
            errorText: state.invalidField == 'reporterEmail'
                ? context.settingsText('נדרשת כתובת תקינה')
                : null,
          ).filledOnDialog(context),
          onChanged: (value) => bloc.add(AppReportEmailChanged(value)),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        AppReportImagesSection(
          otherAttachmentBytes: bloc.otherAttachmentBytes(state),
          images: state.images,
          enabled: enabled,
          onChanged: (images) => bloc.add(AppReportImagesChanged(images)),
        ),
        const SizedBox(height: AppTokens.spaceLG),
        _fieldLabel(
          context,
          FluentIcons.attach_24_regular,
          'מה נשלח יחד עם הדיווח',
        ),
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
        const SizedBox(height: AppTokens.spaceMD),
      ],
    );
  }

  Widget _buildDraftNotice(BuildContext context, {required bool enabled}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          FluentIcons.drafts_24_regular,
          size: AppTokens.iconSM,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppTokens.spaceSM),
        Expanded(
          child: Text(
            context.settingsText('הטופס נטען מטיוטה שמורה'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ActionButton.ghost(
          key: const ValueKey('app-report-discard-draft'),
          text: context.settingsText('השלך טיוטה'),
          icon: FluentIcons.delete_24_regular,
          onPressed: enabled ? _discardDraft : null,
        ),
      ],
    );
  }

  bool get _offline =>
      Settings.isInitialized &&
      (Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false);

  Widget _buildActions(BuildContext context, AppReportState state) {
    final editing = state is AppReportEditing ? state : null;
    final busy = editing?.isSending ?? false;
    final finalizing = editing?.invalidField == 'draftFinalize';
    final loadFailed = editing?.invalidField == 'draftLoad';
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_offline && !finalizing)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
              child: Text(
                context.settingsText(
                  'מצב מנותק: הדיווח יישמר בתור לשליחה או להעברה, לאחר השלמת השדות הנדרשים.',
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              if (_bloc.supportsDraft && !finalizing && !loadFailed)
                ActionButton.ghost(
                  key: const ValueKey('app-report-discard'),
                  text: context.settingsText('השלך טיוטה'),
                  onPressed: editing == null || busy ? null : _discardDraft,
                ),
              ActionButton.neutral(
                key: const ValueKey('app-report-save-draft'),
                text: context.settingsText(
                  _bloc.supportsDraft && !loadFailed
                      ? 'שמור טיוטה וצא זמנית'
                      : 'סגור',
                ),
                onPressed: busy || finalizing ? null : _leave,
              ),
              if (!_offline && !finalizing && !loadFailed)
                ActionButton.neutral(
                  key: const ValueKey('app-report-queue'),
                  text: context.settingsText('שמור בתור'),
                  onPressed: editing == null || busy
                      ? null
                      : () => _bloc.add(
                          const AppReportSubmitted(queueOnly: true),
                        ),
                ),
              if (!loadFailed)
                ActionButton.recommended(
                  key: const ValueKey('app-report-send'),
                  text: context.settingsText(
                    finalizing
                        ? 'סיים שמירה מקומית'
                        : _offline
                        ? 'שמור בתור'
                        : 'שלח',
                  ),
                  icon: FluentIcons.send_24_regular,
                  isLoading: busy,
                  onPressed: editing == null || busy
                      ? null
                      : () =>
                            _bloc.add(AppReportSubmitted(queueOnly: _offline)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _leave() {
    final state = _bloc.state;
    if (state is AppReportEditing &&
        (state.isSending || state.invalidField == 'draftFinalize')) {
      return;
    }
    if (_bloc.supportsDraft &&
        state is AppReportEditing &&
        state.invalidField != 'draftLoad') {
      _bloc.add(const AppReportDraftSaved());
    } else {
      Navigator.of(context).pop();
    }
  }

  void _discardDraft() => _bloc.add(const AppReportDraftDiscarded());
}
