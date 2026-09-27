import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/external_catalog/responsa/responsa_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// נקודת הכניסה לפרויקט השו"ת. שום דבר כאן אינו רץ בעליית אוצריא -
/// הקטלוג נקרא בחיפוש הראשון, והתוכנה עולה רק בפתיחת ספר.
class ResponsaService {
  ResponsaService._();

  static final ResponsaService instance = ResponsaService._();

  final ResponsaCatalogRepository catalog = ResponsaCatalogRepository.instance;

  late final ResponsaController controller = ResponsaController(
    allowAutoStart: allowAutoStart,
  );

  late final ResponsaLibraryProvider provider = ResponsaLibraryProvider(
    catalog: catalog,
    controller: controller,
  );

  /// אותה הגדרה שמפעילה את החיפוש - ספר שנמצא ואי אפשר לפתוח חסר ערך.
  /// נקרא מהאחסון ולא מה-BLoC, כי לשכבת הספקים אין `BuildContext`.
  static bool allowAutoStart() {
    if (!Settings.isInitialized) return false;
    return SettingsRepository.decodeEnabledExternalProviders(
      Settings.getValue<String>(
        SettingsRepository.keyEnabledExternalProviders,
      ),
    ).contains(ExternalProviderRegistry.responsa.id);
  }

  /// מחזיר `null` בהצלחה, או הודעת שגיאה למשתמש - לעולם לא חריג.
  Future<String?> openBook(ExternalLibraryBook book) async {
    final result = await provider.open(book);
    return result.ok ? null : (result.message ?? 'פתיחת הספר נכשלה');
  }
}
