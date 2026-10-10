// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// גרסת הסכמה של מניפסט ה-release. צרכנים חייבים לדחות גרסה גבוהה יותר.
const int kReleaseManifestSchemaVersion = 1;

/// מגבלת GitHub לנכס בודד — נכס גדול ממנה חייב להתפצל.
const int kGithubAssetLimit = 2147483648;

/// מאגר ברירת המחדל שממנו מגיעים הנכסים הבנויים.
const String kOtzariaRepository = 'Otzaria/otzaria';

final RegExp _repositoryPattern = RegExp(r'^Otzaria/[A-Za-z0-9._-]+$');
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// שגיאת קלט בבניית המניפסט. תמיד עוצרת את הבנייה — מניפסט חלקי גרוע
/// מהיעדר מניפסט, כי הצרכן אינו יכול להבחין בין "אין רכיב" ל"הקלט שבור".
class ReleaseManifestException implements Exception {
  ReleaseManifestException(this.message);
  final String message;
  @override
  String toString() => 'ReleaseManifestException: $message';
}

/// תיאור נכס בודד בטבלת הרכיבים: המאגר שממנו הוא מגיע ותבנית שם הקובץ.
class AssetSpec {
  const AssetSpec({
    required this.pattern,
    this.repository = kOtzariaRepository,
    this.split = false,
  });

  /// תבנית (ביטוי רגולרי) לשם הקובץ בתיקיית ה-release. עבור נכס מפוצל
  /// התבנית מתארת את קובץ ה-`*.manifest.json`, לא את החלקים.
  final String pattern;
  final String repository;
  final bool split;
}

/// רכיב ידוע — השורה הדקלרטיבית היחידה שצריך להוסיף כדי שרכיב חדש
/// יופיע במניפסט. רכיב שכל נכסיו חסרים פשוט מושמט.
class ComponentSpec {
  const ComponentSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.required,
    required this.installOrder,
    required this.assets,
    this.nameEn,
    this.descriptionEn,
    this.platform,
    this.architecture,
    this.packageFormat,
    this.dependsOn = const [],
    this.installedBy = const [],
    this.origin = 'built',
    this.installedSize,
    this.compatibilityFromLibraryIndexProvenance = false,
    this.outputNote,
    this.outputNoteEn,
  });

  final String id;
  final String name;
  final String description;

  /// הטקסט למסייע שרץ באנגלית. חסר = הצרכן מציג את [name] / [description].
  final String? nameEn;
  final String? descriptionEn;
  final String type;
  final bool required;
  final int installOrder;
  final List<AssetSpec> assets;
  final String? platform;
  final String? architecture;

  /// פורמט החבילה (`deb` / `rpm`) — רק לרכיב שהוא חבילת התקנה של מנהל
  /// חבילות. רכיב בלעדיו מתאים לכל פורמט שנבחר.
  final String? packageFormat;
  final List<String> dependsOn;

  /// הרכיבים שמתקינים את הרכיב הזה (למשל מתקין שקורא את חלקי הספרייה לצדו).
  /// המסייע מציע אותו רק כשאחד מהם מוצע, ומוריד אותו יחד איתו.
  final List<String> installedBy;

  /// תיעוד מקור בלבד (רישוי/ייחוס) — אינו משפיע על נתיב ההורדה.
  final String origin;
  final int? installedSize;
  final bool compatibilityFromLibraryIndexProvenance;

  /// משפט שעמוד הסיום של המסייע מוסיף כשהרכיב הוכן.
  final String? outputNote;
  final String? outputNoteEn;
}

