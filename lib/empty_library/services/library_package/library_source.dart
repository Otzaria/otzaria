import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show SplitAsset, kSplitManifestSuffix;

/// רכיבי הספרייה שהייבוא מזהה ומדווח עליהם.
enum LibraryComponent { libraryDb, talmudBavli, catalog, lexicon, searchIndex }

/// מה הייבוא התקין, ואילו רכיבים חסרים בספרייה אחריו. האינדקס אינו נחשב
/// חסר: כשאינו בחבילה התוכנה בונה אותו.
class LibraryImportReport extends Equatable {
  const LibraryImportReport({required this.imported, required this.missing});

  final Set<LibraryComponent> imported;
  final Set<LibraryComponent> missing;

  @override
  List<Object?> get props => [imported, missing];
}

/// תת-התיקייה שבה חבילת אנדרואיד המלאה מניחה את קובצי הספרייה.
const kLibraryDbSubfolder = 'library_db';

enum RawAssetFormat {
  /// zstd שמפוענח לקובץ — קובץ אחד או חלקים לפי מניפסט.
  zstd,

  /// קובץ מוכן שמועתק כמות שהוא.
  plain,

  /// tar.zst שנפרס לתיקייה.
  tarZstd,

  /// תיקייה שכבר חולצה; נתמכת רק בתיקייה רגילה (לא SAF).
  directory,
}

/// נכס ספרייה גולמי שנמצא בתיקיית המקור.
class RawLibraryAsset {
  const RawLibraryAsset({
    required this.component,
    required this.format,
    required this.folder,
    required this.sourceName,
    this.parts = const [],
    this.sha256,
    this.directoryPath,
  });

  final LibraryComponent component;
  final RawAssetFormat format;

  /// התיקייה שבה יושבים [parts] — השורש או [kLibraryDbSubfolder].
  final PackageFolder folder;

  /// שם הקובץ במקור, או שם הארכיון השלם כשהוא מפוצל.
  final String sourceName;
  final List<LibraryPackagePart> parts;

  /// ה-SHA-256 של הארכיון השלם, ממניפסט החלקים.
  final String? sha256;
  final String? directoryPath;

  int get size => parts.fold(0, (sum, part) => sum + part.size);

  /// שם הקובץ או התיקייה בתיקיית הספרים.
  String get targetName => switch (component) {
    LibraryComponent.libraryDb => DatabaseConstants.databaseFileName,
    LibraryComponent.catalog =>
      DatabaseConstants.externalCatalogDatabaseFileName,
    LibraryComponent.lexicon => DatabaseConstants.lexicalDatabaseFileName,
    LibraryComponent.talmudBavli => DatabaseConstants.talmudBavliFolderName,
    LibraryComponent.searchIndex => throw UnsupportedError(
      'אינדקס אינו נכס גולמי',
    ),
  };
}

/// נכסי הספרייה הגולמיים שבתיקייה. [problem] — ה-DB נמצא כחלקים שאי אפשר
/// לייבא (חלק חסר, מניפסט פגום), ואין גרסה אחרת שלו.
class RawLibraryScan {
  const RawLibraryScan({this.assets = const {}, this.problem});

  final Map<LibraryComponent, RawLibraryAsset> assets;
  final String? problem;

  bool get isEmpty => assets.isEmpty && problem == null;
  int get compressedSize =>
      assets.values.fold(0, (sum, asset) => sum + asset.size);
}

/// מה שנמצא בתיקיית המקור: חבילת המסייע (גוברת) או נכסים גולמיים.
class LibrarySourceScan {
  const LibrarySourceScan({
    required this.folder,
    this.packages = const LibraryPackageScan(),
    this.raw = const RawLibraryScan(),
    this.singleVolume = false,
  });

  final PackageFolder folder;
  final LibraryPackageScan packages;
  final RawLibraryScan raw;

  /// נבחרה תיקייה של כרך אחד (`otzaria-android-full-part2`), ולכן חלקים
  /// חסרים כנראה חולצו לתיקיות הכרכים שלצידה.
  final bool singleVolume;

  bool get isEmpty => packages.isEmpty && raw.isEmpty;

  /// הרכיבים שהייבוא יתקין.
  Set<LibraryComponent> get components {
    final set = packages.packages;
    if (set == null) return raw.assets.keys.toSet();
    // חבילת המסייע היא books/ שלם.
    return {
      LibraryComponent.libraryDb,
      LibraryComponent.talmudBavli,
      LibraryComponent.catalog,
      LibraryComponent.lexicon,
      if (set.index != null) LibraryComponent.searchIndex,
    };
  }
}

