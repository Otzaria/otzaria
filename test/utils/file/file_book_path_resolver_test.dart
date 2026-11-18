import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/file_book_path_resolver.dart';
import 'package:path/path.dart' as p;

import '../../helpers/memory_settings_cache.dart';

void main() {
  late Directory tempDir;
  late String activeLibrary;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tempDir = await Directory.systemTemp.createTemp('otzaria_resolver');
    activeLibrary = p.join(tempDir.path, 'new', 'books');
    await Directory(activeLibrary).create(recursive: true);
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      activeLibrary,
    );
  });

  tearDown(() => tempDir.delete(recursive: true));

  test('הגרסה האסינכרונית מוצאת ספר שהספרייה שלו הועברה', () async {
    final activePath = p.join(activeLibrary, 'ב.pdf');
    await File(activePath).writeAsBytes([1]);
    final stalePath = p.join(tempDir.path, 'old', 'books', 'ב.pdf');

    expect(await resolveMovedFileBookPathAsync(stalePath), activePath);
    expect(resolveMovedFileBookPath(stalePath), activePath);
  });

  test('קובץ קיים או חסר נשאר בנתיב שלו', () async {
    final existing = p.join(tempDir.path, 'א.pdf');
    await File(existing).writeAsBytes([1]);
    final missing = p.join(tempDir.path, 'old', 'books', 'ג.pdf');

    expect(await resolveMovedFileBookPathAsync(existing), existing);
    expect(await resolveMovedFileBookPathAsync(missing), missing);
  });
}