/// טבלת הרכיבים הידועים. הוספת רכיב = הוספת שורה כאן בלבד.
const List<ComponentSpec> kKnownComponents = [
  ComponentSpec(
    id: 'otzaria-windows-x64',
    name: 'אוצריא ל-Windows',
    description: 'התוכנה עצמה, ללא ספרייה. מתקין רגיל למעבדי x64.',
    nameEn: 'Otzaria for Windows',
    descriptionEn:
        'Otzaria itself, without the library. A standard installer for x64 '
        'processors.',
    type: 'application',
    required: true,
    platform: 'windows',
    architecture: 'x64',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-.+-windows\.exe$')],
  ),
  ComponentSpec(
    id: 'otzaria-windows-arm64',
    name: 'אוצריא ל-Windows (ARM64)',
    description: 'התוכנה עצמה למחשבי ARM64, ללא ספרייה.',
    nameEn: 'Otzaria for Windows (ARM64)',
    descriptionEn: 'Otzaria itself for ARM64 computers, without the library.',
    type: 'application',
    required: false,
    platform: 'windows',
    architecture: 'arm64',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-.+-windows_arm64\.exe$')],
  ),
  ComponentSpec(
    id: 'otzaria-windows-portable-x64',
    name: 'אוצריא ל-Windows — גרסה ניידת',
    description: 'ארכיון ZIP שאינו דורש התקנה, למעבדי x64.',
    nameEn: 'Otzaria for Windows — Portable Version',
    descriptionEn:
        'A ZIP archive that needs no installation, for x64 processors.',
    // צורה חלופית של אותה תוכנה ולא רכיב נוסף — סוג משלה מונע מההצעות
    // לצרף אותה יחד עם המתקין.
    type: 'application-portable',
    required: false,
    platform: 'windows',
    architecture: 'x64',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-windows\.zip$')],
  ),
  ComponentSpec(
    id: 'otzaria-windows-portable-arm64',
    name: 'אוצריא ל-Windows — גרסה ניידת (ARM64)',
    description: 'ארכיון ZIP שאינו דורש התקנה, למחשבי ARM64.',
    nameEn: 'Otzaria for Windows — Portable Version (ARM64)',
    descriptionEn:
        'A ZIP archive that needs no installation, for ARM64 computers.',
    type: 'application-portable',
    required: false,
    platform: 'windows',
    architecture: 'arm64',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-windows_arm64\.zip$')],
  ),
  ComponentSpec(
    id: 'otzaria-windows-full',
    name: 'אוצריא ל-Windows עם ספרייה מלאה',
    description:
        'מתקין הכולל את התוכנה ואת הספרייה המלאה, בלי אינדקס חיפוש בנוי מראש.',
    nameEn: 'Otzaria for Windows with the Full Library',
    descriptionEn:
        'An installer with Otzaria and the full library, without a prebuilt '
        'search index.',
    type: 'application-bundle',
    required: false,
    platform: 'windows',
    architecture: 'x64',
    installOrder: 20,
    // שתי הצורות זרות זו לזו: פיצול הנכס מוחק את ה-exe, ולכן רק אחת קיימת.
    assets: [
      AssetSpec(pattern: r'^otzaria-.+-windows-full\.exe$'),
      AssetSpec(
        pattern: r'^otzaria-.+-windows-full\.exe\.manifest\.json$',
        split: true,
      ),
    ],
  ),
  ComponentSpec(
    id: 'otzaria-windows-full-arm64',
    name: 'אוצריא ל-Windows עם ספרייה מלאה (ARM64)',
    description:
        'מתקין הכולל את התוכנה ואת הספרייה המלאה, למחשבי ARM64, בלי אינדקס '
        'חיפוש בנוי מראש.',
    nameEn: 'Otzaria for Windows with the Full Library (ARM64)',
    descriptionEn:
        'An installer with Otzaria and the full library for ARM64 computers, '
        'without a prebuilt search index.',
    type: 'application-bundle',
    required: false,
    platform: 'windows',
    architecture: 'arm64',
    installOrder: 20,
    assets: [
      AssetSpec(pattern: r'^otzaria-.+-windows_arm64-full\.exe$'),
      AssetSpec(
        pattern: r'^otzaria-.+-windows_arm64-full\.exe\.manifest\.json$',
        split: true,
      ),
    ],
  ),
  ComponentSpec(
    id: 'otzaria-linux-deb-x64',
    name: 'אוצריא ל-Linux (DEB)',
    description:
        'חבילת התקנה ל-Ubuntu, Debian, Mint והפצות דומות, למעבדי x64. ללא ספרייה.',
    nameEn: 'Otzaria for Linux (DEB)',
    descriptionEn:
        'An installation package for Ubuntu, Debian, Mint and similar '
        'distributions, for x64 processors. Library not included.',
    type: 'application',
    required: false,
    platform: 'linux',
    architecture: 'x64',
    packageFormat: 'deb',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-.+-linux\.deb$')],
  ),
  ComponentSpec(
    id: 'otzaria-linux-deb-arm64',
    name: 'אוצריא ל-Linux (DEB, ARM64)',
    description:
        'חבילת התקנה ל-Ubuntu, Debian, Mint והפצות דומות, למחשבי ARM64. ללא ספרייה.',
    nameEn: 'Otzaria for Linux (DEB, ARM64)',
    descriptionEn:
        'An installation package for Ubuntu, Debian, Mint and similar '
        'distributions, for ARM64 computers. Library not included.',
    type: 'application',
    required: false,
    platform: 'linux',
    architecture: 'arm64',
    packageFormat: 'deb',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-.+-linux-arm64\.deb$')],
  ),
  ComponentSpec(
    id: 'otzaria-linux-rpm-x64',
    name: 'אוצריא ל-Linux (RPM)',
    description:
        'חבילת התקנה ל-Fedora, openSUSE והפצות דומות, למעבדי x64. ללא ספרייה.',
    nameEn: 'Otzaria for Linux (RPM)',
    descriptionEn:
        'An installation package for Fedora, openSUSE and similar '
        'distributions, for x64 processors. Library not included.',
    type: 'application',
    required: false,
    platform: 'linux',
    architecture: 'x64',
    packageFormat: 'rpm',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-.+\.x86_64\.rpm$')],
  ),
  ComponentSpec(
    id: 'otzaria-linux-rpm-arm64',
    name: 'אוצריא ל-Linux (RPM, ARM64)',
    description:
        'חבילת התקנה ל-Fedora, openSUSE והפצות דומות, למחשבי ARM64. ללא ספרייה.',
    nameEn: 'Otzaria for Linux (RPM, ARM64)',
    descriptionEn:
        'An installation package for Fedora, openSUSE and similar '
        'distributions, for ARM64 computers. Library not included.',
    type: 'application',
    required: false,
    platform: 'linux',
    architecture: 'arm64',
    packageFormat: 'rpm',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-.+\.aarch64\.rpm$')],
  ),
  // נבנית רק כשחבילת ה-DEB נכשלה בבנייה, ולכן לרוב נעדרת מה-release.
  ComponentSpec(
    id: 'otzaria-linux-portable-x64',
    name: 'אוצריא ל-Linux — גרסה ניידת',
    description: 'ארכיון ZIP שאינו דורש התקנה, למעבדי x64. ללא ספרייה.',
    nameEn: 'Otzaria for Linux — Portable Version',
    descriptionEn:
        'A ZIP archive that needs no installation, for x64 processors. '
        'Library not included.',
    type: 'application-portable',
    required: false,
    platform: 'linux',
    architecture: 'x64',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-linux-raw\.zip$')],
  ),
  ComponentSpec(
    id: 'otzaria-linux-portable-arm64',
    name: 'אוצריא ל-Linux — גרסה ניידת (ARM64)',
    description: 'ארכיון ZIP שאינו דורש התקנה, למחשבי ARM64. ללא ספרייה.',
    nameEn: 'Otzaria for Linux — Portable Version (ARM64)',
    descriptionEn:
        'A ZIP archive that needs no installation, for ARM64 computers. '
        'Library not included.',
    type: 'application-portable',
    required: false,
    platform: 'linux',
    architecture: 'arm64',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-linux-raw-arm64\.zip$')],
  ),
  ComponentSpec(
    id: 'otzaria-linux-full-x64',
    name: 'אוצריא ל-Linux עם ספרייה מלאה',
    description:
        'ארכיון tar.zst ובו התוכנה והספרייה המלאה, למעבדי x64. פורסים אותו '
        'ומפעילים ללא התקנה.',
    nameEn: 'Otzaria for Linux with the Full Library',
    descriptionEn:
        'A tar.zst archive with Otzaria and the full library, for x64 '
        'processors. Extract it and run Otzaria, no installation needed.',
    type: 'application-bundle',
    required: false,
    platform: 'linux',
    architecture: 'x64',
    installOrder: 20,
    assets: [
      AssetSpec(pattern: r'^otzaria-linux-full\.tar\.zst$'),
      AssetSpec(
        pattern: r'^otzaria-linux-full\.tar\.zst\.manifest\.json$',
        split: true,
      ),
    ],
  ),
  ComponentSpec(
    id: 'otzaria-linux-full-arm64',
    name: 'אוצריא ל-Linux עם ספרייה מלאה (ARM64)',
    description:
        'ארכיון tar.zst ובו התוכנה והספרייה המלאה, למחשבי ARM64. פורסים אותו '
        'ומפעילים ללא התקנה.',
    nameEn: 'Otzaria for Linux with the Full Library (ARM64)',
    descriptionEn:
        'A tar.zst archive with Otzaria and the full library, for ARM64 '
        'computers. Extract it and run Otzaria, no installation needed.',
    type: 'application-bundle',
    required: false,
    platform: 'linux',
    architecture: 'arm64',
    installOrder: 20,
    assets: [
      AssetSpec(pattern: r'^otzaria-linux-full-arm64\.tar\.zst$'),
      AssetSpec(
        pattern: r'^otzaria-linux-full-arm64\.tar\.zst\.manifest\.json$',
        split: true,
      ),
    ],
  ),
  // ה-DMG הוא Universal Binary — אותו קובץ ל-Intel ול-Apple Silicon, ולכן
  // אין לו ארכיטקטורה.
  ComponentSpec(
    id: 'otzaria-macos',
    name: 'אוצריא ל-macOS',
    description:
        'קובץ DMG: גוררים ממנו את אוצריא לתיקיית היישומים. ללא ספרייה.',
    nameEn: 'Otzaria for macOS',
    descriptionEn:
        'A DMG file: drag Otzaria from it into the Applications folder. '
        'Library not included.',
    type: 'application',
    required: false,
    platform: 'macos',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^otzaria-macos\.dmg$')],
  ),
  ComponentSpec(
    id: 'otzaria-macos-full',
    name: 'אוצריא ל-macOS עם ספרייה מלאה',
    description:
        'ארכיון tar.zst ובו התוכנה והספרייה המלאה. פורסים אותו ומפעילים ללא '
        'התקנה.',
    nameEn: 'Otzaria for macOS with the Full Library',
    descriptionEn:
        'A tar.zst archive with Otzaria and the full library. Extract it and '
        'run Otzaria, no installation needed.',
    type: 'application-bundle',
    required: false,
    platform: 'macos',
    installOrder: 20,
    assets: [
      AssetSpec(pattern: r'^otzaria-macos-full\.tar\.zst$'),
      AssetSpec(
        pattern: r'^otzaria-macos-full\.tar\.zst\.manifest\.json$',
        split: true,
      ),
    ],
  ),
  // ה-APK כולל את כל ארכיטקטורות המעבד, ולכן אין לו ארכיטקטורה.
  ComponentSpec(
    id: 'otzaria-android',
    name: 'אוצריא ל-Android',
    description: 'קובץ התקנה (APK) לטלפון או לטאבלט. ללא ספרייה.',
    nameEn: 'Otzaria for Android',
    descriptionEn:
        'An installation file (APK) for a phone or tablet. Library not '
        'included.',
    type: 'application',
    required: false,
    platform: 'android',
    installOrder: 10,
    assets: [AssetSpec(pattern: r'^[^\\/]+\.apk$')],
  ),
  // המתקינים הרגילים של Windows פורסים את החלקים שלצדם (installer/otzaria.iss),
  // ובאנדרואיד "ייבוא מתיקיית קובצי הספרייה" באפליקציה (lib/empty_library/services/library_package).
  ComponentSpec(
    id: 'library-full',
    name: 'ספרייה מלאה',
    description:
        'כל ספריית הספרים, למחשב שאין בו אינטרנט. המתקין פורס אותה בעצמו, '
        'ואת אינדקס החיפוש התוכנה בונה אחרי ההתקנה.',
    nameEn: 'Full Library',
    descriptionEn:
        'The complete library for an offline computer. The installer extracts '
        'it, and the app builds the search index after installation.',
    type: 'library',
    required: false,
    platform: 'any',
    installOrder: 30,
    installedBy: [
      'otzaria-windows-x64',
      'otzaria-windows-arm64',
      'otzaria-android',
    ],
    compatibilityFromLibraryIndexProvenance: true,
    outputNote:
        'אוצריא פורסת את הספרייה מהקבצים שבתיקייה בלי אינטרנט: ב-Windows '
        'המתקין עושה זאת בזמן ההתקנה, וב-Android בוחרים "ייבוא מתיקיית קובצי '
        'הספרייה" באוצריא אחרי התקנת ה-APK.',
    outputNoteEn:
        'Otzaria extracts the library from the files in this folder without '
        'an internet connection: on Windows the installer does it during '
        'installation; on Android, install the APK and choose "Import from the '
        'Library Files Folder" in Otzaria.',
    assets: [
      AssetSpec(
        pattern: r'^otzaria-.+-library\.tar\.zst\.manifest\.json$',
        split: true,
      ),
    ],
  ),
  // סוג משלו, ולא library: "מלאה" אוספת ספריות, והאינדקס אינו חלק ממנה.
  ComponentSpec(
    id: 'library-index',
    name: 'אינדקס חיפוש מוכן (למחשבים חלשים)',
    description:
        'בדרך כלל אין בו צורך: התוכנה בונה את אינדקס החיפוש בעצמה אחרי '
        'ההתקנה. מומלץ רק למחשב חלש, שבו בניית האינדקס איטית מאוד. מגיע '
        'יחד עם הספרייה המלאה.',
    nameEn: 'Prebuilt Search Index (for Slower Computers)',
    descriptionEn:
        'Usually unnecessary: the app builds its search index after '
        'installation. Recommended only for a slow computer where indexing '
        'takes a long time. Includes the full library.',
    type: kLibraryIndexType,
    required: false,
    platform: 'any',
    installOrder: 31,
    dependsOn: ['library-full'],
    installedBy: [
      'otzaria-windows-x64',
      'otzaria-windows-arm64',
      'otzaria-android',
    ],
    compatibilityFromLibraryIndexProvenance: true,
    outputNote:
        'אינדקס החיפוש המוכן נפרס יחד עם הספרייה, ולכן התוכנה אינה בונה אותו '
        'אחרי ההתקנה.',
    outputNoteEn:
        'The prebuilt search index is extracted with the library, so the app '
        'does not need to build it after installation.',
    assets: [
      AssetSpec(
        pattern: r'^otzaria-.+-library-index\.tar\.zst\.manifest\.json$',
        split: true,
      ),
    ],
  ),
];

