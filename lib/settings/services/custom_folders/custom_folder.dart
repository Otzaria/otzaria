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

  /// תאריך הוספה
  final DateTime addedAt;

  const CustomFolder({
    required this.path,
    this.addToDatabase = false,
    required this.addedAt,
  });

  /// שם התיקייה (ללא הנתיב המלא)
  String get name => path.split(RegExp(r'[/\\]')).last;

  CustomFolder copyWith({
    String? path,
    bool? addToDatabase,
    DateTime? addedAt,
  }) {
    return CustomFolder(
      path: path ?? this.path,
      addToDatabase: addToDatabase ?? this.addToDatabase,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'addToDatabase': addToDatabase,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory CustomFolder.fromJson(Map<String, dynamic> json) {
    return CustomFolder(
      path: json['path'] as String,
      addToDatabase: json['addToDatabase'] as bool? ?? false,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomFolder && other.path == path;
  }

  @override
  int get hashCode => path.hashCode;
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
