import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:otzaria/utils/file/zip_entry_io.dart';
import 'package:path/path.dart' as p;

/// Extracts a plugin package without buffering the compressed archive or
/// individual decompressed files in memory. Run from a worker isolate, since
/// ZIP directory parsing and some codecs can still use synchronous CPU work.
Future<void> extractPluginArchive(
  String archivePath,
  String tempDirPath,
) async {
  final root = p.normalize(p.absolute(tempDirPath));
  final input = openZipInput(archivePath);
  try {
    final archive = ZipDecoder().decodeStream(input, throwOnError: true);

    for (final entry in archive) {
      final relativePath = p.normalize(entry.name);
      final targetPath = p.normalize(p.join(root, relativePath));
      // ב-Windows isWithin מתעלם מרישיות גם בתיקיות שרגישות לה.
      if (p.isAbsolute(relativePath) ||
          p.split(relativePath).first == '..' ||
          !p.isWithin(root, targetPath)) {
        throw FormatException(
          'נתיב חולץ מקובץ ZIP באופן לא חוקי: ${entry.name}',
        );
      }

      if (entry.isFile) {
        // Unpack in bounded chunks. readBytes()/content would allocate an
        // entire plugin asset, often in addition to the compressed archive.
        final written = await writeZipEntry(entry, targetPath);
        if (written != entry.size) {
          await File(targetPath).delete();
          throw ArchiveException(
            'ZIP entry ${entry.name} declared ${entry.size} bytes '
            'but extracted $written bytes',
          );
        }
      } else {
        await Directory(targetPath).create(recursive: true);
      }
    }
  } finally {
    await input.close();
  }
}
