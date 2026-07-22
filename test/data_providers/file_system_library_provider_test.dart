import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileSystemLibraryProvider bundled talmud bavli', () {
    late Directory tempDir;

    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      tempDir = await Directory.systemTemp.createTemp('otzaria_fs_provider_');
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        tempDir.path,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        DatabaseConstants.otzariaFolderName,
      );
      FileSystemLibraryProvider.instance.resetForTesting();
    });

    tearDown(() async {
      FileSystemLibraryProvider.instance.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'loads Brakhot PDF from bundled talmud bavli folder at library root',
      () async {
        final talmudDir = Directory(
          path.join(
            tempDir.path,
            DatabaseConstants.talmudBavliFolderName,
          ),
        );
        await talmudDir.create(recursive: true);

        final pdfPath = path.join(talmudDir.path, 'ברכות.pdf');
        await File(pdfPath).writeAsBytes(const [37, 80, 68, 70]);

        final provider = FileSystemLibraryProvider.instance;
        await provider.initialize();

        final booksByCategory = await provider.loadBooks({});
        final talmudBooks =
            booksByCategory[DatabaseConstants.talmudBavliFolderName];

        expect(talmudBooks, isNotNull);
        expect(talmudBooks, hasLength(1));
        expect(talmudBooks!.single, isA<PdfBook>());
        expect(talmudBooks.single.title, 'ברכות');

        final keyToPath = await provider.keyToPath;
        final storageKey = BookCompositeKey.create(
          title: 'ברכות',
          categoryId: DatabaseConstants.talmudBavliFolderName.hashCode,
          fileType: 'pdf',
        ).toStorageKey();

        expect(keyToPath[storageKey], pdfPath);
      },
    );

    test('מסווג TXT, DOCX ו-EPUB תאומים כסוגים נפרדים', () async {
      final personalDir = Directory(path.join(tempDir.path, 'אוצריא', 'אישי'));
      await personalDir.create(recursive: true);
      final txtPath = path.join(personalDir.path, 'ספר.txt');
      final docxPath = path.join(personalDir.path, 'ספר.docx');
      final epubPath = path.join(personalDir.path, 'ספר.epub');
      await File(txtPath).writeAsString('טקסט');
      await File(docxPath).writeAsBytes(const [1]);
      await File(epubPath).writeAsBytes(const [2]);

      final provider = FileSystemLibraryProvider.instance;
      await provider.initialize();
      final books = (await provider.loadBooks({}))['ספרים אישיים']!;

      expect(books.whereType<TextBook>().single.fileType, 'txt');
      expect(books.whereType<DocxBook>().single.fileType, 'docx');
      expect(books.whereType<EpubBook>().single.fileType, 'epub');
      expect(books.whereType<EpubBook>().single.path, epubPath);

      final categoryId = 'ספרים אישיים'.hashCode;
      final keyToPath = await provider.keyToPath;
      for (final entry in {
        'txt': txtPath,
        'docx': docxPath,
        'epub': epubPath,
      }.entries) {
        final key = BookCompositeKey.create(
          title: 'ספר',
          categoryId: categoryId,
          fileType: entry.key,
        ).toStorageKey();
        expect(keyToPath[key], entry.value);
      }
    });
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
