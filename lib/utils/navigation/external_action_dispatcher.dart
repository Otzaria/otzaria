import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';

/// תרגום של [OpenBookAction] (URI מ-deep link) לקריאה ל-[BookOpenCoordinator].
///
/// ממוקם כפונקציה ייעודית כדי לאפשר טסט יחידה: בודקים ש-`navigateToPositionIfReused`
/// עובר כ-`true` רק כשה-URI ציין מיקום מפורש (index/mark/m), ולא ידרוס מיקום
/// של טאב פתוח כש-URI חשוף `otzaria://open/book/<id>`.
void dispatchOpenBookAction({
  required OpenBookAction action,
  required Book book,
  required BookOpenCoordinator coordinator,
}) {
  coordinator.openBook(
    book,
    action.index ?? 0,
    action.searchQuery ?? '',
    markSection: action.markSection,
    markText: action.markText,
    explicitIndex: action.hasExplicitPosition,
    navigateToPositionIfReused: action.hasExplicitPosition,
  );
}

/// תרגום של [OpenPdfBookAction] לקריאה ל-[BookOpenCoordinator]. ראה
/// [dispatchOpenBookAction] להסבר.
void dispatchOpenPdfBookAction({
  required OpenPdfBookAction action,
  required Book book,
  required BookOpenCoordinator coordinator,
}) {
  coordinator.openBook(
    book,
    action.page ?? 1,
    '',
    requiresStableLayout: true,
    explicitIndex: action.hasExplicitPosition,
    navigateToPositionIfReused: action.hasExplicitPosition,
  );
}
