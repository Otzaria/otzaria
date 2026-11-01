import 'package:equatable/equatable.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

abstract class LibraryEvent extends Equatable {
  const LibraryEvent();

  @override
  List<Object?> get props => [];
}

class LoadLibrary extends LibraryEvent {}

/// מקור בקשת הרענון — קובע אם צריך prune של תיקיות מותאמות שנמחקו מהדיסק.
enum RefreshSource {
  /// רענון כללי — כולל prune (בדיקת תיקיות שנמחקו מהדיסק).
  general,

  /// רענון בעקבות סריקת תיקיות אישיות שהסתיימה — התיקיות כבר סונכרנו,
  /// לכן prune מיותר ומדלגים עליו.
  customFoldersScan,

  /// שינוי במסדים המצורפים — התיקיות האישיות לא השתנו, ומדלגים על prune.
  attachedLibraries,
}

/// רשימת ההסתרות השתנתה — בונה מחדש את העץ שהממשק מציג (issue #1448).
///
/// בלי האירוע הזה ההסתרה נכנסת לתוקף רק בהפעלה הבאה: [LibraryBloc] טוען את
/// העץ פעם אחת ושומר אותו ב-state, והמסנן חל רק ברגע הטעינה.
///
/// זול מ-[RefreshLibrary]: ה-Future הממוטמן של הקטלוג אינו נדרס, ורק עץ
/// הקטגוריות נבנה מחדש.
class HiddenBooksChanged extends LibraryEvent {
  const HiddenBooksChanged();

  @override
  List<Object?> get props => [];
}

/// bloc של חלון Dart אחר בנה את העץ מחדש (רענון, החלפת מסד, הסתרות): העץ נבנה
/// כאן מהקטלוג הטרי, כמו [HiddenBooksChanged], בלי להודיע הלאה.
class LibraryChangedInOtherWindow extends LibraryEvent {
  const LibraryChangedInOtherWindow();
}

/// קובץ ספר חיצוני נוסף לתיקייה: הקטלוג נסרק מחדש והאיתור המוצג רץ שוב.
class ExternalBooksChanged extends LibraryEvent {
  const ExternalBooksChanged();
}

class RefreshLibrary extends LibraryEvent {
  /// מפתחות catalogueOrderKey של ספרים שתוכנם השתנה ודורשים אינדוקס מחדש.
  final Set<String> changedBookKeys;

  final RefreshSource source;

  /// מזהי בקשה שידווחו ב-completedRefreshRequestIds בסיום הרענון שקלט אותם
  /// (גם אחרי מיזוג רענונים מקבילים). רענון שנכשל אינו מדווח אותם.
  final Set<int> requestIds;

  /// מסדים מצורפים שהקובץ שלהם השתנה — כל ספריהם דורשים אינדוקס מחדש.
  final Set<String> changedAttachedSlugs;

  const RefreshLibrary({
    this.changedBookKeys = const {},
    this.source = RefreshSource.general,
    this.requestIds = const {},
    this.changedAttachedSlugs = const {},
  });

  @override
  List<Object?> get props => [
    changedBookKeys,
    source,
    requestIds,
    changedAttachedSlugs,
  ];
}

class UpdateLibraryPath extends LibraryEvent {
  final String path;

  const UpdateLibraryPath(this.path);

  @override
  List<Object?> get props => [path];
}

class UpdateHebrewBooksPath extends LibraryEvent {
  final String path;

  const UpdateHebrewBooksPath(this.path);

  @override
  List<Object?> get props => [path];
}

class RemoveHebrewBooksPath extends LibraryEvent {
  const RemoveHebrewBooksPath();
}

class NavigateToCategory extends LibraryEvent {
  final Category category;

  const NavigateToCategory(this.category);

  @override
  List<Object?> get props => [category];
}

class NavigateUp extends LibraryEvent {}

class SearchBooks extends LibraryEvent {
  final bool? showOtzarHachochma;
  final bool? showHebrewBooks;
  final bool? showLocalHebrewBooks;

  /// ספרים מחוץ לספרייה שמצטרפים לחיפוש (ספרים שתוספים הוסיפו).
  final List<Book> extraBooks;

  /// מחפש רק ב-[extraBooks], בלי ספרי הספרייה והקטלוגים החיצוניים.
  final bool extraBooksOnly;

  /// חיפוש חוזר כשהספרים שמבחוץ השתנו: הספר שבתצוגה המקדימה נשאר, אם הוא
  /// עדיין בתוצאות.
  final bool keepPreview;

  const SearchBooks({
    this.showOtzarHachochma,
    this.showHebrewBooks,
    this.showLocalHebrewBooks,
    this.extraBooks = const [],
    this.extraBooksOnly = false,
    this.keepPreview = false,
  });

  @override
  List<Object?> get props => [
    showOtzarHachochma,
    showHebrewBooks,
    showLocalHebrewBooks,
    extraBooks,
    extraBooksOnly,
    keepPreview,
  ];
}

class UpdateSearchQuery extends LibraryEvent {
  final String query;

  const UpdateSearchQuery(this.query);

  @override
  List<Object?> get props => [query];
}

class SelectTopics extends LibraryEvent {
  final List<String> topics;

  const SelectTopics(this.topics);

  @override
  List<Object?> get props => [topics];
}

class SelectBookForPreview extends LibraryEvent {
  final Book book;

  const SelectBookForPreview(this.book);

  @override
  List<Object?> get props => [book];
}

class SelectCategoryForPreview extends LibraryEvent {
  final Category category;

  const SelectCategoryForPreview(this.category);

  @override
  List<Object?> get props => [category];
}
