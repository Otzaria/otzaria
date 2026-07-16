import 'package:equatable/equatable.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

abstract class LibraryEvent extends Equatable {
  const LibraryEvent();

  @override
  List<Object?> get props => [];
}

class LoadLibrary extends LibraryEvent {}

class RefreshLibrary extends LibraryEvent {
  /// מפתחות catalogueOrderKey של ספרים שתוכנם השתנה ודורשים אינדוקס מחדש.
  final Set<String> changedBookKeys;

  const RefreshLibrary({this.changedBookKeys = const {}});

  @override
  List<Object?> get props => [changedBookKeys];
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

  const SearchBooks({this.showOtzarHachochma, this.showHebrewBooks});

  @override
  List<Object?> get props => [showOtzarHachochma, showHebrewBooks];
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