/// כרכי ה-ZIP של חבילת אנדרואיד המלאה נפתחים לתיקייה בשם הזה.
const kAndroidFullBundlePrefix = 'otzaria-android-full';

final _volumeFolderName = RegExp('^$kAndroidFullBundlePrefix-part[0-9]+');

/// סורק את [folder] ואת תיקיות החבילה שבו ואת
/// otzaria-android-full שבכל אחת: מנהלי קבצים מחלצים כל כרך לתיקייה משלו.
Future<LibrarySourceScan> scanLibrarySource(PackageFolder folder) async {
  final singleVolume = folder.displayName
      .split(RegExp(r'[\\/]'))
      .reversed
      .take(2)
      .any(_volumeFolderName.hasMatch);
  final scan = await _scanSource(folder, singleVolume);
  if (scan.packages.packages != null) return scan;
  final members = <PackageFolder>[folder];
  for (final name in (await folder.folderNames())..sort()) {
    if (!name.startsWith(kAndroidFullBundlePrefix)) continue;
    final volume = await folder.child(name);
    if (volume == null) continue;
    members.add(volume);
    final inner = await volume.child(kAndroidFullBundlePrefix);
    if (inner != null) members.add(inner);
  }
  if (members.length == 1) return scan;
  if (scan.isEmpty && members.length == 2) {
    return _scanSource(members.last, singleVolume);
  }
  final merged = MergedPackageFolder(members, displayName: folder.displayName);
  var mergedScan = await _scanSource(merged, singleVolume);
  final conflicts = await merged.conflicts();
  final rootNames = {for (final entry in await folder.list()) entry.name};
  if (!scan.isEmpty &&
      conflicts.every(rootNames.contains) &&
      !mergedScan.components.contains(LibraryComponent.libraryDb)) {
    // התנגשות או מניפסט חלקי אינם גוברים על מקור שלם בפני עצמו.
    for (final member in members) {
      final candidate = identical(member, folder)
          ? scan
          : await _scanSource(member, singleVolume);
      if (candidate.packages.packages != null) return candidate;
      if (candidate.raw.assets.containsKey(LibraryComponent.libraryDb)) {
        mergedScan = LibrarySourceScan(
          folder: merged,
          raw: RawLibraryScan(
            assets: {
              ...mergedScan.raw.assets,
              ...candidate.raw.assets,
              ...scan.raw.assets,
            },
          ),
          singleVolume: singleVolume,
        );
        break;
      }
    }
  }
  if (mergedScan.packages.packages == null &&
      mergedScan.components.contains(LibraryComponent.libraryDb)) {
    return LibrarySourceScan(
      folder: merged,
      raw: RawLibraryScan(
        assets: {...mergedScan.raw.assets, ...scan.raw.assets},
      ),
      singleVolume: singleVolume,
    );
  }
  if (conflicts.isEmpty ||
      mergedScan.components.contains(LibraryComponent.libraryDb)) {
    return mergedScan;
  }
  final missing = mergedScan.packages.problemFile;
  return LibrarySourceScan(
    folder: merged,
    packages: LibraryPackageScan(
      problem: LibraryPackageProblem.conflictingParts,
      problemFile: conflicts.contains(missing)
          ? missing
          : (conflicts.toList()..sort()).first,
    ),
  );
}

Future<LibrarySourceScan> _scanSource(
  PackageFolder folder,
  bool singleVolume,
) async {
  final packages = await scanLibraryPackages(folder);
  return LibrarySourceScan(
    folder: folder,
    packages: packages,
    raw: packages.packages != null
        ? const RawLibraryScan()
        : await scanRawLibraryAssets(folder),
    singleVolume: singleVolume,
  );
}

