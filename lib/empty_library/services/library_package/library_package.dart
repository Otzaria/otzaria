import 'dart:convert';

import 'package:otzaria/empty_library/services/library_package/package_folder.dart';

/// סוג הנכס שהמסייע הוריד: הספרייה (`books/`) או האינדקס המוכן (`index/`).
enum LibraryPackageKind {
  library('library', 'books'),
  searchIndex('library-index', 'index');

  const LibraryPackageKind(this.assetSuffix, this.rootFolder);

  /// הסיומת בשם הנכס: `otzaria-<ver>-<assetSuffix>.tar.zst`.
  final String assetSuffix;

  /// התיקייה היחידה בשורש ה-tar.
  final String rootFolder;
}

/// קטע של הארכיון. [sha256] קיים רק כשנקרא מניפסט חלקים.
class LibraryPackagePart {
  const LibraryPackagePart({required this.entry, this.sha256});

  final PackageFileEntry entry;
  final String? sha256;

  String get name => entry.name;
  int get size => entry.size;
}

/// ארכיון tar.zst של ספרייה או אינדקס, כחלקים או כקובץ אחד שהמסייע הרכיב.
class LibraryPackage {
  const LibraryPackage({
    required this.kind,
    required this.version,
    required this.archiveName,
    required this.parts,
    this.sha256,
  });

  final LibraryPackageKind kind;
  final String version;
  final String archiveName;
  final List<LibraryPackagePart> parts;

  /// ה-sha256 של הארכיון השלם, מהמניפסט.
  final String? sha256;

  int get compressedSize => parts.fold(0, (sum, part) => sum + part.size);

  /// בלי מניפסט האימות נשען על ה-checksum שבתוך ה-frame של zstd.
  bool get hasManifest => sha256 != null;
}

/// הספרייה, ואם הורד — האינדקס התואם לה, באותה תיקייה.
class LibraryPackageSet {
  const LibraryPackageSet({
    required this.folder,
    required this.library,
    this.index,
  });

  final PackageFolder folder;
  final LibraryPackage library;
  final LibraryPackage? index;

  String get version => library.version;
  int get compressedSize =>
      library.compressedSize + (index?.compressedSize ?? 0);
}

enum LibraryPackageProblem {
  /// חסר חלק, או שגודלו אינו כבמניפסט.
  incompleteParts,

  /// המניפסט אינו קריא או אינו מתאר את הארכיון.
  invalidManifest,

  /// יש אינדקס אבל לא ספרייה מאותה גרסה.
  indexWithoutLibrary,

  /// קובץ מופיע בשתי תיקיות כרכים בגדלים שונים.
  conflictingParts,
}

/// תוצאת סריקת תיקייה: [packages] כשנמצאה ספרייה שלמה, אחרת [problem]
/// כשנמצאו קובצי מסייע שאי אפשר לייבא. שניהם null — אין קובצי מסייע.
class LibraryPackageScan {
  const LibraryPackageScan({this.packages, this.problem, this.problemFile});

  final LibraryPackageSet? packages;
  final LibraryPackageProblem? problem;

  /// הקובץ שבו נמצאה הבעיה (חלק חסר, מניפסט פגום).
  final String? problemFile;

  bool get isEmpty => packages == null && problem == null;
}

final _assetName = RegExp(
  r'^otzaria-(\d[0-9A-Za-z.+_]*(?:-[0-9A-Za-z.+_]+)*?)-(library|library-index)\.tar\.zst'
  r'(\.part-(\d{3,})|\.manifest\.json)?$',
);
final _sha256 = RegExp(r'^[0-9a-f]{64}$');

class _Group {
  _Group(this.version, this.kind);

  final String version;
  final LibraryPackageKind kind;
  PackageFileEntry? whole;
  PackageFileEntry? manifest;
  final parts = <int, PackageFileEntry>{};

  String get archiveName => 'otzaria-$version-${kind.assetSuffix}.tar.zst';
}

class _PackageError implements Exception {
  const _PackageError(this.problem, this.file);

  final LibraryPackageProblem problem;
  final String file;
}

