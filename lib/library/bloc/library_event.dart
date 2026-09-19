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

  const SearchBooks({
    this.showOtzarHachochma,
    this.showHebrewBooks,
    this.showLocalHebrewBooks,
  });

  @override
  List<Object?> get props => [
    showOtzarHachochma,
    showHebrewBooks,
    showLocalHebrewBooks,
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
