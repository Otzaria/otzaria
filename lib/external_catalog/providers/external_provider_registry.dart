import 'package:otzaria/external_catalog/providers/external_provider_capabilities.dart';

/// הספקים החיצוניים שאוצריא מכירה.
enum ExternalProviderKind { otzar, hebrewBooks, responsa }

/// תיאור סטטי של ספק. אינו טוען ספרים, ולכן מזהה גם ספר של ספק שאינו מופעל.
class ExternalProviderDescriptor {
  final ExternalProviderKind kind;

  /// מזהה טקסטואלי יציב, כפי שנחשף ל-Plugin SDK.
  final String id;

  final String displayName;

  /// התחילית הקנונית של `externalLibraryId` (למשל `oh` ב-`oh:42`).
  final String idPrefix;

  /// תחיליות נוספות שנקלטות לצורך תאימות לאחור.
  final Set<String> aliasPrefixes;

  final String? iconAsset;

  /// הכיתוב על כפתור הפתיחה המקומית - עדיף שם התוכנה על "פתח בתוכנה".
  final String localOpenLabel;

  final ExternalProviderCapabilities capabilities;

  /// בונה קישור לאתר הספק, או `null` לספק ללא נוכחות ברשת.
  final String? Function(String value)? linkBuilder;

  const ExternalProviderDescriptor({
    required this.kind,
    required this.id,
    required this.displayName,
    required this.idPrefix,
    required this.capabilities,
    this.aliasPrefixes = const {},
    this.iconAsset,
    this.localOpenLabel = 'פתח בתוכנה',
    this.linkBuilder,
  });

  /// כל התחיליות שהספק עונה להן, כולל הקנונית.
  Set<String> get allPrefixes => {idPrefix, ...aliasPrefixes};

  String externalLibraryIdFor(String value) => '$idPrefix:$value';

  String? webLinkFor(String value) => linkBuilder?.call(value);
}

/// הפניה מפוענחת ל-`externalLibraryId` — ספק וערך.
class ExternalBookRef {
  final ExternalProviderDescriptor provider;

  /// הערך כפי שהופיע אחרי התחילית, בלי נרמול.
  final String value;

  const ExternalBookRef(this.provider, this.value);

  /// הערך כמספר, אם הוא מספרי. אצל אוצר החכמה והיברובוקס הוא תמיד כזה.
  int? get numericValue => int.tryParse(value);

  String get canonicalId => provider.externalLibraryIdFor(value);

  @override
  bool operator ==(Object other) =>
      other is ExternalBookRef &&
      other.provider.kind == provider.kind &&
      other.value == value;

  @override
  int get hashCode => Object.hash(provider.kind, value);

  @override
  String toString() => canonicalId;
}

/// המקום היחיד שמזהה "מאיזה ספק הספר הזה", במקום `switch` על הספקים בכל קובץ.
class ExternalProviderRegistry {
  ExternalProviderRegistry._();

  static const ExternalProviderDescriptor otzar = ExternalProviderDescriptor(
    kind: ExternalProviderKind.otzar,
    id: 'otzar',
    displayName: 'אוצר החכמה',
    idPrefix: 'oh',
    aliasPrefixes: {'otz', 'otzar'},
    iconAsset: 'assets/logos/otzar.ico',
    capabilities: ExternalProviderCapabilities(webOpen: true, localOpen: true),
    linkBuilder: _otzarLink,
  );

  static const ExternalProviderDescriptor hebrewBooks =
      ExternalProviderDescriptor(
        kind: ExternalProviderKind.hebrewBooks,
        id: 'hebrewbooks',
        displayName: 'היברובוקס',
        idPrefix: 'hb',
        aliasPrefixes: {'hebrew', 'hebrewbooks'},
        iconAsset: 'assets/logos/hebrew_books.png',
        capabilities: ExternalProviderCapabilities(
          webOpen: true,
          pdfDownload: true,
        ),
        linkBuilder: _hebrewBooksLink,
      );

  /// פרויקט השו"ת. אין `webOpen` ואין `pdfDownload` — אין לתוכנה נוכחות
  /// ברשת ואין גישה לקבצי הספרים מחוץ לתוכנה עצמה.
  static const ExternalProviderDescriptor responsa = ExternalProviderDescriptor(
    kind: ExternalProviderKind.responsa,
    id: 'responsa',
    // השם שהמשתמשים מכירים הוא "בר אילן"; "פרויקט השו"ת" לבדו אינו
    // מזוהה אצל רבים.
    displayName: 'פרויקט השו"ת בר אילן',
    idPrefix: 'rp',
    aliasPrefixes: {'responsa'},
    localOpenLabel: 'פתח בבר אילן',
    capabilities: ExternalProviderCapabilities(localOpen: true),
  );

  static const List<ExternalProviderDescriptor> all = [
    otzar,
    hebrewBooks,
    responsa,
  ];

  /// לאוצר החכמה מסלול משלו (`OtzarUtils.launchOtzarLocal`); דרך הקולבק
  /// המשותף הוא מגיע לפותחן של פרויקט השו"ת ונכשל.
  static bool usesSharedLocalOpen(ExternalProviderDescriptor? provider) =>
      provider != null &&
      provider.capabilities.localOpen &&
      provider.kind != ExternalProviderKind.otzar;

  static ExternalProviderDescriptor of(ExternalProviderKind kind) =>
      switch (kind) {
        ExternalProviderKind.otzar => otzar,
        ExternalProviderKind.hebrewBooks => hebrewBooks,
        ExternalProviderKind.responsa => responsa,
      };

  static ExternalProviderDescriptor? byId(String? id) {
    final normalized = id?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final provider in all) {
      if (provider.id == normalized) return provider;
    }
    return null;
  }

  static ExternalProviderDescriptor? byPrefix(String? prefix) {
    final normalized = prefix?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final provider in all) {
      if (provider.allPrefixes.contains(normalized)) return provider;
    }
    return null;
  }

  /// מפענח רק `prefix:value` עם תחילית מוכרת - לא חילוץ ספרות: `"ספר 3 חלקים"`
  /// אינו מזהה, ו-`rp:1524` אינו `1524` של היברובוקס.
  static ExternalBookRef? parse(String? externalLibraryId) {
    final raw = externalLibraryId?.trim();
    if (raw == null || raw.isEmpty) return null;
    final separator = raw.indexOf(':');
    if (separator <= 0 || separator == raw.length - 1) return null;
    final provider = byPrefix(raw.substring(0, separator));
    if (provider == null) return null;
    final value = raw.substring(separator + 1).trim();
    if (value.isEmpty) return null;
    return ExternalBookRef(provider, value);
  }

  /// זיהוי ספק מתוך כתובת אתר — נדרש לספרים ישנים שנשמרו בלי
  /// `externalLibraryId` תקין.
  static ExternalProviderDescriptor? fromLink(String? link) {
    final value = link?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    if (value.contains('hebrewbooks.org')) return hebrewBooks;
    if (value.contains('otzar.org')) return otzar;
    return null;
  }

  static String? _otzarLink(String value) =>
      'https://tablet.otzar.org/book/book.php?book=$value';

  static String? _hebrewBooksLink(String value) =>
      'https://hebrewbooks.org/$value';
}