/// מזהה בתיקייה את קובצי הספרייה והאינדקס שהמסייע הכין: חלקים
/// (`.part-NNN`, עם מניפסט או בלעדיו) או ארכיון שהורכב לקובץ אחד.
/// בכמה גרסאות — הגבוהה ביותר; אינדקס נבחר רק מאותה גרסה של הספרייה.
Future<LibraryPackageScan> scanLibraryPackages(PackageFolder folder) async {
  final groups = <String, _Group>{};
  for (final entry in await folder.list()) {
    final match = _assetName.firstMatch(entry.name);
    if (match == null) continue;
    final version = match.group(1)!;
    final kind = match.group(2) == LibraryPackageKind.searchIndex.assetSuffix
        ? LibraryPackageKind.searchIndex
        : LibraryPackageKind.library;
    final group = groups.putIfAbsent(
      '$version|${kind.name}',
      () => _Group(version, kind),
    );
    final partNumber = match.group(4);
    if (partNumber != null) {
      group.parts[int.parse(partNumber)] = entry;
    } else if (match.group(3) != null) {
      group.manifest = entry;
    } else {
      group.whole = entry;
    }
  }
  if (groups.isEmpty) return const LibraryPackageScan();

  final libraries =
      groups.values.where((g) => g.kind == LibraryPackageKind.library).toList()
        ..sort((a, b) => compareReleaseVersions(b.version, a.version));
  if (libraries.isEmpty) {
    return LibraryPackageScan(
      problem: LibraryPackageProblem.indexWithoutLibrary,
      problemFile: groups.values.first.archiveName,
    );
  }
  final libraryGroup = libraries.first;
  final indexGroup =
      groups['${libraryGroup.version}|${LibraryPackageKind.searchIndex.name}'];
  try {
    return LibraryPackageScan(
      packages: LibraryPackageSet(
        folder: folder,
        library: await _buildPackage(folder, libraryGroup),
        index: indexGroup == null
            ? null
            : await _buildPackage(folder, indexGroup),
      ),
    );
  } on _PackageError catch (e) {
    return LibraryPackageScan(problem: e.problem, problemFile: e.file);
  }
}

Future<LibraryPackage> _buildPackage(PackageFolder folder, _Group group) async {
  final manifestEntry = group.manifest;
  if (manifestEntry != null) {
    return _fromManifest(folder, group, manifestEntry);
  }
  if (group.parts.isNotEmpty) {
    return LibraryPackage(
      kind: group.kind,
      version: group.version,
      archiveName: group.archiveName,
      parts: [
        for (final entry in _contiguousParts(group))
          LibraryPackagePart(entry: entry),
      ],
    );
  }
  return LibraryPackage(
    kind: group.kind,
    version: group.version,
    archiveName: group.archiveName,
    parts: [LibraryPackagePart(entry: group.whole!)],
  );
}

List<PackageFileEntry> _contiguousParts(_Group group) {
  final numbers = group.parts.keys.toList()..sort();
  for (var i = 0; i < numbers.length; i++) {
    if (numbers[i] != i) {
      throw _PackageError(
        LibraryPackageProblem.incompleteParts,
        '${group.archiveName}.part-${i.toString().padLeft(3, '0')}',
      );
    }
  }
  return [for (final n in numbers) group.parts[n]!];
}

/// מניפסט בצורת `split_release_asset.sh`. הארכיון השלם (אם הורכב) גובר
/// כשגודלו תואם, ואחרת כל החלקים חייבים להיות במקומם ובגודל הנכון.
Future<LibraryPackage> _fromManifest(
  PackageFolder folder,
  _Group group,
  PackageFileEntry manifestEntry,
) async {
  final invalid = _PackageError(
    LibraryPackageProblem.invalidManifest,
    manifestEntry.name,
  );
  final Object? json;
  try {
    final bytes = await folder
        .openRead(manifestEntry)
        .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw invalid;
  }
  if (json is! Map ||
      json['schemaVersion'] != 1 ||
      json['archive'] != group.archiveName ||
      json['size'] is! int ||
      json['sha256'] is! String ||
      !_sha256.hasMatch(json['sha256'] as String) ||
      json['parts'] is! List ||
      (json['parts'] as List).isEmpty) {
    throw invalid;
  }
  final sha256 = json['sha256'] as String;
  final whole = group.whole;
  if (whole != null && whole.size == json['size']) {
    return LibraryPackage(
      kind: group.kind,
      version: group.version,
      archiveName: group.archiveName,
      parts: [LibraryPackagePart(entry: whole)],
      sha256: sha256,
    );
  }
  final byName = {for (final e in group.parts.values) e.name: e};
  final parts = <LibraryPackagePart>[];
  for (final (i, part) in (json['parts'] as List).indexed) {
    final expectedName =
        '${group.archiveName}.part-${i.toString().padLeft(3, '0')}';
    if (part is! Map ||
        part['name'] != expectedName ||
        part['size'] is! int ||
        part['sha256'] is! String ||
        !_sha256.hasMatch(part['sha256'] as String)) {
      throw invalid;
    }
    final entry = byName[expectedName];
    if (entry == null || entry.size != part['size']) {
      throw _PackageError(LibraryPackageProblem.incompleteParts, expectedName);
    }
    parts.add(
      LibraryPackagePart(entry: entry, sha256: part['sha256'] as String),
    );
  }
  return LibraryPackage(
    kind: group.kind,
    version: group.version,
    archiveName: group.archiveName,
    parts: parts,
    sha256: sha256,
  );
}

/// השוואת גרסאות כמו `0.9.98` ו-`0.10.1+143`: מספר מול מספר, ואחר כך טקסט.
int compareReleaseVersions(String a, String b) {
  final pa = a.split(RegExp(r'[.+_-]'));
  final pb = b.split(RegExp(r'[.+_-]'));
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]);
    final nb = int.tryParse(pb[i]);
    final cmp = (na != null && nb != null)
        ? na.compareTo(nb)
        : pa[i].compareTo(pb[i]);
    if (cmp != 0) return cmp;
  }
  return pa.length.compareTo(pb.length);
}
