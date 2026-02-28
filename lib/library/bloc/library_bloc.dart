import 'dart:developer' as developer;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/bloc/settings_repository.dart';
import 'package:otzaria/utils/zip_extractor_service.dart';

class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  final DataRepository _repository = DataRepository.instance;

  LibraryBloc() : super(LibraryState.initial()) {
    on<LoadLibrary>(_onLoadLibrary);
    on<RefreshLibrary>(_onRefreshLibrary);
    on<UpdateLibraryPath>(_onUpdateLibraryPath);
    on<UpdateHebrewBooksPath>(_onUpdateHebrewBooksPath);
    on<NavigateToCategory>(_onNavigateToCategory);
    on<NavigateUp>(_onNavigateUp);
    on<SearchBooks>(_onSearchBooks);
    on<SelectTopics>(_onSelectTopics);
    on<UpdateSearchQuery>(_onUpdateSearchQuery);
    on<SelectBookForPreview>(_onSelectBookForPreview);
  }

  Future<void> _onLoadLibrary(
    LoadLibrary event,
    Emitter<LibraryState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      Library library = await _repository.library;

      // בחירת הספר הראשון לתצוגה מקדימה
      final firstBook = _getFirstTextBook(library);

      emit(state.copyWith(
        library: library,
        currentCategory: library,
        isLoading: false,
        previewBook: firstBook,
        searchResults: null,
        searchQuery: null,
        selectedTopics: null,
      ));
      developer.log('📚 LibraryBloc: State emitted with isLoading=false',
          name: 'LibraryBloc');
    } catch (e) {
      developer.log('📚 LibraryBloc: Error loading library: $e',
          name: 'LibraryBloc');
      emit(state.copyWith(
        error: e.toString(),
        isLoading: false,
      ));
    }
  }

  /// מחזיר את ספר הטקסט הראשון בקטגוריה
  Book? _getFirstTextBook(Category category) {
    // חיפוש ספר טקסט בקטגוריה הנוכחית
    for (final book in category.books) {
      if (book is TextBook) {
        return book;
      }
    }

    // אם לא נמצא, חיפוש בתת-קטגוריות
    for (final subCategory in category.subCategories) {
      final book = _getFirstTextBook(subCategory);
      if (book != null) {
        return book;
      }
    }

    return null;
  }

  Future<void> _onRefreshLibrary(
    RefreshLibrary event,
    Emitter<LibraryState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      // שמירת המיקום הנוכחי בספרייה
      final currentCategoryPath =
          _getCurrentCategoryPath(state.currentCategory);

      final libraryPath =
          Settings.getValue<String>(SettingsRepository.keyLibraryPath);
      if (libraryPath != null) {
        FileSystemData.instance.libraryPath = libraryPath;
      }

      // רענון הספרייה מהמערכת קבצים
      DataRepository.instance.library = FileSystemData.instance.getLibrary();
      final library = await _repository.library;

      try {
        await TantivyDataProvider.instance.reopenIndex();
      } catch (e) {
        // אם יש בעיה עם פתיחת האינדקס מחדש, נמשיך בלי זה
        // הספרייה עדיין תתרענן אבל החיפוש עלול לא לעבוד עד להפעלה מחדש
        developer.log('Warning: Could not reopen search index',
            name: 'LibraryBloc', error: e);
      }

      // חזרה לאותה תיקייה שהיתה פתוחה קודם
      final targetCategory = _findCategoryByPath(library, currentCategoryPath);

      emit(state.copyWith(
        library: library,
        currentCategory: targetCategory ?? library,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        error: e.toString(),
        isLoading: false,
      ));
    }
  }

  /// מחזיר את הנתיב של התיקייה הנוכחית
  List<String> _getCurrentCategoryPath(Category? category) {
    if (category == null) return [];

    final path = <String>[];
    Category? current = category;
    final visited = <Category>{}; // למניעת לולאות אינסופיות

    while (current != null &&
        current.parent != null &&
        current.parent != current) {
      // בדיקה שלא ביקרנו כבר בקטגוריה הזו (למניעת לולאה אינסופית)
      if (visited.contains(current)) {
        break;
      }
      visited.add(current);

      path.insert(0, current.title);
      current = current.parent;
    }

    return path;
  }

  /// מוצא תיקייה לפי נתיב
  Category? _findCategoryByPath(Category rootCategory, List<String> path) {
    if (path.isEmpty) return rootCategory;

    Category current = rootCategory;

    for (final categoryName in path) {
      try {
        final found = current.subCategories
            .where((cat) => cat.title == categoryName)
            .first;
        current = found;
      } catch (e) {
        // אם לא מצאנו את התיקייה, נחזיר את הקרובה ביותר
        return current;
      }
    }

    return current;
  }

  Future<void> _onUpdateLibraryPath(
    UpdateLibraryPath event,
    Emitter<LibraryState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      // בדיקה וחילוץ קובץ ZIP אם קיים
      final extractionResult =
          await ZipExtractorService.checkAndExtractZipIfNeeded(event.path);

      if (!extractionResult.success) {
        emit(state.copyWith(
          error: extractionResult.errorMessage ?? 'שגיאה בחילוץ קובץ דחוס',
          isLoading: false,
        ));
        return;
      }

      // אם חולץ קובץ, נמתין רגע
      if (extractionResult.successfullyExtracted) {
        developer.log(
            'ZIP file extracted: ${extractionResult.extractedFileName}',
            name: 'LibraryBloc');
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath, event.path);
      FileSystemData.instance.libraryPath = event.path;
      DataRepository.instance.library = FileSystemData.instance.getLibrary();

      // פתיחה מחדש של אינדקס החיפוש
      try {
        await TantivyDataProvider.instance.reopenIndex();
      } catch (e) {
        developer.log('Warning: Could not reopen search index',
            name: 'LibraryBloc', error: e);
      }

      final library = await _repository.library;

      // בחירת הספר הראשון לתצוגה מקדימה
      final firstBook = _getFirstTextBook(library);

      emit(state.copyWith(
        library: library,
        currentCategory: library,
        isLoading: false,
        previewBook: firstBook,
        searchResults: null,
        searchQuery: null,
        selectedTopics: null,
      ));
    } catch (e) {
      emit(state.copyWith(
        error: e.toString(),
        isLoading: false,
      ));
    }
  }

  Future<void> _onUpdateHebrewBooksPath(
    UpdateHebrewBooksPath event,
    Emitter<LibraryState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      // בדיקה וחילוץ קובץ ZIP אם קיים
      final extractionResult =
          await ZipExtractorService.checkAndExtractZipIfNeeded(event.path);

      if (!extractionResult.success) {
        emit(state.copyWith(
          error: extractionResult.errorMessage ?? 'שגיאה בחילוץ קובץ דחוס',
          isLoading: false,
        ));
        return;
      }

      // אם חולץ קובץ, נמתין רגע
      if (extractionResult.successfullyExtracted) {
        developer.log(
            'ZIP file extracted: ${extractionResult.extractedFileName}',
            name: 'LibraryBloc');
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await Settings.setValue<String>('key-hebrew-books-path', event.path);

      // רענון הספרייה כדי לטעון את הספרים החדשים
      DataRepository.instance.library = FileSystemData.instance.getLibrary();

      final library = await _repository.library;

      // בחירת הספר הראשון לתצוגה מקדימה
      final firstBook = _getFirstTextBook(library);

      emit(state.copyWith(
        library: library,
        currentCategory: library,
        isLoading: false,
        previewBook: firstBook,
        searchResults: null,
        searchQuery: null,
        selectedTopics: null,
      ));
    } catch (e) {
      emit(state.copyWith(
        error: e.toString(),
        isLoading: false,
      ));
    }
  }

  void _onNavigateToCategory(
    NavigateToCategory event,
    Emitter<LibraryState> emit,
  ) {
    // בחירת הספר הראשון בקטגוריה החדשה
    final firstBook = _getFirstTextBook(event.category);

    emit(state.copyWith(
      currentCategory: event.category,
      searchQuery: null,
      searchResults: null,
      selectedTopics: null,
      previewBook: firstBook,
    ));
  }

  void _onNavigateUp(
    NavigateUp event,
    Emitter<LibraryState> emit,
  ) {
    if (state.currentCategory?.parent != null) {
      emit(state.copyWith(
        currentCategory: state.currentCategory!.parent!,
        searchQuery: null,
        searchResults: null,
        selectedTopics: null,
      ));
    }
  }

  void _onUpdateSearchQuery(
    UpdateSearchQuery event,
    Emitter<LibraryState> emit,
  ) {
    emit(state.copyWith(searchQuery: event.query));
  }

  Future<void> _onSearchBooks(
    SearchBooks event,
    Emitter<LibraryState> emit,
  ) async {
    if (state.searchQuery == null || state.searchQuery!.length < 3) {
      emit(state.copyWith(
        searchResults: null,
      ));
      return;
    }

    try {
      final results = await _repository.findBooks(
        state.searchQuery!,
        state.currentCategory,
        topics: state.selectedTopics,
        includeOtzar: event.showOtzarHachochma ?? false,
        includeHebrewBooks: event.showHebrewBooks ?? false,
      );

      // בחירת הספר הראשון מתוצאות החיפוש לתצוגה מקדימה
      Book? firstBook;
      if (results.isNotEmpty) {
        // העדפה לספר טקסט על פני PDF
        firstBook = results.firstWhere(
          (book) => book is TextBook,
          orElse: () => results.first,
        );
      }

      emit(state.copyWith(
        searchResults: results,
        previewBook: firstBook,
      ));
    } catch (e) {
      emit(state.copyWith(
        error: e.toString(),
        searchResults: null,
      ));
    }
  }

  void _onSelectTopics(
    SelectTopics event,
    Emitter<LibraryState> emit,
  ) {
    // כשמשנים את הנושאים, צריך לעדכן את הספר המוצג
    // אם יש תוצאות חיפוש, נבחר את הספר הראשון מהרשימה המסוננת
    Book? firstBook;
    if (state.searchResults != null && state.searchResults!.isNotEmpty) {
      final filteredResults = event.topics.isEmpty
          ? state.searchResults!
          : state.searchResults!.where((book) {
              return event.topics.any((topic) => book.topics.contains(topic));
            }).toList();

      if (filteredResults.isNotEmpty) {
        firstBook = filteredResults.firstWhere(
          (book) => book is TextBook,
          orElse: () => filteredResults.first,
        );
      }
    }

    emit(state.copyWith(
      selectedTopics: event.topics,
      previewBook: firstBook,
    ));
  }

  void _onSelectBookForPreview(
    SelectBookForPreview event,
    Emitter<LibraryState> emit,
  ) {
    emit(state.copyWith(
      previewBook: event.book,
      searchResults: state.searchResults,
    ));
  }
}
