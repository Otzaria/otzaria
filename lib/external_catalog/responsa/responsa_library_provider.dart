import 'package:otzaria/external_catalog/providers/external_library_provider.dart';
import 'package:otzaria/external_catalog/providers/external_provider_capabilities.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/responsa_bridge_client.dart';
import 'package:otzaria/external_catalog/responsa/responsa_bridge_launcher.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/models/books.dart';

/// ספק פרויקט השו"ת.
///
/// שתי שכבות נפרדות, ובכוונה:
///
/// * **קטלוג** — SQLite מקומי שנבנה מההתקנה של המשתמש. עצם קיום הרשומה
///   בקטלוג אומר שהספר קיים בגרסה שממנה הקטלוג נבנה; אין לבדוק קובץ,
///   כי כל הספרים יושבים בארכיון אחד ואין התקנה חלקית ברמת ספר.
/// * **גשר** — נדרש רק לפתיחה. הקטלוג עובד בלעדיו.
class ResponsaLibraryProvider implements ExternalLibraryProvider {
  final ResponsaCatalogRepository catalog;
  final ResponsaBridgeClient bridge;
  final ResponsaBridgeLauncher launcher;

  /// האם ההגדרה מתירה להעלות את הגשר בעת הצורך.
  final bool Function() bridgeEnabled;

  ResponsaLibraryProvider({
    required this.catalog,
    required this.bridge,
    required this.launcher,
    required this.bridgeEnabled,
  });

  @override
  ExternalProviderDescriptor get descriptor =>
      ExternalProviderRegistry.responsa;

  @override
  String get id => descriptor.id;

  @override
  String get displayName => descriptor.displayName;

  @override
  String get idPrefix => descriptor.idPrefix;

  @override
  String? get iconAsset => descriptor.iconAsset;

  @override
  ExternalProviderCapabilities get capabilities => descriptor.capabilities;

  @override
  Future<List<Book>> loadBooks() => catalog.loadBooks();

  /// טעינת ספרים לפי מזהים חיצוניים (`rp:1524`) — המסלול שתוספים
  /// משתמשים בו. אין בדיקת קובץ: קיום ברשומה **הוא** הזמינות.
  Future<List<Book>> loadBooksByIds(Iterable<String> externalLibraryIds) {
    final keys = <String>[];
    for (final value in externalLibraryIds) {
      final parsed = ExternalProviderRegistry.parse(value);
      if (parsed?.provider.kind == ExternalProviderKind.responsa) {
        keys.add(parsed!.value);
      } else {
        // מזהה בלי תחילית מתקבל כמפתח גולמי, לנוחות קוראים פנימיים.
        final raw = value.trim();
        if (raw.isNotEmpty && !raw.contains(':')) keys.add(raw);
      }
    }
    return catalog.loadBooksByKeys(keys);
  }

  @override
  Future<bool> canOpen(Book book) async {
    final key = _keyOf(book);
    if (key == null) return false;
    return (await catalog.openRefFor(key)) != null;
  }

  @override
  Future<ExternalOpenResult> openBook(Book book) => open(book);

  /// פותח את הספר בתוכנה, ואם נמסר [siman] — מנווט אליו אחרי הפתיחה.
  Future<ExternalOpenResult> open(
    Book book, {
    int? siman,
    String? requestId,
  }) async {
    final key = _keyOf(book);
    if (key == null) {
      return const ExternalOpenResult.failure(
        'notAResponsaBook',
        'הספר אינו ספר של פרויקט השו"ת',
      );
    }

    final openRef = await catalog.openRefFor(key);
    if (openRef == null) {
      return const ExternalOpenResult.failure(
        'notInCatalog',
        'הספר אינו נמצא בקטלוג פרויקט השו"ת. ייתכן שיש לבנות את הקטלוג מחדש.',
      );
    }

    final launchError = await launcher.ensureRunning(
      allowStart: bridgeEnabled(),
    );
    if (launchError != null) {
      return ExternalOpenResult.failure(
        launchError,
        _launchMessage(launchError),
      );
    }

    final result = siman == null
        ? await bridge.openBook(
            openRef,
            expectedTitle: book.title,
            requestId: requestId,
          )
        : await bridge.openBookAtSiman(
            openRef,
            siman,
            expectedTitle: book.title,
            requestId: requestId,
          );

    if (result.ok) return const ExternalOpenResult.success();
    return ExternalOpenResult.failure(
      result.errorCode ?? 'openFailed',
      result.message ?? _openMessage(result.errorCode),
    );
  }

  /// ביטול פעולה ארוכה. הביטול אמיתי — הגשר עוצר את הפעולה עצמה.
  Future<void> cancel(String requestId) => bridge.cancel(requestId);

  static String? _keyOf(Book book) {
    final parsed = ExternalProviderRegistry.parse(book.externalLibraryId);
    if (parsed?.provider.kind != ExternalProviderKind.responsa) return null;
    return parsed!.value;
  }

  static String _launchMessage(String code) => switch (code) {
    'bridgeDisabled' => 'הפעלת פרויקט השו"ת מתוך אוצריא כבויה בהגדרות.',
    'bridgeNotInstalled' => 'רכיב החיבור לפרויקט השו"ת אינו מותקן.',
    'bridgeLaunchFailed' => 'לא ניתן להפעיל את רכיב החיבור לפרויקט השו"ת.',
    'bridgeNotReady' => 'רכיב החיבור לפרויקט השו"ת לא הגיב בזמן.',
    _ => 'לא ניתן להתחבר לפרויקט השו"ת.',
  };

  static String _openMessage(String? code) => switch (code) {
    'referenceNotParsed' => 'פרויקט השו"ת לא זיהה את ההפניה לספר הזה.',
    'openedWrongBook' => 'פרויקט השו"ת פתח ספר אחר — הפתיחה בוטלה.',
    'responsaNotRunning' => 'פרויקט השו"ת אינו פעיל.',
    'unsupportedResponsaVersion' => 'הגרסה המותקנת של פרויקט השו"ת אינה נתמכת.',
    'timeout' => 'פרויקט השו"ת לא הגיב בזמן.',
    'cancelled' => 'הפתיחה בוטלה.',
    _ => 'פתיחת הספר בפרויקט השו"ת נכשלה.',
  };
}
