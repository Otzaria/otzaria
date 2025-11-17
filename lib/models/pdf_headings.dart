import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// מודל לניהול קבצי headings של PDF
/// מקשר בין כותרות ב-PDF למספרי שורות בקובץ הטקסט
class PdfHeadings {
  final Map<String, int> headingsMap;
  final String bookTitle;

  PdfHeadings({
    required this.headingsMap,
    required this.bookTitle,
  });

  /// טוען קובץ headings JSON עבור ספר מסוים
  static Future<PdfHeadings?> loadFromFile(String bookTitle) async {
    try {
      // קבלת נתיב הספרייה
      final libraryPath = Settings.getValue<String>('key-library-path');
      if (libraryPath == null || libraryPath.isEmpty) {
        debugPrint('Library path not set');
        return null;
      }

      // נתיב לקובץ ה-JSON בתיקיית links
      final fileName = '${bookTitle}_headings.json';
      final filePath = '$libraryPath${Platform.pathSeparator}links${Platform.pathSeparator}$fileName';
      
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('Headings file not found: $filePath');
        return null;
      }

      final jsonString = await file.readAsString();
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      
      // המרה ל-Map<String, int>
      final Map<String, int> headingsMap = {};
      jsonData.forEach((key, value) {
        if (value is int) {
          headingsMap[key] = value;
        } else if (value is String) {
          headingsMap[key] = int.tryParse(value) ?? 0;
        }
      });

      return PdfHeadings(
        headingsMap: headingsMap,
        bookTitle: bookTitle,
      );
    } catch (e) {
      debugPrint('Error loading headings file for $bookTitle: $e');
      return null;
    }
  }

  /// מחזיר את מספר השורה בטקסט עבור כותרת מסוימת
  int? getLineNumberForHeading(String heading) {
    return headingsMap[heading];
  }

  /// מחזיר את הכותרת הקרובה ביותר למספר שורה נתון
  String? getClosestHeading(int lineNumber) {
    String? closestHeading;
    int closestDistance = double.maxFinite.toInt();

    for (final entry in headingsMap.entries) {
      final distance = (entry.value - lineNumber).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closestHeading = entry.key;
      }
    }

    return closestHeading;
  }

  /// מחזיר רשימה של כותרות ממוינות לפי מספר השורה
  List<MapEntry<String, int>> getSortedHeadings() {
    final entries = headingsMap.entries.toList();
    entries.sort((a, b) => a.value.compareTo(b.value));
    return entries;
  }
}
