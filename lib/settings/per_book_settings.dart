import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// מחלקה לניהול הגדרות פר-ספר
class PerBookSettings {
  static const String _settingsFolderName = 'per_book_settings';

  /// קבלת נתיב תיקיית ההגדרות
  static Future<Directory> _getSettingsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final settingsDir = Directory('${appDir.path}/$_settingsFolderName');
    if (!await settingsDir.exists()) {
      await settingsDir.create(recursive: true);
    }
    return settingsDir;
  }

  /// יצירת שם קובץ בטוח מתוך שם ספר
  static String _sanitizeBookName(String bookName) {
    // הסרת תווים לא חוקיים משם הקובץ
    return bookName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(' ', '_');
  }

  /// קבלת נתיב קובץ הגדרות לספר
  static Future<File> _getSettingsFile(String bookName) async {
    final dir = await _getSettingsDirectory();
    final sanitizedName = _sanitizeBookName(bookName);
    return File('${dir.path}/settings_$sanitizedName.json');
  }

  /// שמירת הגדרות לספר
  static Future<void> saveSettings(
    String bookName,
    Map<String, dynamic> settings,
  ) async {
    try {
      final file = await _getSettingsFile(bookName);
      final json = jsonEncode(settings);
      await file.writeAsString(json);
    } catch (e) {
      debugPrint('❌ Error saving per-book settings: $e');
      rethrow;
    }
  }

  /// טעינת הגדרות של ספר
  static Future<Map<String, dynamic>?> loadSettings(String bookName) async {
    try {
      final file = await _getSettingsFile(bookName);
      if (!await file.exists()) {
        return null;
      }
      final json = await file.readAsString();
      final settings = jsonDecode(json) as Map<String, dynamic>;
      return settings;
    } catch (e) {
      debugPrint('❌ Error loading per-book settings: $e');
      return null;
    }
  }

  /// מחיקת הגדרות של ספר
  static Future<void> deleteSettings(String bookName) async {
    try {
      final file = await _getSettingsFile(bookName);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('❌ Error deleting per-book settings: $e');
    }
  }

  /// מחיקת כל קבצי ההגדרות
  static Future<void> deleteAllSettings() async {
    try {
      final dir = await _getSettingsDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('❌ Error deleting all per-book settings: $e');
    }
  }

  /// קבלת רשימת כל הספרים עם הגדרות
  static Future<List<String>> getAllBooksWithSettings() async {
    try {
      final dir = await _getSettingsDirectory();
      if (!await dir.exists()) {
        return [];
      }
      final files = await dir.list().toList();
      return files
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) {
        final name = f.path.split(Platform.pathSeparator).last;
        return name
            .replaceFirst('settings_', '')
            .replaceFirst('.json', '')
            .replaceAll('_', ' ');
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error getting books with settings: $e');
      }
      return [];
    }
  }

  /// ניקוי קבצי הגדרות שהפכו למיותרים (זהים לברירת המחדל)
  static Future<void> cleanupRedundantSettings({
    required double defaultFontSize,
    required bool defaultRemoveNikud,
    required bool defaultShowSplitView,
  }) async {
    try {
      final dir = await _getSettingsDirectory();
      if (!await dir.exists()) {
        return;
      }

      final files = (await dir.list().toList()).whereType<File>();

      for (final file in files) {
        if (!file.path.endsWith('.json')) continue;

        try {
          final json =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;

          // בדיקה אם כל ההגדרות זהות לברירת המחדל
          final fontSize = json['fontSize'] as double?;
          final commentatorsBelow = json['commentatorsBelow'] as bool?;
          final removeNikud = json['removeNikud'] as bool?;

          bool isRedundant = true;

          if (fontSize != null && fontSize != defaultFontSize) {
            isRedundant = false;
          }
          if (removeNikud != null && removeNikud != defaultRemoveNikud) {
            isRedundant = false;
          }
          if (commentatorsBelow != null &&
              commentatorsBelow != !defaultShowSplitView) {
            isRedundant = false;
          }

          if (isRedundant) {
            await file.delete();
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ Error processing file ${file.path}: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error cleaning redundant settings: $e');
      }
    }
  }
}

/// הגדרות פר-ספר לספרי טקסט
class TextBookPerBookSettings {
  final double? fontSize;
  final bool? commentatorsBelow; // true = מתחת, false = בצד
  final bool? removeNikud;

  TextBookPerBookSettings({
    this.fontSize,
    this.commentatorsBelow,
    this.removeNikud,
  });

  Map<String, dynamic> toJson() => {
        if (fontSize != null) 'fontSize': fontSize,
        if (commentatorsBelow != null) 'commentatorsBelow': commentatorsBelow,
        if (removeNikud != null) 'removeNikud': removeNikud,
      };

  factory TextBookPerBookSettings.fromJson(Map<String, dynamic> json) {
    return TextBookPerBookSettings(
      fontSize: json['fontSize'] as double?,
      commentatorsBelow: json['commentatorsBelow'] as bool?,
      removeNikud: json['removeNikud'] as bool?,
    );
  }

  /// שמירת הגדרות
  Future<void> save(String bookName) async {
    await PerBookSettings.saveSettings(bookName, toJson());
  }

  /// טעינת הגדרות
  static Future<TextBookPerBookSettings?> load(String bookName) async {
    final json = await PerBookSettings.loadSettings(bookName);
    if (json == null) return null;
    return TextBookPerBookSettings.fromJson(json);
  }

  /// מחיקת הגדרות
  static Future<void> delete(String bookName) async {
    await PerBookSettings.deleteSettings(bookName);
  }
}

/// הגדרות פר-ספר לספרי PDF
class PdfBookPerBookSettings {
  final double? zoom;

  PdfBookPerBookSettings({
    this.zoom,
  });

  Map<String, dynamic> toJson() => {
        if (zoom != null) 'zoom': zoom,
      };

  factory PdfBookPerBookSettings.fromJson(Map<String, dynamic> json) {
    return PdfBookPerBookSettings(
      zoom: json['zoom'] as double?,
    );
  }

  /// שמירת הגדרות
  Future<void> save(String bookName) async {
    await PerBookSettings.saveSettings(bookName, toJson());
  }

  /// טעינת הגדרות
  static Future<PdfBookPerBookSettings?> load(String bookName) async {
    final json = await PerBookSettings.loadSettings(bookName);
    if (json == null) return null;
    return PdfBookPerBookSettings.fromJson(json);
  }

  /// מחיקת הגדרות
  static Future<void> delete(String bookName) async {
    await PerBookSettings.deleteSettings(bookName);
  }
}
