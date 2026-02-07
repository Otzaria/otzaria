import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/settings_repository.dart';

/// שירות לניהול נתוני קובץ SourcesBooks.csv
/// טוען את הקובץ פעם אחת בהפעלת התוכנה ושומר בזיכרון
class SourcesBooksService {
  static final SourcesBooksService _instance = SourcesBooksService._internal();
  factory SourcesBooksService() => _instance;
  SourcesBooksService._internal();

  /// נתוני הספרים שנטענו מהקובץ CSV
  Map<String, Map<String, String>>? _booksData;

  /// האם הנתונים נטענו בהצלחה
  bool get isLoaded => _booksData != null;

  /// טעינת נתוני הקובץ CSV לזיכרון
  Future<void> loadSourcesBooks() async {
    try {
      debugPrint('Loading SourcesBooks.csv...');

      final libraryPath = Settings.getValue(SettingsRepository.keyLibraryPath);
      if (libraryPath == null || libraryPath.isEmpty) {
        debugPrint('Library path is null or empty');
        _booksData = {};
        return;
      }

      final csvPath =
          '$libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}אודות התוכנה${Platform.pathSeparator}SourcesBooks.csv';
      final file = File(csvPath);

      debugPrint('Looking for CSV file at: $csvPath');
      if (!await file.exists()) {
        debugPrint('SourcesBooks.csv file does not exist');
        _booksData = {};
        return;
      }

      final csvContent = await file.readAsString(encoding: utf8);
      final rows = const CsvToListConverter().convert(csvContent);

      if (rows.isEmpty) {
        debugPrint('SourcesBooks.csv file is empty');
        _booksData = {};
        return;
      }

      // המרת הנתונים למפה לחיפוש מהיר
      final Map<String, Map<String, String>> booksMap = {};

      for (final row in rows.skip(1)) {
        // דילוג על שורת הכותרת
        if (row.isNotEmpty && row.length >= 3) {
          final fileNameRaw = row[0].toString();
          final fileName = fileNameRaw.replaceAll('.txt', '');

          // שמירה גם עם השם עם .txt וגם בלי
          final bookData = {
            'שם הקובץ': fileNameRaw,
            'נתיב הקובץ': row[1].toString(),
            'תיקיית המקור': row[2].toString(),
          };

          booksMap[fileName] = bookData;
          booksMap[fileNameRaw] = bookData;
        }
      }

      _booksData = booksMap;
      debugPrint(
          'Successfully loaded ${booksMap.length ~/ 2} books from SourcesBooks.csv');
    } catch (e) {
      debugPrint('Error loading SourcesBooks.csv: $e');
      _booksData = {};
    }
  }

  /// קבלת פרטי ספר לפי שם
  Map<String, String> getBookDetails(String bookTitle) {
    if (_booksData == null) {
      debugPrint('SourcesBooks data not loaded yet');
      return _getDefaultBookDetails();
    }

    final bookData = _booksData![bookTitle];
    if (bookData != null) {
      return bookData;
    }

    debugPrint('Book not found in SourcesBooks: "$bookTitle"');
    return _getDefaultBookDetails();
  }

  /// נתוני ברירת מחדל כשהספר לא נמצא
  Map<String, String> _getDefaultBookDetails() {
    return {
      'שם הקובץ': 'לא ניתן למצוא את הספר',
      'נתיב הקובץ': 'לא ניתן למצוא את הספר',
      'תיקיית המקור': 'לא ניתן למצוא את הספר',
    };
  }

  /// איפוס הנתונים (לשימוש בעת שינוי נתיב ספרייה)
  void clearData() {
    _booksData = null;
  }
}
