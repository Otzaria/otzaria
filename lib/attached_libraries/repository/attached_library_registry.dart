import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_store.dart';
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';

class _OpenLibrary {
  _OpenLibrary(this.path, this.repository);

  final String path;
  final SeforimRepository repository;
  DateTime lastUsed = DateTime.now();
}

/// החיבורים למסדים המצורפים: חיבור read-only מוקשח לכל מסד, נפתח בגישה
/// הראשונה ונסגר אחרי [idleTimeout] בלי שימוש — כדי לא לנעול את הקובץ.
///
/// הרשימה נטענת מ-[AttachedLibraryStore] בגישה הראשונה, ומוחלפת ב-[update].
class AttachedLibraryRegistry {
  AttachedLibraryRegistry({
    this._store = const AttachedLibraryStore(),
    this.idleTimeout = const Duration(minutes: 5),
  });

  /// ניתן להחלפה בבדיקות.
  static AttachedLibraryRegistry instance = AttachedLibraryRegistry();

  /// הפתיחה הראשונה ממתינה לו — main.dart מציב כאן את הצגת החלון, כך שכרטיסיה
  /// משוחזרת של ספר מצורף אינה פותחת קובץ (אולי בכונן רשת) לפני ההצגה.
  static Future<void> Function() startupGate = _noGate;
  static Future<void> _noGate() async {}

  /// בדיקת פתיחה ב-isolate לפני החיבור ב-main isolate: פתיחה של קובץ מת
  /// חוסמת את ה-thread, ו-timeout של Dart אינו עוזר שם.
  static Duration openTimeout = const Duration(seconds: 5);

  final AttachedLibraryStore _store;

  /// null — בלי סגירה אוטומטית.
  final Duration? idleTimeout;

  List<AttachedLibrary>? _libraries;
  final Map<String, _OpenLibrary> _open = {};
  final Map<String, Future<SeforimRepository?>> _opening = {};
  Timer? _idleTimer;

  /// כל המסדים הרשומים, לפי [AttachedLibrary.priority].
  List<AttachedLibrary> get libraries => _libraries ??= _load();

  /// הרשימה, או null כשהערך השמור פגום ולא הוחלף מאז ב-[update].
  List<AttachedLibrary>? get librariesIfKnown {
    final list = libraries;
    return _storeUnreadable ? null : list;
  }

  bool _storeUnreadable = false;

  List<AttachedLibrary> _load() {
    final loaded = _store.loadLibrariesOrNull();
    _storeUnreadable = loaded == null;
    return _sorted(loaded ?? const []);
  }

  /// המסדים שספריהם מוצגים בעץ הספרייה, לפי הסדר.
  List<AttachedLibrary> get visibleLibraries => [
    for (final library in libraries)
      if (library.isVisibleInLibrary) library,
  ];

  /// המסד התקין שה-slug שלו [slug].
  AttachedLibrary? libraryFor(String slug) => libraries
      .where((library) => library.isOk && library.slug == slug)
      .firstOrNull;

  /// נתיב הקובץ של מסד [source], או null כשאינו מסד מצורף רשום.
  String? pathFor(BookSource source) =>
      source is AttachedBookSource ? libraryFor(source.slug)?.path : null;

  /// מחליף את הרשימה. חיבור למסד שנתיבו או מצבו השתנה נסגר.
  void update(List<AttachedLibrary> libraries) {
    _libraries = _sorted(libraries);
    _storeUnreadable = false;
    AttachedFindRefWorker.instance.reset();
    for (final slug in _open.keys.toList()) {
      final library = libraryFor(slug);
      if (library == null || library.path != _open[slug]!.path) {
        _closeEntry(slug);
      }
    }
  }

  /// המאגר של מסד [slug], או null כשהמסד אינו תקין או שהקובץ אינו נגיש.
  Future<SeforimRepository?> repositoryFor(String slug) {
    final library = libraryFor(slug);
    if (library == null) return Future.value();
    final open = _open[slug];
    if (open != null && open.path == library.path) {
      open.lastUsed = DateTime.now();
      _scheduleIdleCheck();
      return Future.value(open.repository);
    }
    // גוף בלוק: callback שמחזיר את ה-Future שהוסר היה ממתין לעצמו לנצח.
    return _opening[slug] ??= _openLibrary(library).whenComplete(() {
      _opening.remove(slug);
    });
  }