/// מזהה את קובצי הספרייה שבשורש [root] וב-[kLibraryDbSubfolder] שבו;
/// לכל רכיב — הגרסה הראשונה שנמצאה, והשורש קודם.
Future<RawLibraryScan> scanRawLibraryAssets(PackageFolder root) async {
  final folders = [root, ?await root.child(kLibraryDbSubfolder)];
  final assets = <LibraryComponent, RawLibraryAsset>{};
  String? problem;
  for (final folder in folders) {
    final files = {for (final e in await folder.list()) e.name: e};
    if (!assets.containsKey(LibraryComponent.libraryDb)) {
      try {
        final db = await _findDatabase(folder, files);
        if (db != null) assets[LibraryComponent.libraryDb] = db;
      } on FormatException catch (e) {
        problem ??= e.message;
      }
    }
    final found = [
      _single(folder, files, LibraryComponent.catalog, [
        (DatabaseConstants.externalCatalogArchiveFileName, RawAssetFormat.zstd),
        (
          DatabaseConstants.externalCatalogDatabaseFileName,
          RawAssetFormat.plain,
        ),
      ]),
      _single(folder, files, LibraryComponent.lexicon, [
        for (final name in DatabaseConstants.lexicalReleaseAssetFileNames)
          (name, RawAssetFormat.plain),
      ]),
      _single(folder, files, LibraryComponent.talmudBavli, [
        (DatabaseConstants.talmudBavliArchiveFileName, RawAssetFormat.tarZstd),
      ]),
      await _extractedTalmud(folder),
    ];
    for (final asset in found.nonNulls) {
      assets.putIfAbsent(asset.component, () => asset);
    }
  }
  return RawLibraryScan(
    assets: assets,
    problem: assets.containsKey(LibraryComponent.libraryDb) ? null : problem,
  );
}

RawLibraryAsset? _single(
  PackageFolder folder,
  Map<String, PackageFileEntry> files,
  LibraryComponent component,
  List<(String, RawAssetFormat)> candidates,
) {
  for (final (name, format) in candidates) {
    final entry = files[name];
    if (entry == null) continue;
    return RawLibraryAsset(
      component: component,
      format: format,
      folder: folder,
      sourceName: name,
      parts: [LibraryPackagePart(entry: entry)],
    );
  }
  return null;
}

Future<RawLibraryAsset?> _extractedTalmud(PackageFolder folder) async {
  if (folder is MergedPackageFolder) {
    for (final member in folder.members) {
      final asset = await _extractedTalmud(member);
      if (asset != null) return asset;
    }
  }
  if (folder is! DirectoryPackageFolder) return null;
  final dir = Directory(
    p.join(folder.path, DatabaseConstants.talmudBavliFolderName),
  );
  if (!await dir.exists()) return null;
  return RawLibraryAsset(
    component: LibraryComponent.talmudBavli,
    format: RawAssetFormat.directory,
    folder: folder,
    sourceName: DatabaseConstants.talmudBavliFolderName,
    directoryPath: dir.path,
  );
}

/// סדר העדפה: הסכמה הגבוהה ביותר שהגרסה קוראת (קובץ שלם לפני חלקים),
/// ואחריה seforim.db רגיל.
Future<RawLibraryAsset?> _findDatabase(
  PackageFolder folder,
  Map<String, PackageFileEntry> files,
) async {
  for (final name in DatabaseConstants.supportedDatabaseArchiveFileNames) {
    final whole = _single(folder, files, LibraryComponent.libraryDb, [
      (name, RawAssetFormat.zstd),
    ]);
    if (whole != null) return whole;
    final manifest = files['$name$kSplitManifestSuffix'];
    if (manifest != null) return _fromSplitManifest(folder, files, manifest);
  }
  return _single(folder, files, LibraryComponent.libraryDb, [
    (DatabaseConstants.databaseFileName, RawAssetFormat.plain),
  ]);
}

/// מניפסט בצורת `split_release_asset.sh`; זורק [FormatException] עם שם
/// החלק החסר או הפגום.
Future<RawLibraryAsset> _fromSplitManifest(
  PackageFolder folder,
  Map<String, PackageFileEntry> files,
  PackageFileEntry manifest,
) async {
  final Object? json;
  try {
    final bytes = await folder
        .openRead(manifest)
        .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw FormatException('הקובץ ${manifest.name} פגום');
  }
  if (json is Map && json['parts'] is List) {
    for (final part in json['parts'] as List) {
      if (part is! Map || part['name'] is! String) continue;
      final entry = files[part['name']];
      if (entry == null) throw FormatException('חסר הקובץ ${part['name']}');
      if (entry.size != part['size']) {
        throw FormatException('הקובץ ${part['name']} אינו שלם');
      }
    }
  }
  final split = SplitAsset.fromManifestJson(
    json,
    manifestName: manifest.name,
    partUrls: {for (final name in files.keys) name: name},
  );
  return RawLibraryAsset(
    component: LibraryComponent.libraryDb,
    format: RawAssetFormat.zstd,
    folder: folder,
    sourceName: split.archive,
    parts: [
      for (final part in split.parts)
        LibraryPackagePart(entry: files[part.name]!, sha256: part.sha256),
    ],
    sha256: split.sha256,
  );
}