/// סוג רכיב האינדקס הבנוי מראש.
const String kLibraryIndexType = 'library-index';

/// סוגים שאינם מותקנים בעצמם, ולכן חייבים לשאת `installedBy`.
const Set<String> kInstalledByRequiredTypes = {'library', kLibraryIndexType};

/// בונה את מניפסט ה-release מתוך [directory] — תיקיית קבצי ה-release של CI.
///
/// [externalComponents] הם רכיבים המתארים נכסים במאגרים אחרים בארגון Otzaria
/// (לדוגמה Otzaria/SeforimLibrary) שאינם יושבים בתיקייה המקומית.
Map<String, Object?> buildReleaseManifest({
  required String releaseTag,
  required String releaseVersion,
  required Directory directory,
  List<ComponentSpec> specs = kKnownComponents,
  List<Map<String, Object?>> externalComponents = const [],
}) {
  if (releaseTag.trim().isEmpty) {
    throw ReleaseManifestException('release tag is empty');
  }
  if (releaseVersion.trim().isEmpty) {
    throw ReleaseManifestException('release version is empty');
  }
  if (!directory.existsSync()) {
    throw ReleaseManifestException(
      'release directory not found: '
      '${directory.path}',
    );
  }

  final files = <String, File>{};
  for (final entity in directory.listSync()) {
    if (entity is File) files[_basename(entity.path)] = entity;
  }

  final provenance = _readProvenance(files);
  final components = <Map<String, Object?>>[];

  for (final spec in specs) {
    final assets = <Map<String, Object?>>[];
    for (final assetSpec in spec.assets) {
      final pattern = RegExp(assetSpec.pattern);
      final matches = files.keys.where(pattern.hasMatch).toList()..sort();
      if (matches.isEmpty) continue;
      if (matches.length > 1) {
        throw ReleaseManifestException(
          'component ${spec.id}: ${matches.length} files match '
          '${assetSpec.pattern} ($matches)',
        );
      }
      assets.add(
        assetSpec.split
            ? _splitAsset(
                manifestFile: files[matches.single]!,
                files: files,
                repository: assetSpec.repository,
                releaseTag: releaseTag,
                componentId: spec.id,
              )
            : _singleAsset(
                file: files[matches.single]!,
                repository: assetSpec.repository,
                releaseTag: releaseTag,
              ),
      );
    }
    if (assets.isEmpty) continue;

    var downloadSize = 0;
    for (final asset in assets) {
      downloadSize += _downloadSizeOf(asset);
    }

    components.add({
      'id': spec.id,
      'name': spec.name,
      if (spec.nameEn != null) 'nameEn': spec.nameEn,
      'description': spec.description,
      if (spec.descriptionEn != null) 'descriptionEn': spec.descriptionEn,
      'type': spec.type,
      'required': spec.required,
      'origin': spec.origin,
      if (spec.platform != null) 'platform': spec.platform,
      if (spec.architecture != null) 'architecture': spec.architecture,
      if (spec.packageFormat != null) 'packageFormat': spec.packageFormat,
      'installOrder': spec.installOrder,
      'dependsOn': spec.dependsOn,
      if (spec.installedBy.isNotEmpty) 'installedBy': spec.installedBy,
      'downloadSize': downloadSize,
      if (spec.installedSize != null) 'installedSize': spec.installedSize,
      if (spec.compatibilityFromLibraryIndexProvenance && provenance != null)
        'compatibility': provenance,
      if (spec.outputNote != null) 'outputNote': spec.outputNote,
      if (spec.outputNoteEn != null) 'outputNoteEn': spec.outputNoteEn,
      'assets': assets,
    });
  }

  // רכיב שאף מתקין שלו, או אחת מתלויותיו, לא נבנו אינו שמיש — מושמט כמו רכיב
  // שנכסיו חסרים. אינדקס בלי ספרייה, למשל.
  final built = {for (final c in components) c['id']};
  components.removeWhere((component) {
    if (!(component['dependsOn'] as List<String>).every(built.contains)) {
      return true;
    }
    final installers = component['installedBy'] as List<String>?;
    if (installers == null) return false;
    final present = installers.where(built.contains).toList();
    component['installedBy'] = present;
    return present.isEmpty;
  });

  for (final external in externalComponents) {
    components.add(Map<String, Object?>.from(external));
  }

  components.sort((a, b) {
    final order = (a['installOrder'] as int).compareTo(
      b['installOrder'] as int,
    );
    return order != 0
        ? order
        : (a['id'] as String).compareTo(b['id'] as String);
  });

  final manifest = <String, Object?>{
    'schemaVersion': kReleaseManifestSchemaVersion,
    'releaseTag': releaseTag,
    'releaseVersion': releaseVersion,
    'components': components,
  };

  final errors = validateReleaseManifest(manifest);
  if (errors.isNotEmpty) {
    throw ReleaseManifestException(
      'generated manifest is invalid:\n - ${errors.join('\n - ')}',
    );
  }
  return manifest;
}

