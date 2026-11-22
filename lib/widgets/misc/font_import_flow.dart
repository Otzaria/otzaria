import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:otzaria/utils/file/system_font_locator.dart';
import 'package:otzaria/utils/file/user_font_importer.dart';

/// בוחר קובץ גופן מהמשתמש. ממשק, כדי שבדיקות יחליפו אותו ב-fake בלי בורר
/// המערכת.
abstract interface class FontFilePicker {
  /// נתיב הקובץ שנבחר, או null כשהמשתמש ביטל.
  Future<String?> pickFontFile(BuildContext context);
}

/// בורר הקבצים של המערכת (ב-iOS: `UIDocumentPicker` דרך `file_picker`, שמעתיק
/// את הקובץ שנבחר לתיקייה זמנית של האפליקציה).
class SystemFontFilePicker implements FontFilePicker {
  const SystemFontFilePicker();

  @override
  Future<String?> pickFontFile(BuildContext context) async {
    // בורר המערכת ב-iOS אינו מכיר את כל סיומות הגופן (ttc, otc), ולכן ללא
    // סינון; הקובץ מאומת לפי סיומתו ותוכנו ב-[UserFontImporter].
    final file = await withFilePickerOwner(
      context,
      (picker) => picker.pickFile(
        type: FileType.any,
        windowsOptions: modalWindowsOptions(context),
        linuxOptions: kModalLinuxOptions,
      ),
    );
    return file?.path;
  }
}

/// זרימת "הוסף גופן מקובץ": בחירה, אימות והעתקה לתיקיית האפליקציה, ורענון
/// רשימת הגופנים. הרכיבים ניתנים להחלפה לבדיקות.
class FontImportFlow {
  FontImportFlow._();

  static FontFilePicker picker = const SystemFontFilePicker();

  /// null כשאין תיקיית גופנים למשתמש בפלטפורמה הנוכחית.
  static UserFontImporter? Function() importerFactory = _defaultImporter;

  static UserFontImporter? _defaultImporter() {
    final directory = SystemFontLocator.userFontsDirectory;
    if (directory == null) return null;
    return UserFontImporter(
      directory: directory,
      inspect: AppFonts.hebrewFamiliesInFile,
      onChanged: AppFonts.refreshSystemFonts,
    );
  }

  /// null כשהמשתמש ביטל את הבחירה.
  static Future<UserFontImportResult?> run(BuildContext context) async {
    final importer = importerFactory();
    if (importer == null) {
      return const UserFontImportResult(UserFontImportStatus.failed);
    }
    final path = await picker.pickFontFile(context);
    if (path == null) return null;
    return importer.importFile(path);
  }

  @visibleForTesting
  static void debugReset() {
    picker = const SystemFontFilePicker();
    importerFactory = _defaultImporter;
  }
}

/// הטקסט שמוצג למשתמש על תוצאת הייבוא.
String fontImportMessage(BuildContext context, UserFontImportResult result) {
  final font = result.families.isEmpty ? '' : result.families.first;
  return switch (result.status) {
    UserFontImportStatus.imported => context.settingsText(
      'הגופן {font} נוסף לרשימה',
      args: {'font': font},
    ),
    UserFontImportStatus.alreadyImported => context.settingsText(
      'הגופן {font} כבר ברשימה',
      args: {'font': font},
    ),
    UserFontImportStatus.notAFont => context.settingsText(
      'הקובץ שנבחר אינו קובץ גופן (ttf, otf, ttc או otc)',
    ),
    UserFontImportStatus.noHebrew => context.settingsText(
      'בגופן הזה אין אותיות עבריות',
    ),
    UserFontImportStatus.tooLarge => context.settingsText(
      'קובץ הגופן גדול מדי',
    ),
    UserFontImportStatus.failed => context.settingsText(
      'לא ניתן היה להעתיק את הגופן',
    ),
  };
}
