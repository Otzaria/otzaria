import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';

/// מחלקה לניהול הגדרות פר-ספר
class PerBookSettings {
  /// קבלת נתיב תיקיית ההגדרות
  /// נשמרת תחת שורש הנתונים האחיד של האפליקציה.
  static Future<Directory> _getSettingsDirectory() async {
    final settingsDir = Directory(await AppPaths.getPerBookSettingsPath());
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
  final bool? removePunctuation;
  final bool? continuousReadingMode;
  final bool? showSubtitles;

  TextBookPerBookSettings({
    this.fontSize,
    this.commentatorsBelow,
    this.removeNikud,
    this.removePunctuation,
    this.continuousReadingMode,
    this.showSubtitles,
  });

  Map<String, dynamic> toJson() => {
        if (fontSize != null) 'fontSize': fontSize,
        if (commentatorsBelow != null) 'commentatorsBelow': commentatorsBelow,
        if (removeNikud != null) 'removeNikud': removeNikud,
        if (removePunctuation != null) 'removePunctuation': removePunctuation,
        if (continuousReadingMode != null)
          'continuousReadingMode': continuousReadingMode,
        if (showSubtitles != null) 'showSubtitles': showSubtitles,
      };

  factory TextBookPerBookSettings.fromJson(Map<String, dynamic> json) {
    return TextBookPerBookSettings(
      fontSize: json['fontSize'] as double?,
      commentatorsBelow: json['commentatorsBelow'] as bool?,
      removeNikud: json['removeNikud'] as bool?,
      removePunctuation: json['removePunctuation'] as bool?,
      continuousReadingMode: json['continuousReadingMode'] as bool?,
      showSubtitles: json['showSubtitles'] as bool?,
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

/// מצב תצוגת PDF
enum PdfLayoutMode {
  regularView, // תצוגה רגילה
  bookView, // תצוגת ספר
}

/// הגדרות פר-ספר לספרי PDF
class PdfBookPerBookSettings {
  static final Map<String, Future<void>> _pendingWrites = {};

  final double? zoom;
  final List<String>? activeCommentators;
  final PdfLayoutMode? layoutMode;

  PdfBookPerBookSettings({
    this.zoom,
    this.activeCommentators,
    this.layoutMode,
  });

  PdfBookPerBookSettings copyWith({
    double? zoom,
    List<String>? activeCommentators,
    PdfLayoutMode? layoutMode,
  }) {
    return PdfBookPerBookSettings(
      zoom: zoom ?? this.zoom,
      activeCommentators: activeCommentators ?? this.activeCommentators,
      layoutMode: layoutMode ?? this.layoutMode,
    );
  }

  Map<String, dynamic> toJson() => {
        if (zoom != null) 'zoom': zoom,
        if (activeCommentators != null)
          'activeCommentators': activeCommentators,
        if (layoutMode != null) 'layoutMode': layoutMode!.name,
      };

  factory PdfBookPerBookSettings.fromJson(Map<String, dynamic> json) {
    return PdfBookPerBookSettings(
      zoom: json['zoom'] as double?,
      activeCommentators:
          (json['activeCommentators'] as List<dynamic>?)?.cast<String>(),
      layoutMode: json['layoutMode'] != null
          ? PdfLayoutMode.values.firstWhere(
              (e) => e.name == json['layoutMode'],
              orElse: () => PdfLayoutMode.regularView,
            )
          : null,
    );
  }

  /// שמירת הגדרות
  Future<void> save(String bookName) async {
    final previousWrite = _pendingWrites[bookName] ?? Future.value();
    final currentWrite = previousWrite.then((_) async {
      final existingSettings = await PdfBookPerBookSettings.load(bookName);
      final settingsToSave = existingSettings?.copyWith(
            zoom: zoom,
            activeCommentators: activeCommentators,
            layoutMode: layoutMode,
          ) ??
          this;

      await PerBookSettings.saveSettings(bookName, settingsToSave.toJson());
    });

    _pendingWrites[bookName] = currentWrite;

    try {
      await currentWrite;
    } finally {
      if (identical(_pendingWrites[bookName], currentWrite)) {
        _pendingWrites.remove(bookName);
      }
    }
  }

  /// טעינת הגדרות
  static Future<PdfBookPerBookSettings?> load(String bookName) async {
    final json = await PerBookSettings.loadSettings(bookName);
    if (json == null) return null;
    return PdfBookPerBookSettings.fromJson(json);
  }

  /// מחיקת הגדרות
  static Future<void> delete(String bookName) async {
    final previousWrite = _pendingWrites[bookName] ?? Future.value();
    final deleteWrite = previousWrite.then((_) async {
      await PerBookSettings.deleteSettings(bookName);
    });

    _pendingWrites[bookName] = deleteWrite;

    try {
      await deleteWrite;
    } finally {
      if (identical(_pendingWrites[bookName], deleteWrite)) {
        _pendingWrites.remove(bookName);
      }
    }
  }
}
