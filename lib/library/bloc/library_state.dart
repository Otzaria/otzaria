import 'package:equatable/equatable.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';

class LibraryState extends Equatable {
  final Library? library;
  final bool isLoading;

  /// שגיאת הפעולה האחרונה. מתאפסת אחרי כל copyWith, אחרת מסך הספרייה נתקע עליה.
  final String? error;
  final Category? currentCategory;
  final List<Book>? searchResults;

  /// קטגוריות שכותרתן תואמת לשאילתה — קבוצת "תיקיות" אחרי הספרים בתוצאות.
  final List<Category>? searchCategoryResults;
  final String? searchQuery;
  final List<String>? selectedTopics;
  final Book? previewBook;

  /// תיקייה שנבחרה לתצוגה מקדימה. בלעדית ל-[previewBook] — בחירת אחד מנקה את השני.
  final Category? previewCategory;

  /// ספרים חדשים שנמצאו ברענון ודורשים אינדוקס. מתאפס אחרי כל copyWith.
  final List<Book>? newBooksToIndex;

  /// ספרים שתוכנם השתנה ודורשים אינדוקס מחדש. מתאפס אחרי כל copyWith.
  final List<Book>? changedBooksToIndex;

  /// ספרים שהועברו קטגוריה; יש לבדוק אם מיקומם באינדקס עדיין שונה.
  final List<Book>? booksToCheckForIndex;

  /// מזהי RefreshLibrary.requestIds שהרענון הזה השלים בהצלחה.
  /// מתאפס אחרי כל copyWith.
  final Set<int>? completedRefreshRequestIds;

  /// מזהי בקשות הרענון שהסתיימו בכשל. מתאפס אחרי כל copyWith.
  final Set<int>? failedRefreshRequestIds;

  /// נתיב HebrewBooks ששונה. מתאפס אחרי כל copyWith.
  final String? changedHebrewBooksPath;

  /// האם חיפוש בספרייה רץ כעת. משמש להצגת סמל "טוען" באזור התוצאות.
  final bool isSearching;

  const LibraryState({
    this.library,
    this.isLoading = false,
    this.error,
    this.currentCategory,
    this.searchResults,
    this.searchCategoryResults,
    this.searchQuery,
    this.selectedTopics,
    this.previewBook,
    this.previewCategory,
    this.newBooksToIndex,
    this.changedBooksToIndex,
    this.booksToCheckForIndex,
    this.completedRefreshRequestIds,
    this.failedRefreshRequestIds,
    this.changedHebrewBooksPath,
    this.isSearching = false,
  });

  /// מעבר "טעינה הסתיימה בהצלחה" — משמש להאזנה לריענון הספרייה (עדכון,
  /// החלפת מיקום) במקומות שמציגים נתונים הנגזרים ממנה, כמו גרסת הספרייה.
  static bool reloadCompleted(LibraryState previous, LibraryState current) =>
      previous.isLoading && !current.isLoading && current.library != null;

  /// לעצים שמציגים את הקטלוג בלבד: חיפוש, ניווט ותצוגה מקדימה במסך הספרייה
  /// אינם משנים אותם.
  static bool catalogChanged(LibraryState previous, LibraryState current) =>
      !identical(previous.library, current.library) ||
      previous.isLoading != current.isLoading ||
      previous.error != current.error;

  static bool refreshRequestSettled(LibraryState state, int requestId) =>
      (state.completedRefreshRequestIds?.contains(requestId) ?? false) ||
      (state.failedRefreshRequestIds?.contains(requestId) ?? false);

  factory LibraryState.initial() {
    // ספרייה ראשונית עד שהקטלוג נטען: קטגוריות השורש של ה-DB, קבועות בקוד
    final placeholderCategories = [
      Category(
        title: 'תנ״ך',
        description: '',
        shortDescription: '',
        order: 5,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'תלמוד בבלי',
        description: '',
        shortDescription: '',
        order: 5,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'משנה',
        description: '',
        shortDescription: '',
        order: 10,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'תלמוד ירושלמי',
        description: '',
        shortDescription: '',
        order: 10,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'מדרש',
        description: '',
        shortDescription: '',
        order: 20,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'הלכה',
        description: '',
        shortDescription: '',
        order: 25,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'קבלה',
        description: '',
        shortDescription: '',
        order: 30,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'סדר התפילה',
        description: '',
        shortDescription: '',
        order: 35,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'מחשבת ישראל',
        description: '',
        shortDescription: '',
        order: 40,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'תוספתא',
        description: '',
        shortDescription: '',
        order: 45,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'חסידות',
        description: '',
        shortDescription: '',
        order: 50,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'ספרי מוסר',
        description: '',
        shortDescription: '',
        order: 55,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'שו״ת',
        description: '',
        shortDescription: '',
        order: 60,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'בית שני',
        description: '',
        shortDescription: '',
        order: 65,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'מילונים וספרי יעץ',
        description: '',
        shortDescription: '',
        order: 70,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'ספרים מספריות חיצוניות',
        description: '',
        shortDescription: '',
        order: 75,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'לימוד יומי',
        description: '',
        shortDescription: '',
        order: 999,
        subCategories: [],
        books: [],
        parent: null,
      ),
      Category(
        title: 'ספרות עזר',
        description: '',
        shortDescription: '',
        order: 999,
        subCategories: [],
        books: [],
        parent: null,
      ),
    ];

    final placeholderLibrary = Library(categories: placeholderCategories);

    return LibraryState(
      library: placeholderLibrary,
      currentCategory: placeholderLibrary,
      isLoading: true,
    );
  }

  /// [clearPreviewBook] מאפס את התצוגה המקדימה (ספר ותיקייה); בלי הדגל null נשמר.
  LibraryState copyWith({
    Library? library,
    bool? isLoading,
    String? error,
    Category? currentCategory,
    List<Book>? searchResults,
    List<Category>? searchCategoryResults,
    String? searchQuery,
    List<String>? selectedTopics,
    Book? previewBook,
    Category? previewCategory,
    bool clearPreviewBook = false,
    List<Book>? newBooksToIndex,
    List<Book>? changedBooksToIndex,
    List<Book>? booksToCheckForIndex,
    Set<int>? completedRefreshRequestIds,
    Set<int>? failedRefreshRequestIds,
    String? changedHebrewBooksPath,
    bool? isSearching,
  }) {
    return LibraryState(
      library: library ?? this.library,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentCategory: currentCategory ?? this.currentCategory,
      searchResults: searchResults,
      searchCategoryResults: searchCategoryResults,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedTopics: selectedTopics ?? this.selectedTopics,
      previewBook: clearPreviewBook || previewCategory != null
          ? null
          : (previewBook ?? this.previewBook),
      previewCategory: clearPreviewBook || previewBook != null
          ? null
          : (previewCategory ?? this.previewCategory),
      newBooksToIndex: newBooksToIndex, // null = אין ספרים לאינדוקס
      changedBooksToIndex: changedBooksToIndex, // null = אין ספרים שהשתנו
      booksToCheckForIndex: booksToCheckForIndex,
      completedRefreshRequestIds: completedRefreshRequestIds,
      failedRefreshRequestIds: failedRefreshRequestIds,
      changedHebrewBooksPath: changedHebrewBooksPath,
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
    searchCategoryResults,
    searchQuery,
    selectedTopics,
    previewBook,
    previewCategory,
    newBooksToIndex,
    changedBooksToIndex,
    booksToCheckForIndex,
    completedRefreshRequestIds,
    failedRefreshRequestIds,
    changedHebrewBooksPath,
    isSearching,
  ];
}
