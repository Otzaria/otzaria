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

  /// ספרים חדשים שנמצאו ברענון ודורשים אינדוקס. מתאפס אחרי כל copyWith.
  final List<Book>? newBooksToIndex;

  /// ספרים שתוכנם השתנה ודורשים אינדוקס מחדש. מתאפס אחרי כל copyWith.
  final List<Book>? changedBooksToIndex;

  /// האם חיפוש בספרייה רץ כעת. משמש להצגת סמל "טוען" באזור התוצאות.
  final bool isSearching;

  const LibraryState({
    this.library,
    this.isLoading = false,
    this.error,
    this.currentCategory,
    this.searchResults,
    this.searchQuery,
    this.selectedTopics,
    this.previewBook,
    this.newBooksToIndex,
    this.changedBooksToIndex,
    this.isSearching = false,
  });

  factory LibraryState.initial() {
    // יצירת ספרייה ראשונית עם כל הקטגוריות מה-DB
    final placeholderCategories = [
      Category(
          title: 'תנ״ך',
          description: '',
          shortDescription: '',
          order: 5,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'תלמוד בבלי',
          description: '',
          shortDescription: '',
          order: 5,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'משנה',
          description: '',
          shortDescription: '',
          order: 10,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'תלמוד ירושלמי',
          description: '',
          shortDescription: '',
          order: 10,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'מדרש',
          description: '',
          shortDescription: '',
          order: 20,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'הלכה',
          description: '',
          shortDescription: '',
          order: 25,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'קבלה',
          description: '',
          shortDescription: '',
          order: 30,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'סדר התפילה',
          description: '',
          shortDescription: '',
          order: 35,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'מחשבת ישראל',
          description: '',
          shortDescription: '',
          order: 40,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'תוספתא',
          description: '',
          shortDescription: '',
          order: 45,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'חסידות',
          description: '',
          shortDescription: '',
          order: 50,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'ספרי מוסר',
          description: '',
          shortDescription: '',
          order: 55,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'שו״ת',
          description: '',
          shortDescription: '',
          order: 60,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'בית שני',
          description: '',
          shortDescription: '',
          order: 65,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'מילונים וספרי יעץ',
          description: '',
          shortDescription: '',
          order: 70,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'ספרים מספריות חיצוניות',
          description: '',
          shortDescription: '',
          order: 75,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'לימוד יומי',
          description: '',
          shortDescription: '',
          order: 999,
          subCategories: [],
          books: [],
          parent: null),
      Category(
          title: 'ספרות עזר',
          description: '',
          shortDescription: '',
          order: 999,
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
    List<Book>? newBooksToIndex,
    List<Book>? changedBooksToIndex,
    bool? isSearching,
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
      newBooksToIndex: newBooksToIndex, // null = אין ספרים לאינדוקס
      changedBooksToIndex: changedBooksToIndex, // null = אין ספרים שהשתנו
      isSearching: isSearching ?? this.isSearching,
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
        newBooksToIndex,
        changedBooksToIndex,
        isSearching,
      ];
}
