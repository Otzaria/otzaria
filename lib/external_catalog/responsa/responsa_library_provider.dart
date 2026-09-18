import 'package:otzaria/external_catalog/providers/external_library_provider.dart';
import 'package:otzaria/external_catalog/providers/external_provider_capabilities.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/models/books.dart';

/// ספק פרויקט השו"ת.
///
/// שתי שכבות נפרדות, ובכוונה:
///
/// * **קטלוג** — SQLite מקומי שנבנה מההתקנה של המשתמש. עצם קיום הרשומה
///   בקטלוג אומר שהספר קיים במהדורה שממנה הקטלוג נבנה; אין לבדוק קובץ,
///   כי כל הספרים יושבים בארכיון אחד ואין התקנה חלקית ברמת ספר.
/// * **שליטה בתוכנה** — נדרשת רק לפתיחה, ורצה באיזולט רקע בתוך אוצריא.
///   אין רכיב חיצוני להתקין ואין מה להגדיר בפרויקט השו"ת.
class ResponsaLibraryProvider implements ExternalLibraryProvider {
  final ResponsaCatalogRepository catalog;
  final ResponsaController controller;

  ResponsaLibraryProvider({required this.catalog, required this.controller});

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
  Future<ExternalOpenResult> open(Book book, {int? siman}) async {
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

    final report = await controller.openBook(
      openRef,
      expectedTitle: book.title,
      siman: siman,
    );
    if (report.ok) return const ExternalOpenResult.success();
    return ExternalOpenResult.failure(
      report.failure?.name ?? 'openFailed',
      report.message ?? messageFor(report.failure),
    );
  }

  /// ביטול פעולה ארוכה. הביטול אמיתי — הפעולה עצמה נעצרת.
  void cancel() => controller.cancel();

  static String? _keyOf(Book book) {
    final parsed = ExternalProviderRegistry.parse(book.externalLibraryId);
    if (parsed?.provider.kind != ExternalProviderKind.responsa) return null;
    return parsed!.value;
  }

  static String messageFor(ResponsaFailure? failure) => switch (failure) {
    ResponsaFailure.responsaNotRunning => 'פרויקט השו"ת אינו פעיל.',
    ResponsaFailure.citationDialogNotFound =>
      'לא ניתן לפתוח את חלון המקורות בפרויקט השו"ת.',
    ResponsaFailure.referenceNotParsed =>
      'פרויקט השו"ת לא זיהה את ההפניה לספר הזה.',
    ResponsaFailure.openedWrongBook =>
      'פרויקט השו"ת פתח ספר אחר — הפתיחה בוטלה.',
    ResponsaFailure.mdiWindowLimitReached =>
      'פרויקט השו"ת אינו פותח חלונות נוספים. יש לסגור בו כמה חלונות.',
    ResponsaFailure.resultsNotCleared =>
      'פרויקט השו"ת אינו מגיב כצפוי. נסה שוב.',
    ResponsaFailure.timeout => 'פרויקט השו"ת לא הגיב בזמן.',
    ResponsaFailure.cancelled => 'הפתיחה בוטלה.',
    null => 'פתיחת הספר בפרויקט השו"ת נכשלה.',
  };
}
