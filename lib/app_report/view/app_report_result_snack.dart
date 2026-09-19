import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';

/// הודעת הסיום של שליחת דיווח על התוכנה, משותפת לטופס, להצעה אחרי קריסה
/// ולניהול התור בהגדרות.
void showAppReportResultSnack(AppReportDeliveryResult result) {
  switch (result.status) {
    case AppReportDeliveryStatus.sent:
      if (result.merged) {
        UiSnack.showSuccess(ReportMessages.appReportMerged(result.issueNumber));
      } else {
        UiSnack.showSuccess(ReportMessages.appReportSent(result.issueNumber));
      }
    case AppReportDeliveryStatus.queued:
      UiSnack.show(ReportMessages.appReportQueued);
    case AppReportDeliveryStatus.failed:
      UiSnack.showError(
        result.failureReason == AppReportFailureReason.offlineQueueDisabled
            ? ReportMessages.offlineQueueDisabled
            : ReportMessages.appReportRejected(result.rejectedField),
      );
  }
}

/// הודעת הכישלון של בדיקת התקינות המקומית, לפי השדה שהוחזר מ-`validate`.
String appReportInvalidFieldMessage(String field, {required bool emailEmpty}) {
  switch (field) {
    case 'title':
      return ReportMessages.appReportTitleRequired;
    case 'description':
      return ReportMessages.appReportDescriptionRequired;
    case 'reporterEmail':
      return emailEmpty
          ? ReportMessages.appReportEmailRequired
          : ReportMessages.appReportInvalidEmail;
    default:
      return ReportMessages.sendFailed;
  }
}
