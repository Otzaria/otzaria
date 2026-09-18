import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/external_catalog/responsa/responsa_bridge_client.dart';
import 'package:otzaria/external_catalog/responsa/responsa_bridge_launcher.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/external_catalog/responsa/responsa_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// נקודת הכניסה היחידה לפרויקט השו"ת מתוך שאר האפליקציה.
///
/// **שום דבר כאן אינו רץ בעליית אוצריא.** הקטלוג נקרא בפעם הראשונה
/// שמחפשים, והגשר עולה רק כשמבקשים לפתוח ספר וההגדרה מתירה זאת.
class ResponsaService {
  ResponsaService._();

  static final ResponsaService instance = ResponsaService._();

  final ResponsaCatalogRepository catalog = ResponsaCatalogRepository.instance;

  late final ResponsaBridgeClient bridge = ResponsaBridgeClient();

  late final ResponsaBridgeLauncher launcher = ResponsaBridgeLauncher(
    client: bridge,
  );

  late final ResponsaLibraryProvider provider = ResponsaLibraryProvider(
    catalog: catalog,
    bridge: bridge,
    launcher: launcher,
    bridgeEnabled: bridgeEnabled,
  );

  /// האם המשתמש התיר להעלות מופע של פרויקט השו"ת ברקע.
  ///
  /// נקרא ישירות מהאחסון ולא דרך ה-BLoC: הקריאה מגיעה מתוך שכבת
  /// הספקים, שאין לה `BuildContext`.
  static bool bridgeEnabled() {
    if (!Settings.isInitialized) return false;
    return Settings.getValue<bool>(
          SettingsRepository.keyEnableResponsaBridge,
          defaultValue: false,
        ) ??
        false;
  }

  /// פותח ספר בתוכנה. מחזיר `null` בהצלחה, או הודעת שגיאה למשתמש.
  ///
  /// אין כאן חריגים: קריסת הגשר, תוכנה שאינה מותקנת או הפניה שלא נותחה
  /// כולן מגיעות כטקסט, ואינן מפילות את אוצריא.
  Future<String?> openBook(ExternalLibraryBook book, {int? siman}) async {
    final result = await provider.open(book, siman: siman);
    return result.ok ? null : (result.message ?? 'פתיחת הספר נכשלה');
  }
}
