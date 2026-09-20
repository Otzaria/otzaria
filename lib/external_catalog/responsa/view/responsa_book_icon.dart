import 'dart:typed_data';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/external_catalog/responsa/responsa_icon.dart';
import 'package:otzaria/external_catalog/responsa/responsa_paths.dart';

/// האייקון של בר אילן, כפי שהוא בהתקנה של המשתמש.
///
/// הבייטים נטענים פעם אחת לכל ריצת אפליקציה ונשמרים ב-[future]: כל
/// כרטיס ספר בתוצאות מבקש את אותו אייקון, וקריאה מחדש לכל אחד מהם
/// הייתה קוראת את קובץ ההרצה שוב ושוב.
///
/// כשאין התקנה, אין הרשאת קריאה, או שקובץ ההרצה אינו מכיל אייקון —
/// מוצג [fallback]. אייקון חסר הוא עניין קוסמטי ואסור שיפיל מסך.
class ResponsaBookIcon extends StatefulWidget {
  final double size;
  final Color? color;

  const ResponsaBookIcon({super.key, required this.size, this.color});

  /// אייקון מובנה מובחן, למקרה שאי אפשר לחלץ את האמיתי.
  static const IconData fallback = FluentIcons.library_24_filled;

  static Future<Uint8List?>? _future;

  /// כמה להמתין לפני שניסיון שנכשל מותר שוב.
  static const Duration _retryAfter = Duration(seconds: 30);

  /// מנקה את המטמון. לבדיקות בלבד.
  @visibleForTesting
  static void resetCache() => _future = null;

  /// עוקף את הטעינה בבדיקות.
  @visibleForTesting
  static set debugFuture(Future<Uint8List?>? value) => _future = value;

  static Future<Uint8List?> _load() async {
    final installPath = await ResponsaCatalogRepository.instance
        .sourceInstallPath();
    final bytes = await ResponsaIcon.load(
      installPath: installPath,
      cacheDirectory: ResponsaPaths.baseDirectory,
    );
    // כישלון אינו נשמר במטמון לנצח. בהדלקה הראשונה הקטלוג עדיין לא
    // נבנה, ולכן אין נתיב התקנה; אילו ה-`null` היה נשמר, האייקון היה
    // חסר עד להפעלה מחדש של אוצריא.
    //
    // אבל גם לא מנוקה מיד: כל כרטיס ספר בונה את הווידג'ט הזה, וניקוי
    // מיידי הפך רשימה של 60 ספרים ל-60 ניסיונות טעינה — כל אחד עם
    // פתיחת SQLite וקריאת 4.5MB. ההשהיה נותנת לבנייה של הקטלוג להסתיים
    // ולניסיון הבא להצליח, בלי סערת ניסיונות בדרך.
    if (bytes == null) {
      final failed = _future;
      Future<void>.delayed(_retryAfter, () {
        if (identical(_future, failed)) _future = null;
      });
    }
    return bytes;
  }

  @override
  State<ResponsaBookIcon> createState() => _ResponsaBookIconState();
}

class _ResponsaBookIconState extends State<ResponsaBookIcon> {
  late final Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = ResponsaBookIcon._future ??= ResponsaBookIcon._load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return Icon(
            ResponsaBookIcon.fallback,
            size: widget.size,
            color: widget.color,
          );
        }
        return Image.memory(
          bytes,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          // האייקון שבקובץ ההרצה הוא 32x32. בכרטיס גדול הוא נמתח, וזה
          // עדיין עדיף על אייקון גנרי שאינו אומר מאיפה הספר.
          errorBuilder: (context, error, stack) => Icon(
            ResponsaBookIcon.fallback,
            size: widget.size,
            color: widget.color,
          ),
        );
      },
    );
  }
}
