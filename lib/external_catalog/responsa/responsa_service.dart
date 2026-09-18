import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/external_catalog/responsa/responsa_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// נקודת הכניסה היחידה לפרויקט השו"ת מתוך שאר האפליקציה.
///
/// **שום דבר כאן אינו רץ בעליית אוצריא.** הקטלוג נקרא בפעם הראשונה
/// שמחפשים, והתוכנה עולה רק כשמבקשים לפתוח ספר וההגדרה מתירה זאת.
class ResponsaService {
  ResponsaService._();

  static final ResponsaService instance = ResponsaService._();

  final ResponsaCatalogRepository catalog = ResponsaCatalogRepository.instance;

  late final ResponsaController controller = ResponsaController(
    autoStart: allowAutoStart(),
  );

  late final ResponsaLibraryProvider provider = ResponsaLibraryProvider(
    catalog: catalog,
    controller: controller,
  );

  /// האם המשתמש התיר להעלות מופע של בר אילן כשאינו רץ.
  ///
  /// **אותה הגדרה שמפעילה את החיפוש.** ספר שנמצא בחיפוש ואי אפשר
  /// לפתוח אותו הוא תוצאה חסרת ערך, ולכן אין כאן מתג שני.
  ///
  /// נקרא ישירות מהאחסון ולא דרך ה-BLoC: הקריאה מגיעה משכבת הספקים,
  /// שאין לה `BuildContext`.
  static bool allowAutoStart() {
    if (!Settings.isInitialized) return false;
    return SettingsRepository.decodeEnabledExternalProviders(
      Settings.getValue<String>(
        SettingsRepository.keyEnabledExternalProviders,
      ),
    ).contains(ExternalProviderRegistry.responsa.id);
  }

  /// פותח ספר בתוכנה. מחזיר `null` בהצלחה, או הודעת שגיאה למשתמש.
  ///
  /// אין כאן חריגים: תוכנה שאינה מותקנת, הפניה שלא נותחה או מופע שנפל
  /// מגיעים כטקסט, ואינם מפילים את אוצריא.
  Future<String?> openBook(ExternalLibraryBook book, {int? siman}) async {
    final result = await provider.open(book, siman: siman);
    return result.ok ? null : (result.message ?? 'פתיחת הספר נכשלה');
  }

  /// מבטל פתיחה שרצה כרגע.
  void cancelOpen() => provider.cancel();
}