int _downloadSizeOf(Map<String, Object?> asset) {
  final parts = asset['parts'] as List<Object?>?;
  if (parts == null) return asset['size'] as int;
  var total = 0;
  for (final part in parts) {
    total += (part as Map<String, Object?>)['size'] as int;
  }
  return total;
}

Map<String, Object?> _singleAsset({
  required File file,
  required String repository,
  required String releaseTag,
}) {
  final measured = measureAsset(file);
  return {
    'kind': 'single',
    'repository': repository,
    'releaseTag': releaseTag,
    'name': _basename(file.path),
    'size': measured.size,
    'sha256': measured.sha256,
  };
}

/// גודל ו-sha256 של נכס.
class MeasuredAsset {
  const MeasuredAsset({required this.size, required this.sha256});
  final int size;
  final String sha256;
}

/// גודל ברירת המחדל של מקטע הקריאה. 1MiB — קטן דיו לכל runner.
const int kAssetHashChunkSize = 1024 * 1024;

/// מודד נכס בזרימה. נכס ה-release הגדול ביותר הוא כ-2GB, וקריאתו לזיכרון
/// בבת אחת הפילה את ה-runner.
MeasuredAsset measureAsset(File file, {int chunkSize = kAssetHashChunkSize}) {
  final sink = _DigestSink();
  final input = sha256.startChunkedConversion(sink);
  final handle = file.openSync();
  final buffer = Uint8List(chunkSize);
  var size = 0;
  try {
    while (true) {
      final read = handle.readIntoSync(buffer);
      if (read == 0) break;
      input.add(Uint8List.sublistView(buffer, 0, read));
      size += read;
    }
  } finally {
    handle.closeSync();
  }
  input.close();
  return MeasuredAsset(size: size, sha256: sink.digest.toString());
}

