import 'package:equatable/equatable.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/models/app_report_image.dart';

/// אירועי טופס הדיווח על התוכנה.
sealed class AppReportEvent extends Equatable {
  const AppReportEvent();

  @override
  List<Object?> get props => const [];
}

/// איסוף האבחון וקטע הלוג, לפני הצגת הטופס.
class AppReportAttachmentsRequested extends AppReportEvent {
  const AppReportAttachmentsRequested();
}

class AppReportTypeChanged extends AppReportEvent {
  const AppReportTypeChanged(this.type);

  final AppReportType type;

  @override
  List<Object?> get props => [type];
}

class AppReportTitleChanged extends AppReportEvent {
  const AppReportTitleChanged(this.title);

  final String title;

  @override
  List<Object?> get props => [title];
}

class AppReportDescriptionChanged extends AppReportEvent {
  const AppReportDescriptionChanged(this.description);

  final String description;

  @override
  List<Object?> get props => [description];
}

class AppReportStepsChanged extends AppReportEvent {
  const AppReportStepsChanged(this.steps);

  final String steps;

  @override
  List<Object?> get props => [steps];
}

class AppReportEmailChanged extends AppReportEvent {
  const AppReportEmailChanged(this.email);

  final String email;

  @override
  List<Object?> get props => [email];
}

/// הכללה או החרגה של מפת האבחון מהדיווח.
class AppReportDiagnosticsToggled extends AppReportEvent {
  const AppReportDiagnosticsToggled(this.include);

  final bool include;

  @override
  List<Object?> get props => [include];
}

/// הכללה או החרגה של קטע הלוג מהדיווח.
class AppReportErrorLogToggled extends AppReportEvent {
  const AppReportErrorLogToggled(this.include);

  final bool include;

  @override
  List<Object?> get props => [include];
}

/// החלפת רשימת התמונות המצורפות (הוספה או הסרה).
class AppReportImagesChanged extends AppReportEvent {
  const AppReportImagesChanged(this.images);

  final List<AppReportImage> images;

  @override
  List<Object?> get props => [images];
}

class AppReportSubmitted extends AppReportEvent {
  const AppReportSubmitted();
}