  Future<SeforimRepository?> repositoryForSource(BookSource source) =>
      source is AttachedBookSource
      ? repositoryFor(source.slug)
      : Future.value();

  Future<SeforimRepository?> _openLibrary(AttachedLibrary library) async {
    await startupGate();
    if (!await _preflight(library)) return null;
    final database = MyDatabase.untrusted(
      library.path,
      immutable: library.immutable,
    );
    final repository = SeforimRepository(database);
    try {
      await repository.ensureInitialized();
      // ensureInitialized בולע כשלי קריאה — שאילתה מפורשת מאמתת שהקובץ נפתח.
      await database.capabilities;
    } catch (e) {
      debugPrint('[AttachedLibraryRegistry] open ${library.slug} failed: $e');
      database.retire();
      return null;
    }
    _closeEntry(library.slug);
    _open[library.slug] = _OpenLibrary(library.path, repository);
    _scheduleIdleCheck();
    return repository;
  }

  static Future<bool> _preflight(AttachedLibrary library) async {
    final path = library.path;
    final immutable = library.immutable;
    try {
      return await Isolate.run(() {
        if (!File(path).existsSync()) return false;
        final db = openUntrustedReadOnlyDatabase(path, immutable: immutable);
        try {
          db.select('PRAGMA schema_version');
          return true;
        } finally {
          db.close();
        }
      }).timeout(openTimeout, onTimeout: () => false);
    } catch (e) {
      debugPrint('[AttachedLibraryRegistry] preflight $path failed: $e');
      return false;
    }
  }

  void _scheduleIdleCheck() {
    final timeout = idleTimeout;
    if (timeout == null || _idleTimer != null) return;
    _idleTimer = Timer.periodic(timeout ~/ 2, (_) => closeIdle());
  }

  /// סוגר חיבורים שלא נוגעו בהם [idleTimeout]. המאגר נשאר רשום, והחיבור
  /// ייפתח מחדש בשאילתה הבאה.
  @visibleForTesting
  void closeIdle({DateTime? now}) {
    final timeout = idleTimeout;
    if (timeout == null) return;
    final cutoff = (now ?? DateTime.now()).subtract(timeout);
    for (final entry in _open.values) {
      if (entry.lastUsed.isBefore(cutoff) && entry.repository.database.isOpen) {
        entry.repository.database.close();
      }
    }
    if (_open.values.every((e) => !e.repository.database.isOpen)) {
      _idleTimer?.cancel();
      _idleTimer = null;
    }
  }

  /// משחרר את הקובץ של [slug] — החיבור נסגר ונשכח. גישה הבאה פותחת מחדש.
  Future<void> close(String slug) async {
    AttachedFindRefWorker.instance.reset();
    _closeEntry(slug);
  }

  /// סוגר את כל החיבורים (איפוס runtime, יציאה).
  Future<void> closeAll() async {
    AttachedFindRefWorker.instance.reset();
    for (final slug in _open.keys.toList()) {
      _closeEntry(slug);
    }
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// סוגר הכל ושוכח את הרשימה — הגישה הבאה קוראת אותה מחדש מההגדרות.
  Future<void> reset() async {
    await closeAll();
    _libraries = null;
  }

  /// המאגרים שהחיבור שלהם פתוח כרגע — בלי לפתוח מסד שעדיין סגור.
  List<SeforimRepository> get openRepositories => [
    for (final entry in _open.values)
      if (entry.repository.database.isOpen) entry.repository,
  ];

  @visibleForTesting
  bool isOpen(String slug) => _open[slug]?.repository.database.isOpen ?? false;

  void _closeEntry(String slug) {
    final entry = _open.remove(slug);
    entry?.repository.database.retire();
  }

  static List<AttachedLibrary> _sorted(List<AttachedLibrary> libraries) =>
      [...libraries]..sort((a, b) => a.priority.compareTo(b.priority));
}