class _DigestSink implements Sink<Digest> {
  late final Digest digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}

/// נכס מפוצל — משקף את מניפסט הפיצול של `split_release_asset.sh` כלשונו,
/// כדי שלא תיווצר צורה שנייה לאותו מידע.
Map<String, Object?> _splitAsset({
  required File manifestFile,
  required Map<String, File> files,
  required String repository,
  required String releaseTag,
  required String componentId,
}) {
  final manifestName = _basename(manifestFile.path);
  Object? decoded;
  try {
    decoded = jsonDecode(manifestFile.readAsStringSync());
  } on FormatException catch (error) {
    throw ReleaseManifestException('$manifestName is not valid JSON: $error');
  }
  if (decoded is! Map<String, Object?>) {
    throw ReleaseManifestException('$manifestName is not a JSON object');
  }
  if (decoded['schemaVersion'] != 1) {
    throw ReleaseManifestException(
      '$manifestName has schemaVersion ${decoded['schemaVersion']}; this '
      'generator reads 1',
    );
  }

  final archive = decoded['archive'];
  if (archive is! String || archive != _basename(archive) || archive.isEmpty) {
    throw ReleaseManifestException('$manifestName has an unsafe archive name');
  }
  final size = decoded['size'];
  final sha = decoded['sha256'];
  if (size is! int || size <= 0) {
    throw ReleaseManifestException('$manifestName has an invalid archive size');
  }
  if (sha is! String || !_sha256Pattern.hasMatch(sha)) {
    throw ReleaseManifestException('$manifestName has an invalid archive hash');
  }

  final rawParts = decoded['parts'];
  if (rawParts is! List || rawParts.isEmpty) {
    throw ReleaseManifestException('$manifestName lists no parts');
  }
  final parts = <Map<String, Object?>>[];
  for (final rawPart in rawParts) {
    if (rawPart is! Map) {
      throw ReleaseManifestException('$manifestName has a malformed part');
    }
    final name = rawPart['name'];
    final partSize = rawPart['size'];
    final partSha = rawPart['sha256'];
    if (name is! String || name.isEmpty || name != _basename(name)) {
      throw ReleaseManifestException('$manifestName has an unsafe part name');
    }
    if (partSize is! int || partSize <= 0 || partSize >= kGithubAssetLimit) {
      throw ReleaseManifestException(
        '$manifestName: part $name has an '
        'invalid size',
      );
    }
    if (partSha is! String || !_sha256Pattern.hasMatch(partSha)) {
      throw ReleaseManifestException(
        '$manifestName: part $name has an '
        'invalid hash',
      );
    }
    final partFile = files[name];
    if (partFile == null) {
      throw ReleaseManifestException(
        'component $componentId: part $name listed in $manifestName is not in '
        'the release directory',
      );
    }
    if (partFile.lengthSync() != partSize) {
      throw ReleaseManifestException(
        'component $componentId: part $name is ${partFile.lengthSync()} bytes '
        'but $manifestName records $partSize',
      );
    }
    parts.add({'name': name, 'size': partSize, 'sha256': partSha});
  }

  return {
    'kind': 'split',
    'repository': repository,
    'releaseTag': releaseTag,
    'name': archive,
    'size': size,
    'sha256': sha,
    'manifestAsset': manifestName,
    'githubAssetLimit': decoded['githubAssetLimit'] ?? kGithubAssetLimit,
    if (decoded['partSizeLimit'] != null)
      'partSizeLimit': decoded['partSizeLimit'],
    'parts': parts,
  };
}

