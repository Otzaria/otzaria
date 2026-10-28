import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:otzaria/utils/file/zip_entry_io.dart';
import 'package:path/path.dart' as p;
import 'package:posix/posix.dart' as posix;

/// מחלץ ארכיון (zip/tar) מ-[archivePath] אל [outputDir] ב-isolate נפרד.
Future<void> extractArchiveFileToDisk(String archivePath, String outputDir) =>
    Isolate.run(() async {
      if (!archivePath.toLowerCase().endsWith('.zip')) {
        await extractFileToDisk(archivePath, outputDir);
        return;
      }

      final input = openZipInput(archivePath);
      try {
        final archive = ZipDecoder().decodeStream(input);
        final links = Archive();
        final root = p.canonicalize(outputDir);
        final setPermissions = _supportsPermissions();
        await Directory(outputDir).create(recursive: true);
        for (final entry in archive) {
          final dest = p.join(outputDir, p.normalize(entry.name));
          if (!p.isWithin(root, p.canonicalize(dest))) continue;
          if (entry.isSymbolicLink) {
            links.add(entry);
          } else if (entry.isDirectory) {
            await Directory(dest).create(recursive: true);
          } else {
            await writeZipEntry(entry, dest);
            if (setPermissions) {
              posix.chmod(dest, entry.unixPermissions.toRadixString(8));
            }
          }
        }
        // קישורים נוצרים רק אחרי הקבצים, עם בדיקות הנתיבים של archive.
        await extractArchiveToDisk(links, outputDir);
      } finally {
        await input.close();
      }
    });

bool _supportsPermissions() {
  try {
    return (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) &&
        posix.isPosixSupported;
  } catch (_) {
    // טעינת libc אינה זמינה בכל מערכת, כמו בבדיקת התמיכה של archive.
    return false;
  }
}
