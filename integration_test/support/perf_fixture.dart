import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/models/tour_steps.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../test/helpers/seforim_fixture_db.dart';

const perfFixtureVersion = 'synthetic-v2';
const perfBooks = <String, int>{
  'מדידה קצרה': 128,
  'מדידה בינונית': 4096,
  'מדידה ארוכה': 65536,
};
const perfQuery = 'בדיקה ירוקה';
const perfPluginId = 'org.otzaria.perf-fixture';
const perfPluginHtml = '''<!doctype html><html lang="he" dir="rtl">
<meta charset="utf-8"><title>Performance fixture</title>
<style>body{font:20px sans-serif;background:#fff;color:#111}</style>
<h1>תוסף מדידה מקומי</h1><p id="ready">קלט קבוע לבדיקת תוסף</p>
<script>requestAnimationFrame(()=>requestAnimationFrame(()=>window.perfReady=true));</script>
</html>''';

String perfLine(int index) => index % 32 == 0
    ? '<h2>פרק מדידה ${index ~/ 32}</h2>'
    : 'שורה $index: בדיקה ${index.isEven ? 'ירוקה' : 'כחולה'} של טקסט קבוע, '
          'גלילה וחיפוש עם מספרים 0123456789 ואותיות ABC.';

Map<String, int> perfBooksWithLineCounts(String option) {
  if (option.isEmpty) return perfBooks;
  final counts = option
      .split(',')
      .map((part) => int.tryParse(part.trim()))
      .toList();
  if (counts.length != 3 ||
      counts.any((count) => count == null || count < 1 || count > 1000000) ||
      counts[0]! >= counts[1]! ||
      counts[1]! >= counts[2]!) {
    throw ArgumentError(
      'PERF_BOOK_LINES requires three increasing sizes in 1..1000000.',
    );
  }
  return Map<String, int>.fromIterables(perfBooks.keys, counts.cast<int>());
}

class PerfFixture {
  PerfFixture(this.root, {Map<String, int> books = perfBooks})
    : books = Map.unmodifiable(books);
  final Directory root;
  final Map<String, int> books;
  String get libraryPath => p.join(root.path, 'library');
  String get dbPath => p.join(libraryPath, 'seforim.db');
  String get pluginPath => p.join(root.path, 'fixture-plugin');
  String get appDataPath => p.join(root.path, 'app-data');
  late String id;

  Future<void> prepare({required bool preparationOnly}) async {
    if (!p.isAbsolute(root.path)) {
      throw ArgumentError('PERF_DATA_DIR must be absolute.');
    }
    if (await FileSystemEntity.isLink(root.path)) {
      throw StateError('Fixture root must not be a symlink.');
    }
    final marker = File(p.join(root.path, '.otzaria-perf-fixture'));
    await root.create(recursive: true);
    if (await marker.exists()) {
      final existing =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      if (preparationOnly ||
          existing['version'] != perfFixtureVersion ||
          jsonEncode(existing['books'] ?? perfBooks) != jsonEncode(books)) {
        throw StateError(
          'Preparation requires a new directory; measured runs require a matching fixture.',
        );
      }
      id = await _identity();
      if (existing['fixtureId'] != id) {
        throw StateError('The warm fixture changed since preparation.');
      }
    } else {
      if (!preparationOnly || !await root.list().isEmpty) {
        throw StateError(
          'Refusing to modify a nonempty or unprepared fixture directory.',
        );
      }
      await _create();
      id = await _identity();
      await Directory(appDataPath).create(recursive: true);
      await _seedSettings();
      await marker.writeAsString(
        jsonEncode({
          'version': perfFixtureVersion,
          'fixtureId': id,
          'books': books,
        }),
        flush: true,
      );
    }
    if (!await File(
      p.join(appDataPath, '${HiveCache.keyName}.hive'),
    ).exists()) {
      throw StateError('Prepared fixture settings are missing.');
    }
    AppPaths.configureDataRootPathForProcess(appDataPath);
    AppPaths.debugOverrideDocumentsRootPath(p.join(root.path, 'documents'));
  }

  Future<String> _identity() async {
    final hashes = <String>[
      for (final path in [
        dbPath,
        p.join(libraryPath, 'lexical.db'),
        p.join(pluginPath, 'index.html'),
      ])
        (await sha256.bind(File(path).openRead()).first).toString(),
    ];
    return '$perfFixtureVersion:${sha256.convert(utf8.encode(hashes.join(':')))}';
  }