/// מטא-דאטת התאמה מתוך `otzaria-library-index.provenance.json`, אם הוא נארז.
/// השדות הם אלה שהבנייה כבר משווה — לא מומצאים כאן חדשים.
Map<String, Object?>? _readProvenance(Map<String, File> files) {
  final file = files['otzaria-library-index.provenance.json'];
  if (file == null) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    throw ReleaseManifestException(
      'otzaria-library-index.provenance.json is not valid JSON: $error',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw ReleaseManifestException(
      'otzaria-library-index.provenance.json is not a JSON object',
    );
  }
  final compatibility = <String, Object?>{};
  for (final key in const [
    'libraryReleaseTag',
    'seforimDbZstSha256',
    'searchEngineVersion',
    'talmudVolumesDigest',
  ]) {
    final value = decoded[key];
    if (value != null) compatibility[key] = value;
  }
  return compatibility.isEmpty ? null : compatibility;
}

/// מאמת מניפסט מול הסכמה ומחזיר רשימת שגיאות (ריקה = תקין).
///
/// שדות לא מוכרים מותרים בכוונה — צרכן ישן חייב להמשיך לעבוד מול מניפסט חדש.
List<String> validateReleaseManifest(Object? manifest) {
  final errors = <String>[];
  if (manifest is! Map) {
    return ['manifest is not a JSON object'];
  }
  if (manifest['schemaVersion'] != kReleaseManifestSchemaVersion) {
    errors.add('schemaVersion must be $kReleaseManifestSchemaVersion');
  }
  for (final key in const ['releaseTag', 'releaseVersion']) {
    final value = manifest[key];
    if (value is! String || value.trim().isEmpty) {
      errors.add('$key must be a non-empty string');
    }
  }

  final components = manifest['components'];
  if (components is! List) {
    errors.add('components must be a list');
    return errors;
  }

  final ids = <String>{};
  for (final component in components) {
    if (component is! Map) {
      errors.add('a component is not a JSON object');
      continue;
    }
    final id = component['id'];
    final label = id is String ? id : '<unnamed>';
    if (id is! String || id.isEmpty) {
      errors.add('component $label: id must be a non-empty string');
    } else if (!ids.add(id)) {
      errors.add('component $label: duplicate id');
    }
    for (final key in const ['name', 'description', 'type', 'origin']) {
      final value = component[key];
      if (value is! String || value.isEmpty) {
        errors.add('component $label: $key must be a non-empty string');
      }
    }
    if (component['origin'] != 'built' && component['origin'] != 'imported') {
      errors.add('component $label: origin must be built or imported');
    }
    if (component['required'] is! bool) {
      errors.add('component $label: required must be a boolean');
    }
    for (final key in const ['platform', 'architecture', 'packageFormat']) {
      final value = component[key];
      if (value != null && (value is! String || value.isEmpty)) {
        errors.add('component $label: $key must be a non-empty string');
      }
    }
    if (component['installOrder'] is! int) {
      errors.add('component $label: installOrder must be an integer');
    }
    final downloadSize = component['downloadSize'];
    if (downloadSize is! int || downloadSize <= 0) {
      errors.add('component $label: downloadSize must be a positive integer');
    }
    final installedSize = component['installedSize'];
    if (installedSize != null &&
        (installedSize is! int || installedSize <= 0)) {
      errors.add('component $label: installedSize must be a positive integer');
    }
    final dependsOn = component['dependsOn'];
    if (dependsOn is! List || dependsOn.any((d) => d is! String)) {
      errors.add('component $label: dependsOn must be a list of ids');
    }
    final installedBy = component['installedBy'];
    if (installedBy != null &&
        (installedBy is! List ||
            installedBy.isEmpty ||
            installedBy.any((d) => d is! String))) {
      errors.add(
        'component $label: installedBy must be a non-empty list of ids',
      );
    }
    if (kInstalledByRequiredTypes.contains(component['type']) &&
        installedBy is! List) {
      errors.add(
        'component $label: a library must name the components that install '
        'it (installedBy)',
      );
    }
    final outputFolder = component['outputFolder'];
    if (outputFolder != null &&
        (outputFolder is! String || !isSafeOutputFolder(outputFolder))) {
      errors.add(
        'component $label: outputFolder must be a relative path of safe names',
      );
    }
    for (final key in const [
      'outputNote',
      'nameEn',
      'descriptionEn',
      'outputNoteEn',
    ]) {
      final value = component[key];
      if (value != null && (value is! String || value.trim().isEmpty)) {
        errors.add('component $label: $key must be a non-empty string');
      }
    }
    final compatibility = component['compatibility'];
    if (compatibility != null && compatibility is! Map) {
      errors.add('component $label: compatibility must be a map');
    }

    final assets = component['assets'];
    if (assets is! List || assets.isEmpty) {
      errors.add('component $label: assets must be a non-empty list');
      continue;
    }
    for (final asset in assets) {
      errors.addAll(_validateAsset(asset, label));
    }
  }

  final byId = {
    for (final component in components.whereType<Map>())
      if (component['id'] is String) component['id'] as String: component,
  };
  for (final component in components.whereType<Map>()) {
    final dependsOn = component['dependsOn'];
    if (dependsOn is List) {
      for (final dependency in dependsOn.whereType<String>()) {
        if (!ids.contains(dependency)) {
          errors.add(
            'component ${component['id']}: dependsOn unknown component '
            '$dependency',
          );
        }
      }
    }
    final partOf = component['partOf'];
    if (partOf != null) {
      final whole = byId[partOf];
      final wholeDepends = whole?['dependsOn'];
      // המסייעים אינם מציגים חלק לבדו — הוא מגיע רק דרך dependsOn של השלם.
      if (partOf is! String ||
          wholeDepends is! List ||
          !wholeDepends.contains(component['id'])) {
        errors.add(
          'component ${component['id']}: partOf must name a component that '
          'dependsOn it',
        );
      }
    }
    final installedBy = component['installedBy'];
    if (installedBy is! List) continue;
    for (final installer in installedBy.whereType<String>()) {
      final target = byId[installer];
      if (target == null) {
        errors.add(
          'component ${component['id']}: installedBy unknown component '
          '$installer',
        );
      } else if (installer == component['id'] ||
          target['installedBy'] != null) {
        // שרשרת מתקינים הייתה מחייבת את המסייעים לפתור רקורסיה.
        errors.add(
          'component ${component['id']}: installedBy $installer must be a '
          'component that is not itself installed by another',
        );
      }
    }
  }
  return errors;
}

