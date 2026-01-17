import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// מחלקה לניהול הגדרות פר-ספר
class PerBookSettings {
  static const String _settingsFolderName = 'per_book_settings';
  static bool _migrationAttempted = false;

  /// קבלת נתיב תיקיית ההגדרות
  /// נשמר בתיקיית ה־Application Support (זהה לשאר הגדרות האפליקציה)
  static Future<Directory> _getSettingsDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final settingsDir = Directory('${appDir.path}/$_settingsFolderName');
    if (!await settingsDir.exists()) {
      await settingsDir.create(recursive: true);
    }
    // מיגרציה לאחור: העברת הגדרות שנשמרו בעבר בתיקיית Documents
    if (!_migrationAttempted) {
      _migrationAttempted = true;
      await _migrateFromDocuments(settingsDir);
    }
    return settingsDir;
  }

  /// העברת קבצי הגדרות מתיקיית Documents לתיקיית Application Support
  static Future<void> _migrateFromDocuments(Directory newDir) async {
    try {
      final oldAppDir = await getApplicationDocumentsDirectory();
      final oldDir = Directory('${oldAppDir.path}/$_settingsFolderName');
      if (!await oldDir.exists()) return;

        final files = await oldDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
        for (final file in files) {
        if (!file.path.endsWith('.json')) continue;

        final fileName = file.path.split(Platform.pathSeparator).last;
        final destPath = '${newDir.path}/$fileName';
        final destFile = File(destPath);

        if (await destFile.exists()) {
          continue;
        }

        try {
          await file.rename(destPath);
        } catch (_) {
          // אם rename נכשל (למשל בין כוננים), נעתיק ואז נמחק
          await file.copy(destPath);
          await file.delete();
        }
      }

      // אם לא נשארו קבצי JSON - נמחק את התיקייה הישנה
        final hasJson = await oldDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .any((f) => f.path.endsWith('.json'));
      if (!hasJson) {
        await oldDir.delete(recursive: true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error migrating per-book settings: $e');
      }
    }
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
      debugPrint('📁 Saving to file: ${file.path}');
      final json = jsonEncode(settings);
      debugPrint('📄 JSON content: $json');
      await file.writeAsString(json);
      debugPrint('✅ Saved per-book settings for: $bookName');
    } catch (e) {
      debugPrint('❌ Error saving per-book settings: $e');
      rethrow;
    }
  }

  /// טעינת הגדרות של ספר
  static Future<Map<String, dynamic>?> loadSettings(String bookName) async {
    try {
      final file = await _getSettingsFile(bookName);
      debugPrint('📁 Looking for file: ${file.path}');
      if (!await file.exists()) {
        debugPrint('📁 File does not exist');
        return null;
      }
      final json = await file.readAsString();
      debugPrint('📄 JSON content: $json');
      final settings = jsonDecode(json) as Map<String, dynamic>;
      debugPrint('✅ Loaded per-book settings for: $bookName');
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
        debugPrint('✅ Deleted per-book settings for: $bookName');
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
        debugPrint('✅ Deleted all per-book settings');
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
      debugPrint('❌ Error getting books with settings: $e');
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
      int cleanedCount = 0;

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
            cleanedCount++;
            debugPrint('🧹 Cleaned redundant settings file: ${file.path}');
          }
        } catch (e) {
          debugPrint('❌ Error processing file ${file.path}: $e');
        }
      }

      if (cleanedCount > 0) {
        debugPrint('🧹 Cleaned $cleanedCount redundant settings files');
      }
    } catch (e) {
      debugPrint('❌ Error cleaning redundant settings: $e');
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
