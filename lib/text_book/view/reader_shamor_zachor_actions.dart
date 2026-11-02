import 'dart:io';
import 'dart:async';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/settings_exports.dart' hide UpdateFontSize;
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';

/// פעולות שמור וזכור של הקורא: בדיקת מעקב, סימון התקדמות והוספה למעקב.
mixin ReaderShamorZachorActions<T extends StatefulWidget> on State<T> {
  /// הטאב של הקורא; ממנו המיקום הנוכחי בספר.
  TextBookTab get readerTab;

  /// Check if book is already being tracked in Shamor Zachor
  /// שמור וזכור נשען על מזהי seforim.db בלבד; ספר ממקור אחר מחזיק מזהה
  /// ממרחב אחר שעלול להתנגש עם ספר רשמי אקראי, ולכן אינו נתמך.
  bool isOfficialSeforimBook(Book book) =>
      book.id != null &&
      book.isOfficialLibraryBook &&
      !DatabaseConstants.isTalmudBavliPdfExternalLibraryId(
        book.externalLibraryId,
      );

  bool isBookTrackedInShamorZachor(Book book) {
    if (!isOfficialSeforimBook(book)) return false;
    try {
      final dataProvider = context.read<ShamorZachorDataProvider>();
      if (!dataProvider.hasData) return false;
      return dataProvider.getBookById(book.id!) != null;
    } catch (e) {
      debugPrint('Error checking if book is tracked: $e');
      return false;
    }
  }

  /// סימון V בשמור וזכור
  Future<void> markShamorZachorProgress(String bookTitle) async {
    try {
      final dataProvider = context.read<ShamorZachorDataProvider>();
      final progressProvider = context.read<ShamorZachorProgressProvider>();
      await dataProvider.ensureLoaded();
      if (!mounted) return;
      final state = context.read<TextBookBloc>().state;
      if (state is! TextBookLoaded) return;

      if (!dataProvider.hasData) {
        UiSnack.showError(TextBookMessages.shamorZachorDataNotLoaded);
        return;
      }

      // בדיקה אם יש ID לספר - אם לא, נחפש לפי כותרת
      int? bookId = state.book.id;
      if (bookId == null) {
        final resolvedBook = await BookDatabaseResolver.resolveBook(
          title: bookTitle,
          categoryId: state.book.categoryId,
          fileType: state.book.fileType,
          filePath: state.book.filePath,
          preferSource: BookDatabaseResolver.likelySource(
            source: state.book.source,
            categoryPath: state.book.categoryPath,
          ),
        );
        bookId = resolvedBook?.book.id;
      }

      if (bookId == null) {
        UiSnack.showError(TextBookMessages.bookNotFoundInDatabase);
        return;
      }

      // חיפוש הספר לפי ID ב-shamor zachor
      final result = dataProvider.getBookById(bookId);

      if (result == null) {
        UiSnack.showError(TextBookMessages.bookNotFoundInShamorZachor);
        return;
      }

      final (bookDetails, _, _) = result;

      // שורת מקור (לא segmentIndex של מצב רצף).
      final currentIndex = readerTab.index;

      // טווחי BookSection הם שורות מקור; כותרות יכולות לחזור בין פרקים.
      BookSection? findCurrentSection(List<BookSection> sections) {
        for (final section in sections) {
          if (currentIndex < section.startPage ||
              currentIndex > section.endPage) {
            continue;
          }
          if (section.isLeaf) return section;
          final child = findCurrentSection(section.children);
          if (child != null) return child;
        }
        return null;
      }

      final section = findCurrentSection(bookDetails.sections ?? const []);
      final targetItem = section == null
          ? null
          : bookDetails.learnableItems.firstWhereOrNull(
              (item) => item.sectionId == section.id,
            );
      if (targetItem == null) {
        final currentRef = await refFromIndex(
          currentIndex,
          state.book.tableOfContents,
        );
        throw Exception('$currentRef לא נמצא בשמור וזכור');
      }
      final displayName = targetItem.hierarchyPath.join(', ');

      // בדיקת מצב העמודות עבור הפרק הספציפי - משתמשים ב-ID!
      final itemProgress = progressProvider.getProgressForItemById(
        bookId,
        targetItem.absoluteIndex,
      );

      // מציאת העמודה הראשונה שלא מסומנת
      String? columnToMark;
      const columns = ['learn', 'review1', 'review2', 'review3'];

      for (final column in columns) {
        if (!itemProgress.getProperty(column)) {
          columnToMark = column;
          break;
        }
      }

      if (columnToMark == null) {
        UiSnack.show(TextBookMessages.noFreeSlotInChapter(displayName));
        return;
      }

      // סימון הפרק הספציפי - משתמשים ב-ID!
      await progressProvider.updateProgressById(
        bookId,
        targetItem.absoluteIndex,
        columnToMark,
        true,
        bookDetails,
      );

      final columnName = _getColumnDisplayName(columnToMark);
      UiSnack.show(TextBookMessages.chapterMarked(displayName, columnName));
    } catch (e) {
      debugPrint('Error in markShamorZachorProgress: $e');
      UiSnack.showError(TextBookMessages.markingError(e));
    }
  }

  /// קבלת שם העמודה להצגה
  String _getColumnDisplayName(String column) {
    switch (column) {
      case 'learn':
        return 'נלמד';
      case 'review1':
        return 'חזרה ראשונה';
      case 'review2':
        return 'חזרה שנייה';
      case 'review3':
        return 'חזרה שלישית';
      default:
        return column;
    }
  }

  /// Add book to Shamor Zachor tracking
  Future<void> addBookToShamorZachorTracking(Book book) async {
    if (!isOfficialSeforimBook(book)) {
      UiSnack.showError(TextBookMessages.onlyOfficialBooksSupportedInTracking);
      return;
    }
    try {
      final dataProvider = context.read<ShamorZachorDataProvider>();

      final bookTitle = book.title;

      // 1. Get book path from library or database
      String? bookPath = book.filePath;

      if (bookPath == null) {
        final location = await BookLocator.locateBook(
          bookTitle,
          categoryId: book.categoryId,
        );
        bookPath = location?.filePath;
      }

      // If not found in file system, try to get category from database
      if (bookPath == null) {
        String categoryPath = '';
        // Try to use the category path from the book object first
        if (book.categoryPath != null && book.categoryPath!.isNotEmpty) {
          categoryPath = book.categoryPath!.replaceAll(', ', '/');
        } else {
          final dbProvider = SqliteDataProvider.instance;
          if (await dbProvider.databaseExists() && dbProvider.isInitialized) {
            try {
              final resolvedBook = await BookDatabaseResolver.resolveBook(
                title: bookTitle,
                categoryId: book.categoryId,
                fileType: book.fileType,
                filePath: book.filePath,
                preferSource: BookDatabaseResolver.likelySource(
                  source: book.source,
                  categoryPath: book.categoryPath,
                ),
              );
              if (resolvedBook != null) {
                categoryPath = await BookDatabaseResolver.buildCategoryPath(
                  resolvedBook.repository,
                  resolvedBook.book.categoryId,
                );
                categoryPath = categoryPath.replaceAll(', ', '/');
              }
            } catch (e) {
              debugPrint('Error getting category from DB: $e');
            }
          }
        }

        if (categoryPath.isNotEmpty) {
          final libraryPath =
              Settings.getValue<String>(SettingsRepository.keyLibraryPath) ??
              '.';
          bookPath =
              '$libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}$categoryPath${Platform.pathSeparator}$bookTitle.txt';
          debugPrint('Book path from DB: $bookPath');
        }
      }

      if (bookPath == null) {
        UiSnack.showError(TextBookMessages.bookPathNotFound);
        return;
      }

      debugPrint('Adding book to tracking - Path: $bookPath');

      // 2. Use the actual book title as-is (don't modify it)
      // The title should match exactly what's in the DB
      String cleanBookName = bookTitle;

      // 3. Show loading indicator
      UiSnack.show(TextBookMessages.addingBookToTracking);

      // 4. Add book via provider (only needs book name)
      await dataProvider.addCustomBook(
        bookName: cleanBookName,
        bookId: book.id,
        categoryId: book.categoryId,
      );

      // 5. Success message
      UiSnack.show(TextBookMessages.bookAddedToTracking(cleanBookName));

      // 6. Update UI to reflect the change
      setState(() {});
    } catch (e, stackTrace) {
      debugPrint('Error adding book to Shamor Zachor: $e');
      debugPrint('Stack trace: $stackTrace');
      UiSnack.showError(TextBookMessages.addBookToTrackingError(e));
    }
  }
}