final RegExp _outputFolderSegment = RegExp(r'^[A-Za-z0-9._-]+$');

/// תיקייה יחסית בתיקיית הפלט של המסייעים: שמות בטוחים מופרדים ב-`/`, בלי
/// מקטע של נקודות בלבד — המסייעים בונים ממנה נתיב כתיבה.
bool isSafeOutputFolder(String folder) => folder
    .split('/')
    .every(
      (segment) =>
          _outputFolderSegment.hasMatch(segment) &&
          segment.replaceAll('.', '').isNotEmpty,
    );

List<String> _validateAsset(Object? asset, String componentLabel) {
  final errors = <String>[];
  String prefix(String message) => 'component $componentLabel: $message';
  if (asset is! Map) return [prefix('an asset is not a JSON object')];

  final repository = asset['repository'];
  if (repository is! String || !_repositoryPattern.hasMatch(repository)) {
    errors.add(
      prefix(
        'repository must be owner/repo inside the Otzaria '
        'organization',
      ),
    );
  }
  final releaseTag = asset['releaseTag'];
  if (releaseTag is! String || releaseTag.trim().isEmpty) {
    errors.add(prefix('asset releaseTag must be a non-empty string'));
  }
  final name = asset['name'];
  if (name is! String || name.isEmpty || name != _basename(name)) {
    errors.add(prefix('asset name must be a bare file name'));
  }
  final size = asset['size'];
  if (size is! int || size <= 0) {
    errors.add(prefix('asset size must be a positive integer'));
  }
  final sha = asset['sha256'];
  if (sha is! String || !_sha256Pattern.hasMatch(sha)) {
    errors.add(prefix('asset sha256 must be 64 lowercase hex characters'));
  }

  final kind = asset['kind'];
  if (kind == 'single') {
    if (size is int && size >= kGithubAssetLimit) {
      errors.add(prefix('a single asset must stay below GitHub\'s limit'));
    }
    if (asset['parts'] != null) {
      errors.add(prefix('a single asset must not carry parts'));
    }
  } else if (kind == 'split') {
    final parts = asset['parts'];
    if (parts is! List || parts.isEmpty) {
      errors.add(prefix('a split asset must list its parts'));
    } else {
      var total = 0;
      for (final part in parts) {
        if (part is! Map) {
          errors.add(prefix('a split part is not a JSON object'));
          continue;
        }
        final partName = part['name'];
        final partSize = part['size'];
        final partSha = part['sha256'];
        if (partName is! String ||
            partName.isEmpty ||
            partName != _basename(partName)) {
          errors.add(prefix('a split part name must be a bare file name'));
        }
        if (partSize is! int ||
            partSize <= 0 ||
            partSize >= kGithubAssetLimit) {
          errors.add(prefix('a split part size must be below GitHub\'s limit'));
        } else {
          total += partSize;
        }
        if (partSha is! String || !_sha256Pattern.hasMatch(partSha)) {
          errors.add(prefix('a split part sha256 must be 64 hex characters'));
        }
      }
      if (size is int && total != 0 && total != size) {
        errors.add(
          prefix(
            'the split parts total $total bytes but the archive '
            'is $size',
          ),
        );
      }
    }
    final manifestAsset = asset['manifestAsset'];
    if (manifestAsset is! String ||
        manifestAsset.isEmpty ||
        manifestAsset != _basename(manifestAsset)) {
      errors.add(prefix('a split asset must name its manifest asset'));
    }
  } else {
    errors.add(prefix('asset kind must be single or split'));
  }
  return errors;
}

