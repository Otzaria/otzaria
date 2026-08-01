import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;

class ReleaseIndexBuilderCliExitCode {
  static const int success = 0;
  static const int buildFailed = 1;
  static const int usageError = 64;
}

/// הגדרות בניית אינדקס הספרייה עבור חבילת ההפצה המלאה.
class ReleaseIndexBuilderConfig {
  final String libraryPath;
  final String indexPath;
  final String dataPath;

  const ReleaseIndexBuilderConfig({
    required this.libraryPath,
    required this.indexPath,
    required this.dataPath,
  });
}

typedef ReleaseIndexBuild =
    Future<void> Function(
      ReleaseIndexBuilderConfig config,
      void Function(String message) log,
    );

/// פקודת headless שבונה אינדקס Tantivy מאותו DB ואותו מנוע של האפליקציה.
class ReleaseIndexBuilderCli {
  static Future<int> run(
    List<String> args, {
    StringSink? out,
    StringSink? err,
    ReleaseIndexBuild? build,
  }) async {
    final outSink = out ?? stdout;
    final errSink = err ?? stderr;
    final parsed = _parse(args, errSink);
    if (parsed == null) return ReleaseIndexBuilderCliExitCode.usageError;
    if (parsed == _helpConfig) {
      printUsage(outSink);
      return ReleaseIndexBuilderCliExitCode.success;
    }

    try {
      await (build ?? _buildIndex)(parsed, outSink.writeln);
      outSink.writeln('אינדקס ההפצה נבנה בהצלחה: ${parsed.indexPath}');
      return ReleaseIndexBuilderCliExitCode.success;
    } catch (error, stackTrace) {
      errSink.writeln('בניית אינדקס ההפצה נכשלה: $error');
      errSink.writeln(stackTrace);
      return ReleaseIndexBuilderCliExitCode.buildFailed;
    }
  }

  static const _helpConfig = ReleaseIndexBuilderConfig(
    libraryPath: '',
    indexPath: '',
    dataPath: '',
  );

  static ReleaseIndexBuilderConfig? _parse(
    List<String> args,
    StringSink err,
  ) {
    String? libraryPath;
    String? indexPath;
    String? dataPath;

    for (var i = 0; i < args.length; i++) {
      final argument = args[i];
      if (argument == '--help' || argument == '-h') return _helpConfig;

      String? value;
      if (argument == '--library' ||
          argument == '--index' ||
          argument == '--data') {
        if (i + 1 >= args.length) {
          err.writeln('שגיאה: ל-$argument חסר נתיב.');
          printUsage(err);
          return null;
        }
        value = args[++i];
      }

      if (argument == '--library') {
        libraryPath = value;
      } else if (argument == '--index') {
        indexPath = value;
      } else if (argument == '--data') {
        dataPath = value;
      } else if (argument.startsWith('--library=')) {
        libraryPath = argument.substring('--library='.length);
      } else if (argument.startsWith('--index=')) {
        indexPath = argument.substring('--index='.length);
      } else if (argument.startsWith('--data=')) {
        dataPath = argument.substring('--data='.length);
      } else if (value == null) {
        err.writeln('שגיאה: ארגומנט לא מוכר: $argument');
        printUsage(err);
        return null;
      }
    }

    if ([libraryPath, indexPath, dataPath].any((value) => value == null)) {
      err.writeln('שגיאה: חובה לציין --library, --index ו---data.');
      printUsage(err);
      return null;
    }

    return ReleaseIndexBuilderConfig(
      libraryPath: p.absolute(libraryPath!),
      indexPath: p.absolute(indexPath!),
      dataPath: p.absolute(dataPath!),
    );
  }

  static Future<void> _buildIndex(
    ReleaseIndexBuilderConfig config,
    void Function(String message) log,
  ) async {
    final libraryDirectory = Directory(config.libraryPath);
    final database = File(
      p.join(config.libraryPath, DatabaseConstants.databaseFileName),
    );
    if (!libraryDirectory.existsSync() || !database.existsSync()) {
      throw StateError('לא נמצא מסד ספרייה ב-${database.path}');
    }

    final indexDirectory = Directory(config.indexPath);
    if (indexDirectory.existsSync() && indexDirectory.listSync().isNotEmpty) {
      throw StateError('תיקיית האינדקס חייבת להיות ריקה: ${config.indexPath}');
    }
    indexDirectory.createSync(recursive: true);
    Directory(config.dataPath).createSync(recursive: true);

    WidgetsFlutterBinding.ensureInitialized();
    AppPaths.configureDataRootPathForProcess(config.dataPath);
    await Settings.init(
      cacheProvider: _MemoryCacheProvider({
        SettingsRepository.keyLibraryPath: config.libraryPath,
        SettingsRepository.keyLibraryFolderName: '',
        SettingsRepository.keyIndexPath: config.indexPath,
        SettingsRepository.keyDatabasesPath: p.join(
          config.dataPath,
          'databases',
        ),
      }),
    );
    await RustLib.init();

    final libraryProvider = DatabaseLibraryProvider.instance;
    await libraryProvider.initialize();
    final library = await libraryProvider.buildLibraryCatalog(
      const {},
      config.libraryPath,
    );
    final books = library
        .getAllBooks()
        .where((book) => book is! PdfBook)
        .toList();
    if (books.isEmpty) {
      throw StateError('מסד הספרייה אינו מכיל ספרים לאינדוקס');
    }

    log('נמצאו ${books.length} ספרים; מתחיל אינדוקס...');
    var lastReported = 0;
    final repository = IndexingRepository(TantivyDataProvider.instance);
    final completed = await repository.indexAllBooks(
      library,
      onProgress: (processed, total) {
        if (processed == total || processed - lastReported >= 100) {
          lastReported = processed;
          log('התקדמות אינדוקס: $processed/$total');
        }
      },
      includePdfBooks: false,
    );
    if (!completed) {
      throw StateError('האינדוקס בוטל או לא הושלם');
    }
    if (books.any(
      (book) =>
          IndexingRepository.isIndexableBook(book) &&
          !repository.isBookIndexed(book),
    )) {
      throw StateError('האינדקס נוצר, אך חסרים בו ספרים הניתנים לאינדוקס');
    }
  }

  static void printUsage(StringSink out) {
    out.writeln(
      'שימוש: otzaria build-release-index '
      '--library <dir> --index <dir> --data <dir>\n'
      '\n'
      'בונה אינדקס חיפוש להפצה מתוך seforim.db שבתיקיית הספרייה.',
    );
  }
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values;

  _MemoryCacheProvider(Map<String, Object?> values) : _values = Map.of(values);

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

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
  Set getKeys() => _values.keys.toSet();

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    return value is T ? value : defaultValue;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}