  Future<void> _create() async {
    final library = await Directory(libraryPath).create(recursive: true);
    final source = SeforimFixtureDb.create(library, SeforimFixtureVariant.full);
    final db = sqlite3.open(source);
    try {
      db.execute('BEGIN');
      for (final row in db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )) {
        final name = row['name'] as String;
        db.execute('DELETE FROM "$name"');
      }
      db.execute(
        "INSERT INTO category (id,title,level,orderIndex) VALUES (1,'מדידות',0,0)",
      );
      db.execute('INSERT INTO category_closure VALUES (1,1)');
      db.execute("INSERT INTO source VALUES (1,'synthetic')");
      final book = db.prepare(
        'INSERT INTO book (id,categoryId,sourceId,title,totalLines,orderIndex) VALUES (?,1,1,?,?,?)',
      );
      final line = db.prepare(
        'INSERT INTO line (id,bookId,lineIndex,content,charCount) VALUES (?,?,?,?,?)',
      );
      try {
        var bookId = 0, lineId = 0;
        for (final entry in books.entries) {
          bookId++;
          book.execute([bookId, entry.key, entry.value, bookId]);
          for (var index = 0; index < entry.value; index++) {
            final content = perfLine(index);
            line.execute([++lineId, bookId, index, content, content.length]);
          }
        }
      } finally {
        book.close();
        line.close();
      }
      db.execute('COMMIT');
      db.execute('VACUUM');
    } finally {
      db.close();
    }
    await File(source).rename(dbPath);
    final lexical = sqlite3.open(p.join(libraryPath, 'lexical.db'));
    try {
      lexical.execute('''
        CREATE TABLE base (id INTEGER PRIMARY KEY, value TEXT NOT NULL UNIQUE);
        CREATE TABLE surface (id INTEGER PRIMARY KEY, value TEXT NOT NULL UNIQUE, base_id INTEGER NOT NULL, notes TEXT);
        CREATE TABLE variant (id INTEGER PRIMARY KEY, value TEXT NOT NULL UNIQUE);
        CREATE TABLE surface_variant (surface_id INTEGER NOT NULL, variant_id INTEGER NOT NULL, PRIMARY KEY(surface_id,variant_id));
      ''');
    } finally {
      lexical.close();
    }
    await Directory(pluginPath).create();
    await File(p.join(pluginPath, 'index.html')).writeAsString(perfPluginHtml);
  }

  Future<void> _seedSettings() async {
    final settings = await Hive.openBox<dynamic>(
      HiveCache.keyName,
      path: appDataPath,
    );
    try {
      await settings.putAll({
        'settings_initialized': true,
        SettingsRepository.keyLibraryPath: libraryPath,
        SettingsRepository.keyLibraryFolderName: '',
        SettingsRepository.keyIndexPath: p.join(root.path, 'index'),
        SettingsRepository.keyDatabasesPath: p.join(root.path, 'databases'),
        SettingsRepository.keyBackupPath: p.join(root.path, 'backups'),
        SettingsRepository.keyOfflineMode: true,
        SettingsRepository.keyAutoUpdateIndex: false,
        SettingsRepository.keyIndexUpdateMode: 'off',
        SettingsRepository.keySoftwareAndBookUpdatesEnabled: false,
        SettingsRepository.keyAutoSync: false,
        SettingsRepository.keyRestoreAllWindows: false,
        SettingsRepository.keyIsFullscreen: false,
        SettingsRepository.keyAppCrashReportMode: 'never',
        SettingsRepository.keyShowExternalBooks: false,
        SettingsRepository.keyShowLocalHebrewBooks: false,
        SettingsRepository.keyFontFamily: 'NotoSerifHebrew',
        SettingsRepository.keyFontSize: 22.0,
        SettingsRepository.keyDefaultSidebarOpen: false,
        SettingsRepository.keyDefaultCommentaryOpen: false,
        SettingsRepository.keyFollowSystemTheme: false,
        SettingsRepository.keyDarkMode: false,
        'key-auto-backup-frequency': 'none',
        TourSteps.statusKey: TourSteps.completed,
        // Non-debug builds otherwise open the ad dialog 5 s into every launch.
        'ad_popup_dont_show_again': true,
        LiveTipStorage.resolvedTipsKey: LiveTipStorage.encode(
          LiveTipId.values.toSet(),
        ),
        'window_bounds_left': 40.0,
        'window_bounds_top': 40.0,
        'window_bounds_width': 1280.0,
        'window_bounds_height': 720.0,
        'window_is_maximized': false,
      });
    } finally {
      await settings.close();
    }
  }
}