String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

String _option(List<String> args, String name) {
  final index = args.indexOf('--$name');
  if (index < 0 || index + 1 >= args.length) {
    throw ReleaseManifestException('missing required option --$name');
  }
  return args[index + 1];
}

String? _optionalOption(List<String> args, String name) {
  final index = args.indexOf('--$name');
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

void main(List<String> args) {
  const usage =
      'usage: dart run tool/release/generate_release_manifest.dart '
      '--tag <release-tag> --version <version> --dir <release-files> '
      '[--out <file>] [--external <components.json>]';
  try {
    final tag = _option(args, 'tag');
    final version = _option(args, 'version');
    final dir = _option(args, 'dir');
    final out =
        _optionalOption(args, 'out') ?? '$dir/otzaria-release-manifest.json';

    final externalPath = _optionalOption(args, 'external');
    var external = const <Map<String, Object?>>[];
    if (externalPath != null) {
      final decoded = jsonDecode(File(externalPath).readAsStringSync());
      if (decoded is! List) {
        throw ReleaseManifestException('$externalPath must be a JSON list');
      }
      external = decoded.map((e) {
        if (e is! Map) {
          throw ReleaseManifestException(
            '$externalPath has a non-object entry',
          );
        }
        return Map<String, Object?>.from(e);
      }).toList();
    }

    final manifest = buildReleaseManifest(
      releaseTag: tag,
      releaseVersion: version,
      directory: Directory(dir),
      externalComponents: external,
    );
    File(out).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    final components = (manifest['components'] as List).length;
    print('Wrote $out with $components components');
  } on ReleaseManifestException catch (error) {
    stderr.writeln('::error::${error.message}');
    stderr.writeln(usage);
    exitCode = 1;
  }
}
