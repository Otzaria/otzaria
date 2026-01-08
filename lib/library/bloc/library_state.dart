import 'package:equatable/equatable.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';

class LibraryState extends Equatable {
  final Library? library;
  final bool isLoading;
  final String? error;
  final Category? currentCategory;
  final List<Book>? searchResults;
  final String? searchQuery;
  final List<String>? selectedTopics;
  final Book? previewBook;

  const LibraryState({
    this.library,
    this.isLoading = false,
    this.error,
    this.currentCategory,
    this.searchResults,
    this.searchQuery,
    this.selectedTopics,
    this.previewBook,
  });

  factory LibraryState.initial() {
    // יצירת ספרייה ראשונית עם כל הקטגוריות הידועות
    final placeholderCategories = [
      Category(
          title: 'תנך',
          description: '',
          shortDescription: '',
          order: 1,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'משנה',
          description: '',
          shortDescription: '',
          order: 2,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'תלמוד בבלי',
          description: '',
          shortDescription: '',
          order: 3,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'תלמוד ירושלמי',
          description: '',
          shortDescription: '',
          order: 4,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'תוספתא',
          description: '',
          shortDescription: '',
          order: 5,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'מדרש',
          description: '',
          shortDescription: '',
          order: 6,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'הלכה',
          description: '',
          shortDescription: '',
          order: 7,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'קבלה',
          description: '',
          shortDescription: '',
          order: 8,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'סדר התפילה',
          description: '',
          shortDescription: '',
          order: 9,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'מחשבת ישראל',
          description: '',
          shortDescription: '',
          order: 10,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'חסידות',
          description: '',
          shortDescription: '',
          order: 11,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'ספרי מוסר',
          description: '',
          shortDescription: '',
          order: 12,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'שות',
          description: '',
          shortDescription: '',
          order: 13,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'ספרות עזר',
          description: '',
          shortDescription: '',
          order: 14,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'לימוד יומי',
          description: '',
          shortDescription: '',
          order: 16,
          subCategories: [],
          books: [],
          parent: null),
    ];

    final placeholderLibrary = Library(categories: placeholderCategories);

    return LibraryState(
      library: placeholderLibrary,
      currentCategory: placeholderLibrary,
      isLoading: true,
    );
  }

  LibraryState copyWith({
    Library? library,
    bool? isLoading,
    String? error,
    Category? currentCategory,
    List<Book>? searchResults,
    String? searchQuery,
    List<String>? selectedTopics,
    Book? previewBook,
  }) {
    return LibraryState(
      library: library ?? this.library,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      currentCategory: currentCategory ?? this.currentCategory,
      searchResults: searchResults,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedTopics: selectedTopics ?? this.selectedTopics,
      previewBook: previewBook ?? this.previewBook,
    );
  }

  @override
  List<Object?> get props => [
        library,
        isLoading,
        error,
        currentCategory,
        searchResults,
        searchQuery,
        selectedTopics,
        previewBook,
      ];
}
