import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/view/app_report_result_snack.dart';
import 'package:otzaria/app_report/view/widgets/app_report_images_section.dart';
import 'package:otzaria/app_report/view/widgets/app_report_preview_section.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
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
    final isNarrow = size.width < 600;
    final maxWidth = isNarrow ? size.width * 0.95 : 640.0;

    return BlocProvider.value(
      value: _bloc,
      child: BlocConsumer<AppReportBloc, AppReportState>(
        listenWhen: (previous, current) =>
            current is AppReportEditing &&
            (previous is! AppReportEditing ||
                previous.invalidField != current.invalidField ||
                previous.isFinished != current.isFinished ||
                previous.draftSaved != current.draftSaved),
        listener: (context, state) {
          if (state is! AppReportEditing) return;
          if (state.draftSaved) {
            UiSnack.showSuccess(ReportMessages.appReportDraftSaved);
            Navigator.of(context).pop();
            return;
          }
          if (state.isFinished && state.result != null) {
            showAppReportResultSnack(state.result!);
            Navigator.of(context).pop(state.result);
            return;
          }
          final invalid = state.invalidField;
          if (invalid != null) {
            UiSnack.showError(
              appReportInvalidFieldMessage(
                invalid,
                emailEmpty: state.email.trim().isEmpty,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is AppReportEditing) _syncControllers(state);
          final dialog = Dialog(
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
                      AppReportEditing() => SingleChildScrollView(
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
          // טקסט או צילום שצורף חוסמים סגירה עקיפה (קיצור ניווט, חזרה); הכפתורים סוגרים ב-pop.
          return PopScope(
            canPop:
                state is! AppReportEditing ||
                (state.title + state.description + state.steps)
                        .trim()
                        .isEmpty &&
                    state.images.isEmpty,
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
      title: 'דיווח על תקלה בתוכנה',
      subtitle: 'ככל שהתיאור מדויק יותר, כך קל יותר לאתר את התקלה ולתקן אותה',
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
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppTokens.spaceSM),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: AppTokens.spaceXS),
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context, AppReportEditing state) {
    final bloc = context.read<AppReportBloc>();
    final enabled = !state.isSending;
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
                label: appReportTypeLabel(type),
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
            filled: true,
            fillColor: AppSurfaces.card(context),
            hintText: 'משפט אחד שמתאר את הבעיה',
            errorText: state.invalidField == 'title' ? 'יש למלא כותרת' : null,
          ),
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
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppSurfaces.card(context),
            hintText: 'מה ציפית שיקרה, ומה קרה בפועל',
            alignLabelWithHint: true,
            errorText: state.invalidField == 'description'
                ? 'יש לתאר את התקלה'
                : null,
          ),
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
          maxLines: 5,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppSurfaces.card(context),
            hintText: 'מה עשית לפני שהתקלה הופיעה',
            alignLabelWithHint: true,
          ),
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
            filled: true,
            fillColor: AppSurfaces.card(context),
            hintText: 'name@example.com',
            errorText: state.invalidField == 'reporterEmail'
                ? 'נדרשת כתובת תקינה'
                : null,
          ),
          onChanged: (value) => bloc.add(AppReportEmailChanged(value)),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        AppReportImagesSection(
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
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppTokens.spaceSM),
        Expanded(
          child: Text(
            'הטופס נטען מטיוטה שמורה',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ActionButton.ghost(
          key: const ValueKey('app-report-discard-draft'),
          text: 'מחק טיוטה',
          icon: FluentIcons.delete_24_regular,
          onPressed: enabled ? _discardDraft : null,
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, AppReportState state) {
    final editing = state is AppReportEditing ? state : null;
    final isSending = editing?.isSending ?? false;
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ActionButton.ghost(
            text: 'ביטול',
            onPressed: isSending ? null : () => Navigator.of(context).pop(),
          ),
          if (_bloc.supportsDraft) ...[
            const SizedBox(width: 8),
            ActionButton.neutral(
              key: const ValueKey('app-report-save-draft'),
              text: 'שמור טיוטה',
              icon: FluentIcons.save_24_regular,
              onPressed: editing == null || isSending
                  ? null
                  : () => _bloc.add(const AppReportDraftSaved()),
            ),
          ],
          const SizedBox(width: 8),
          ActionButton.recommended(
            key: const ValueKey('app-report-send'),
            text: 'שלח',
            icon: FluentIcons.send_24_regular,
            isLoading: isSending,
            onPressed: editing == null || isSending
                ? null
                : () => _bloc.add(const AppReportSubmitted()),
          ),
        ],
      ),
    );
  }

  void _discardDraft() {
    _bloc.add(const AppReportDraftDiscarded());
    UiSnack.show(ReportMessages.appReportDraftDiscarded);
  }
}
