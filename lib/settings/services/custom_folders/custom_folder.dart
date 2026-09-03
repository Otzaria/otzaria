import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

/// מקור-אמת יחיד לשם ה-`source` שמזהה ספר כשייך לתיקייה מותאמת אישית.
/// מסלול ההוספה ומסלול הסנכרון/מחיקה חייבים לתייג באותו שם, אחרת ה-prune
/// והמחיקה לא מזהים את הספרים.
class CustomFolderSource {
  static const String prefix = 'Personal::';

  static String normalizePath(String folderPath) {
    final normalized = p.normalize(folderPath);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  /// שם ה-`source` שמסלול ההוספה הישן תייג בו ספרי תיקיות לפני האיחוד
  /// ל-[prefix]. נשמר רק כדי שה-prune יזהה נתונים legacy מדויקים ויסירם.
  static const String legacyExternalSourceName = 'external';

  /// שם ה-`source` לתיקייה בנתיב [folderPath].
  static String nameForFolder(String folderPath) =>
      '$prefix${normalizePath(folderPath)}';
}

/// מודל לתיקייה מותאמת אישית שהמשתמש הוסיף
class CustomFolder {
  /// נתיב התיקייה במערכת הקבצים
  final String path;

  /// האם להכניס את תוכן התיקייה ל-DB
  final bool addToDatabase;

  /// האם למזג את תוכן התיקייה לעץ הספרייה הראשי. `null` = ללכת אחרי
  /// ההגדרה הגלובלית, וזו ברירת המחדל לכל תיקייה שלא נקבעה לה חריגה.
  final bool? mergeIntoLibrary;

  /// תאריך הוספה
  final DateTime addedAt;

  const CustomFolder({
    required this.path,
    this.addToDatabase = false,
    this.mergeIntoLibrary,
    required this.addedAt,
  });

  /// האם התיקייה ממוזגת בפועל, בהינתן ההגדרה הגלובלית [globalDefault].
  bool resolveMergeIntoLibrary(bool globalDefault) =>
      mergeIntoLibrary ?? globalDefault;

  /// שם התיקייה (ללא הנתיב המלא)
  String get name => path.split(RegExp(r'[/\\]')).last;

  /// [clearMergeIntoLibrary] מחזיר את התיקייה לברירת המחדל הגלובלית —
  /// `mergeIntoLibrary: null` לבדו אינו מבחין בין "אל תשנה" ל"נקה".
  CustomFolder copyWith({
    String? path,
    bool? addToDatabase,
    bool? mergeIntoLibrary,
    bool clearMergeIntoLibrary = false,
    DateTime? addedAt,
  }) {
    return CustomFolder(
      path: path ?? this.path,
      addToDatabase: addToDatabase ?? this.addToDatabase,
      mergeIntoLibrary: clearMergeIntoLibrary
          ? null
          : (mergeIntoLibrary ?? this.mergeIntoLibrary),
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'addToDatabase': addToDatabase,
      if (mergeIntoLibrary != null) 'mergeIntoLibrary': mergeIntoLibrary,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory CustomFolder.fromJson(Map<String, dynamic> json) {
    return CustomFolder(
      path: json['path'] as String,
      addToDatabase: json['addToDatabase'] as bool? ?? false,
      mergeIntoLibrary: json['mergeIntoLibrary'] as bool?,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  /// השוואה לפי הנתיב וההגדרות שהמשתמש משנה. בלי ההגדרות, שינוי הגדרה
  /// בתיקייה לא היה נחשב שינוי ב-state של ה-bloc והממשק לא היה מתעדכן.
  /// `addedAt` מחוץ להשוואה — הוא חותמת ולא זהות.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomFolder &&
        other.path == path &&
        other.addToDatabase == addToDatabase &&
        other.mergeIntoLibrary == mergeIntoLibrary;
  }

  @override
  int get hashCode => Object.hash(path, addToDatabase, mergeIntoLibrary);
}

/// מנהל תיקיות מותאמות אישית
class CustomFoldersManager {
  /// טעינת רשימת התיקיות מההגדרות
  static List<CustomFolder> loadFolders(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      // פרסור פר-פריט: רשומה פגומה אחת לא מאבדת את שאר תיקיות המשתמש
      final folders = <CustomFolder>[];
      for (final json in jsonList) {
        try {
          folders.add(CustomFolder.fromJson(json as Map<String, dynamic>));
        } catch (e) {
          debugPrint('[CustomFolders] skipping corrupt folder entry: $e');
        }
      }
      return folders;
    } catch (e) {
      debugPrint('[CustomFolders] folders JSON parse failed: $e');
      return [];
    }
  }

  /// האם קיימות תיקיות מותאמות אישית פעילות
  static bool hasFolders(String? jsonString) {
    return loadFolders(jsonString).isNotEmpty;
  }

  /// שמירת רשימת התיקיות להגדרות
  static String saveFolders(List<CustomFolder> folders) {
    return jsonEncode(folders.map((f) => f.toJson()).toList());
  }

  /// הוספת תיקייה חדשה
  static List<CustomFolder> addFolder(List<CustomFolder> folders, String path) {
    if (folders.any((f) => f.path == path)) {
      return folders; // התיקייה כבר קיימת
    }
    return [
      ...folders,
      CustomFolder(path: path, addedAt: DateTime.now()),
    ];
  }

  /// הסרת תיקייה
  static List<CustomFolder> removeFolder(
    List<CustomFolder> folders,
    String path,
  ) {
    return folders.where((f) => f.path != path).toList();
  }

  /// קביעת חריגת המיזוג לכל התיקיות שחולקות קטגוריית-שורש.
  static List<CustomFolder> updateFolderMergeSetting(
    List<CustomFolder> folders,
    String path,
    bool? mergeIntoLibrary,
  ) {
    final folderName = folders
        .where((folder) => folder.path == path)
        .firstOrNull
        ?.name;
    if (folderName == null) return folders;

    return folders.map((f) {
      if (f.name != folderName) return f;
      return f.copyWith(
        mergeIntoLibrary: mergeIntoLibrary,
        clearMergeIntoLibrary: mergeIntoLibrary == null,
      );
    }).toList();
  }

  /// עדכון הגדרת addToDatabase לתיקייה
  static List<CustomFolder> updateFolderDbSetting(
    List<CustomFolder> folders,
    String path,
    bool addToDatabase,
  ) {
    return folders.map((f) {
      if (f.path == path) {
        return f.copyWith(addToDatabase: addToDatabase);
      }
      return f;
    }).toList();
  }
}
