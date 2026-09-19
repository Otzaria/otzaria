import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/view/app_report_result_snack.dart';
import 'package:otzaria/app_report/view/widgets/app_report_images_section.dart';
import 'package:otzaria/app_report/view/widgets/app_report_preview_section.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

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
                previous.isFinished != current.isFinished),
        listener: (context, state) {
          if (state is! AppReportEditing) return;
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
                      'דיווח על תקלה בתוכנה',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Flexible(
                    child: switch (state) {
                      AppReportCollecting() => const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      AppReportEditing() => SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _buildForm(context, state),
                      ),
                    },
                  ),
                  _buildActions(context, state),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, AppReportEditing state) {
    final bloc = context.read<AppReportBloc>();
    final enabled = !state.isSending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSegmentedControl<AppReportType>(
          options: [
            for (final type in AppReportType.values)
              SegmentOption(value: type, label: appReportTypeLabel(type)),
          ],
          currentValue: state.type,
          expandToFillWidth: true,
          onChanged: enabled
              ? (type) => bloc.add(AppReportTypeChanged(type))
              : (_) {},
        ),
        const SizedBox(height: 16),
        RtlTextField(
          key: const ValueKey('app-report-title'),
          controller: _title,
          enabled: enabled,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'כותרת',
            errorText: state.invalidField == 'title' ? 'יש למלא כותרת' : null,
          ),
          onChanged: (value) => bloc.add(AppReportTitleChanged(value)),
        ),
        const SizedBox(height: 12),
        RtlTextField(
          key: const ValueKey('app-report-description'),
          controller: _description,
          enabled: enabled,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: 'מה קרה?',
            alignLabelWithHint: true,
            errorText: state.invalidField == 'description'
                ? 'יש לתאר את התקלה'
                : null,
          ),
          onChanged: (value) => bloc.add(AppReportDescriptionChanged(value)),
        ),
        const SizedBox(height: 12),
        RtlTextField(
          key: const ValueKey('app-report-steps'),
          controller: _steps,
          enabled: enabled,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'שלבים לשחזור (לא חובה)',
            alignLabelWithHint: true,
          ),
          onChanged: (value) => bloc.add(AppReportStepsChanged(value)),
        ),
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.ltr,
          child: RtlTextField(
            key: const ValueKey('app-report-email'),
            controller: _email,
            enabled: enabled,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'דואר אלקטרוני לחזרה אליך',
              errorText: state.invalidField == 'reporterEmail'
                  ? 'נדרשת כתובת תקינה'
                  : null,
            ),
            onChanged: (value) => bloc.add(AppReportEmailChanged(value)),
          ),
        ),
        const SizedBox(height: 16),
        AppReportImagesSection(
          images: state.images,
          enabled: enabled,
          onChanged: (images) => bloc.add(AppReportImagesChanged(images)),
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildActions(BuildContext context, AppReportState state) {
    final editing = state is AppReportEditing ? state : null;
    final isSending = editing?.isSending ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ActionButton.ghost(
            text: 'ביטול',
            onPressed: isSending ? null : () => Navigator.of(context).pop(),
          ),
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
}
