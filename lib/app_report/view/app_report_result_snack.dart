import 'package:flutter/widgets.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/reports/view_scope.dart';

/// Shared delivery feedback; only interface messages are translated.
void showAppReportResultSnack(
  AppReportDeliveryResult result, {
  BuildContext? context,
}) {
  String text(String source, {Map<String, Object?>? args}) => context == null
      ? source.replaceAllMapped(
          RegExp(r'\{([^}]+)\}'),
          (m) => '${args?[m[1]] ?? m[0]}',
        )
      : reportText(context, source, args: args);
  switch (result.status) {
    case AppReportDeliveryStatus.sent:
      final number = result.issueNumber;
      UiSnack.showSuccess(
        result.merged
            ? number == null
                  ? text('הדיווח צורף לדיווח קיים על אותה תקלה. תודה!')
                  : text(
                      'הדיווח צורף לדיווח קיים מספר {number} על אותה תקלה. תודה!',
                      args: {'number': number},
                    )
            : number == null
            ? text(ReportMessages.sentToOtzaria)
            : text(
                'הדיווח נקלט ונפתח עבורו דיווח מספר {number}. תודה!',
                args: {'number': number},
              ),
      );
    case AppReportDeliveryStatus.queued:
      UiSnack.show(
        text(
          result.report.schema >= 2
              ? ReportMessages.extendedReportQueued
              : 'הדיווח נשמר בתור לשליחה. ניתן לנהל או לייצא אותו בהגדרות.',
        ),
      );
    case AppReportDeliveryStatus.failed:
      UiSnack.showError(
        result.failureReason == AppReportFailureReason.offlineQueueDisabled
            ? text(ReportMessages.offlineQueueDisabled)
            : result.failureReason ==
                  AppReportFailureReason.serverUpgradeRequired
            ? text(ReportMessages.reportServerUpgradeRequired)
            : text(ReportMessages.reportRejectedPreserved),
      );
  }
}

String appReportInvalidFieldMessage(
  String field, {
  required bool emailEmpty,
  BuildContext? context,
}) {
  final source = switch (field) {
    'title' => ReportMessages.appReportTitleRequired,
    'description' => ReportMessages.appReportDescriptionRequired,
    'reporterEmail' =>
      emailEmpty
          ? ReportMessages.appReportEmailRequired
          : ReportMessages.appReportInvalidEmail,
    'attachments.images' ||
    'attachments.minidump' ||
    'attachments.diagnostics' ||
    'attachments.errorLog' ||
    'attachments' =>
      'עד 10 MiB לקובץ, ועד 20 MiB לכל הצרופות יחד (1 MiB = 1,048,576 בתים).',
    'draftLoad' =>
      'לא ניתן לטעון את הטיוטה. יש לסגור ולנסות לפתוח אותה שוב; התוכן השמור לא שונה.',
    'draftSave' => 'לא ניתן לשמור את הטיוטה. הטופס נשאר פתוח; נסו שוב.',
    'draftFinalize' =>
      'הדיווח נמסר, אך הסרת הטיוטה לא הושלמה. לחצו על סיום השמירה המקומית כדי לנסות שוב בלי לשלוח שוב.',
    'delivery' =>
      'השליחה לא הושלמה. התוכן נשאר בטיוטה וניתן לערוך אותו או לשמור בתור.',
    _ => ReportMessages.sendFailed,
  };
  return context == null ? source : reportText(context, source);
}
