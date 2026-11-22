import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_extractor.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:path/path.dart' as p;

/// תוצאת התקנה של חבילה לא-מקוונת.
enum OfficialPackageResult {
  installed,
  alreadyInstalled,

  /// אינה חבילה קריאה: חלק חסר או פגום, מניפסט חלקים פגום, או tar בלי
  /// המניפסט והחתימה.
  notPackage,

  /// אין מניפסט חתום במפתח של מסד רשמי שהמסד שלו בחבילה.
  badSignature,

  /// המסד אינו תואם לגודל או ל-sha256 שבמניפסט.
  hashMismatch,
  olderVersion,
  noSpace,
  failed,
}

final _suffix = RegExp(r'\.(part-\d{3,}|manifest\.json)$');

/// שם הארכיון (`<name>.tar.zst`) מקובץ שהמשתמש בחר: חלק, מניפסט החלקים
/// או הארכיון השלם.
String offlineArchiveNameOf(String path) =>
    p.basename(path).replaceFirst(_suffix, '');

/// הקבצים של [archiveName] בתיקייה: חלקים, מניפסט חלקים וארכיון שלם.
Future<List<String>> offlinePackageFiles(
  String directory,
  String archiveName,
) async {
  final files = <String>[];
  try {
    await for (final entity in Directory(directory).list()) {
      final name = p.basename(entity.path);
      if (entity is File && offlineArchiveNameOf(name) == archiveName) {
        files.add(entity.path);
      }
    }
  } on FileSystemException {
    return const [];
  }
  return files;
}

/// פורס את [archiveName] שבתיקייה [directory] אל [destination] ב-isolate:
/// חלקים לפי הסדר עם אימות מניפסט החלקים, zstd ו-tar בזרם אחד — אותו קוד
/// של חבילות הספרייה. זורק [FormatException] כשהחבילה חסרה או פגומה.
Future<List<PackageFileEntry>> extractOfflinePackage(
  PackageFolder folder,
  String archiveName,
  String destination, {
  String? selectedName,
  DynamicLibrary Function() openZstd = openZstandardLib,
}) {
  final token = folder.usesPlatformChannel ? RootIsolateToken.instance : null;
  return Isolate.run(() async {
    if (token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }
    final package = await scanNamedArchive(
      folder,
      archiveName,
      selectedName: selectedName,
    );
    if (package == null) throw FormatException('missing $archiveName');
    await extractLibraryPackage(
      package: package,
      folder: folder,
      destination: destination,
      zstd: openZstd(),
      anyRoot: true,
    );
    return [
      for (final part in package.parts) part.entry,
      ?package.manifestEntry,
    ];
  });
}
