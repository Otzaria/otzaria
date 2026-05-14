import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/utils/file/zip_extractor_service.dart';

class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  final DataRepository _repository = DataRepository.instance;
  int _searchGeneration = 0;

  LibraryBloc() : super(LibraryState.initial()) {
    on<LoadLibrary>(_onLoadLibrary);
    on<RefreshLibrary>(_onRefreshLibrary);
    on<UpdateLibraryPath>(_onUpdateLibraryPath);
    on<UpdateHebrewBooksPath>(_onUpdateHebrewBooksPath);
    on<RemoveHebrewBooksPath>(_onRemoveHebrewBooksPath);
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
      await _pruneRemovedCustomFoldersIfNeeded();
      DataRepository.instance.library = FileSystemData.instance.getLibrary();
      DataRepository.instance.invalidateExternalBooksCache();
      Library library = await _repository.library;

      emit(state.copyWith(
        library: library,
        currentCategory: library,
        isLoading: false,
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

  Future<void> _onRefreshLibrary(
    RefreshLibrary event,
    Emitter<LibraryState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _pruneRemovedCustomFoldersIfNeeded();

      // שמירת המיקום הנוכחי בספרייה
      final currentCategoryPath =
          _getCurrentCategoryPath(state.currentCategory);

      // צלם את מפתחות הספרים לפני הרענון לצורך זיהוי ספרים חדשים
      final keysBeforeRefresh = state.library
              ?.getAllBooks()
              .map((b) => IndexingRepository.catalogueOrderKey(b))
              .toSet() ??
          <String>{};

      final libraryPath =
          Settings.getValue<String>(SettingsRepository.keyLibraryPath);
      if (libraryPath != null) {
        FileSystemData.instance.libraryPath = libraryPath;
      }

      // רענון הספרייה מהמערכת קבצים
      DataRepository.instance.library = FileSystemData.instance.getLibrary();
      DataRepository.instance.invalidateExternalBooksCache();
      final library = await _repository.library;

      try {
        await TantivyDataProvider.instance.reopenIndex();
      } catch (e) {
        // אם יש בעיה עם פתיחת האינדקס מחדש, נמשיך בלי זה
        // הספרייה עדיין תתרענן אבל החיפוש עלול לא לעבוד עד להפעלה מחדש
        developer.log('Warning: Could not reopen search index',
            name: 'LibraryBloc', error: e);
      }

      // זיהוי ספרים חדשים שנוספו ברענון
      final newBooksToIndex = library
          .getAllBooks()
          .where((b) => !keysBeforeRefresh
              .contains(IndexingRepository.catalogueOrderKey(b)))
          .toList();

      // חזרה לאותה תיקייה שהיתה פתוחה קודם
      final targetCategory = _findCategoryByPath(library, currentCategoryPath);

      emit(state.copyWith(
        library: library,
        currentCategory: targetCategory ?? library,
        isLoading: false,
        newBooksToIndex: newBooksToIndex.isNotEmpty ? newBooksToIndex : null,
      ));
    } catch (e) {
      emit(state.copyWith(
        error: e.toString(),
        isLoading: false,
      ));
    }
  }

  Future<void> _pruneRemovedCustomFoldersIfNeeded() async {
    final sqliteProvider = SqliteDataProvider.instance;
    if (!sqliteProvider.isInitialized) {
      await sqliteProvider.initialize();
    }

    final repository = sqliteProvider.repository;
    if (repository == null) {
      return;
    }

    final customFoldersJson =
        Settings.getValue<String>(SettingsRepository.keyCustomFolders);
    final customFolders = CustomFoldersManager.loadFolders(customFoldersJson);

    // התיקיות המותאמות אישית חיות ב-user_books.db. ה-FileSyncService
    // צריך גישה לשני ה-DBs (seforim ל-links, user_books ל-prune).
    final userBooksDbPath = await UserBooksDatabaseHolder.resolveDbPath();
    if (!await File(userBooksDbPath).exists()) {
      return;
    }

    final userBooksRepository =
        await UserBooksDatabaseHolder.instance.repository;
    final syncService = await FileSyncService.getInstance(
      repository,
      userBooksRepository: userBooksRepository,
    );
    if (syncService == null) {
      return;
    }

    await syncService.refreshSourcesAndPruneRemovedCustomFolders(customFolders);
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
      await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName, '');
      // ניקוי override Android — DB החדש נמצא ישירות בספרייה
      await Settings.setValue<String>(
          SettingsRepository.keyDbEffectivePath, '');

      FileSystemData.instance.libraryPath = event.path;
      DataRepository.instance.library = FileSystemData.instance.getLibrary();
      DataRepository.instance.invalidateExternalBooksCache();

      // פתיחה מחדש של אינדקס החיפוש
      try {
        await TantivyDataProvider.instance.reopenIndex();
      } catch (e) {
        developer.log('Warning: Could not reopen search index',
            name: 'LibraryBloc', error: e);
      }

      final library = await _repository.library;

      emit(state.copyWith(
        library: library,
        currentCategory: library,
        isLoading: false,
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
      DataRepository.instance.invalidateExternalBooksCache();

      final library = await _repository.library;

      emit(state.copyWith(
        library: library,
        currentCategory: library,
        isLoading: false,
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

  /// הסרת מיקום ספרי היברובוקס
  Future<void> _onRemoveHebrewBooksPath(
    RemoveHebrewBooksPath event,
    Emitter<LibraryState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      // מחיקת הנתיב מההגדרות
      await Settings.setValue<String>(
          SettingsRepository.keyHebrewBooksPath, '');

      // רענון הספרייה כדי להסיר את ספרי היברובוקס
      DataRepository.instance.library = FileSystemData.instance.getLibrary();
      DataRepository.instance.invalidateExternalBooksCache();

      final library = await _repository.library;

      emit(state.copyWith(
        library: library,
        currentCategory: library,
        isLoading: false,
        searchResults: null,
        searchQuery: null,
        selectedTopics: null,
      ));

      developer.log('Hebrew books path removed successfully',
          name: 'LibraryBloc');
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
    emit(state.copyWith(
      currentCategory: event.category,
      searchQuery: null,
      searchResults: null,
      selectedTopics: null,
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
    emit(state.copyWith(
      searchQuery: event.query,
      searchResults: state.searchResults,
    ));
  }

  Future<void> _onSearchBooks(
    SearchBooks event,
    Emitter<LibraryState> emit,
  ) async {
    if (state.searchQuery == null || state.searchQuery!.length < 3) {
      emit(state.copyWith(
        searchResults: null,
        isSearching: false,
      ));
      return;
    }

    try {
      final searchGeneration = ++_searchGeneration;
      final query = state.searchQuery!;
      final category = state.currentCategory;
      final topics = List<String>.from(state.selectedTopics ?? const []);
      final includeOtzar = event.showOtzarHachochma ?? false;
      final includeHebrewBooks = event.showHebrewBooks ?? false;

      emit(state.copyWith(
        isSearching: true,
        searchResults: state.searchResults,
      ));

      final results = await _repository.findBooks(
        query,
        category,
        topics: topics,
        includeOtzar: includeOtzar,
        includeHebrewBooks: includeHebrewBooks,
      );

      if (searchGeneration != _searchGeneration ||
          state.searchQuery != query ||
          state.currentCategory != category ||
          !_sameStringList(state.selectedTopics ?? const [], topics)) {
        // אם אין חיפוש חדש שעקף (אותה גנרציה), נאפס את דגל הטעינה
        // כדי שלא יישאר תקוע (למשל אחרי NavigateToCategory מבלי SearchBooks).
        if (searchGeneration == _searchGeneration) {
          emit(state.copyWith(
            isSearching: false,
            searchResults: state.searchResults,
          ));
        }
        return;
      }

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
        isSearching: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        error: e.toString(),
        searchResults: null,
        isSearching: false,
      ));
    }
  }

  bool _sameStringList(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
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
      searchResults: state.searchResults,
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
