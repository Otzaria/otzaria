import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/external_catalog/responsa/responsa_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

String _createCatalog(Directory directory) {
  final file = path.join(directory.path, 'responsa_catalog.db');
  final db = sqlite3.open(file);
  db.execute('''
    CREATE TABLE books (
      book_pk        INTEGER PRIMARY KEY,
      external_key   TEXT NOT NULL UNIQUE,
      title          TEXT NOT NULL,
      norm_title     TEXT NOT NULL,
      ref_path       TEXT NOT NULL,
      open_ref       TEXT NOT NULL,
      volume         TEXT,
      category       TEXT,
      topics         TEXT,
      tree_param     INTEGER,
      source_version INTEGER NOT NULL
    )
  ''');
  db.execute(
    'CREATE TABLE db_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  );
  db.execute(
    'INSERT INTO books(external_key, title, norm_title, ref_path, open_ref,'
    ' source_version) VALUES(?, ?, ?, ?, ?, ?)',
    ['1524', 'יבמות', 'יבמות', 'מפרשים > רא"ש > יבמות', 'רא"ש יבמות', 25],
  );
  db.close();
  return file;
}

ExternalLibraryBook _responsaBook({String id = 'rp:1524'}) =>
    ExternalLibraryBook(
      title: 'יבמות',
      id: 1524,
      link: null,
      externalLibraryId: id,
    );

/// בקר מדומה — הבדיקות אינן נוגעות בתוכנה אמיתית.
class _FakeController implements ResponsaController {
  _FakeController(this._report);

  final ResponsaOpenReport _report;
  final List<({String openRef, String? expectedTitle, int? siman})> calls = [];
  bool cancelled = false;

  @override
  bool get autoStart => true;

  @override
  bool get isBusy => false;

  @override
  void cancel() => cancelled = true;

  @override
  Future<ResponsaStatus> status() async => const ResponsaStatus(
    installed: true,
    running: true,
    confidence: ResponsaVersionConfidence.verified,
  );

  @override
  Future<ResponsaOpenReport> openBook(
    String openRef, {
    String? expectedTitle,
    int? siman,
  }) async {
    calls.add((openRef: openRef, expectedTitle: expectedTitle, siman: siman));
    return _report;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ResponsaCatalogRepository catalog;

  ({ResponsaLibraryProvider provider, _FakeController controller}) build(
    ResponsaOpenReport report,
  ) {
    final controller = _FakeController(report);
    return (
      provider: ResponsaLibraryProvider(
        catalog: catalog,
        controller: controller,
      ),
      controller: controller,
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-responsa-p-');
    catalog = ResponsaCatalogRepository()
      ..databasePathOverride = _createCatalog(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  const success = ResponsaOpenReport(ok: true, window: 'רא"ש מסכת יבמות פרק א');

  group('זהות הספק', () {
    test('מזהה, תחילית ויכולות', () {
      final provider = build(success).provider;

      expect(provider.id, 'responsa');
      expect(provider.idPrefix, 'rp');
      expect(provider.capabilities.webOpen, isFalse);
      expect(provider.capabilities.localOpen, isTrue);
      expect(provider.capabilities.inBookSearch, isFalse);
      expect(provider.descriptor, ExternalProviderRegistry.responsa);
    });
  });

  group('canOpen', () {
    test('ספר שבקטלוג — כן', () async {
      expect(await build(success).provider.canOpen(_responsaBook()), isTrue);
    });

    test('ספר של ספק אחר — לא', () async {
      expect(
        await build(success).provider.canOpen(_responsaBook(id: 'oh:1524')),
        isFalse,
      );
    });

    test('ספר שאינו בקטלוג — לא', () async {
      expect(
        await build(success).provider.canOpen(_responsaBook(id: 'rp:99999')),
        isFalse,
      );
    });
  });

  group('פתיחה — מטריצת המצבים', () {
    test('הצלחה, וההפניה שנשלחת היא ה-open_ref ולא הכותרת', () async {
      final built = build(success);

      final result = await built.provider.openBook(_responsaBook());

      expect(result.ok, isTrue);
      expect(built.controller.calls.single.openRef, 'רא"ש יבמות');
      expect(built.controller.calls.single.expectedTitle, 'יבמות');
    });

    test('ספר שאינו בקטלוג — כשל מסודר בלי לגעת בתוכנה', () async {
      final built = build(success);

      final result = await built.provider.openBook(
        _responsaBook(id: 'rp:99999'),
      );

      expect(result.errorCode, 'notInCatalog');
      expect(built.controller.calls, isEmpty);
    });

    test('ספר של ספק אחר נדחה', () async {
      final result = await build(
        success,
      ).provider.openBook(_responsaBook(id: 'hb:5'));

      expect(result.errorCode, 'notAResponsaBook');
    });

    test('התוכנה אינה מותקנת', () async {
      final result = await build(
        const ResponsaOpenReport(
          ok: false,
          failure: ResponsaFailure.responsaNotRunning,
          message: 'פרויקט השו"ת אינו מותקן במחשב.',
        ),
      ).provider.openBook(_responsaBook());

      expect(result.errorCode, 'responsaNotRunning');
      expect(result.message, contains('אינו מותקן'));
    });

    test('הפניה שלא נותחה', () async {
      final result = await build(
        const ResponsaOpenReport(
          ok: false,
          failure: ResponsaFailure.referenceNotParsed,
        ),
      ).provider.openBook(_responsaBook());

      expect(result.ok, isFalse);
      expect(result.message, contains('לא זיהה'));
    });

    test('נפתח ספר שגוי — נחשב כשל, לא הצלחה', () async {
      final result = await build(
        const ResponsaOpenReport(
          ok: false,
          failure: ResponsaFailure.openedWrongBook,
        ),
      ).provider.openBook(_responsaBook());

      expect(result.ok, isFalse);
      expect(result.message, contains('ספר אחר'));
    });

    test('תקרת חלונות — הודעה שאומרת למשתמש מה לעשות', () async {
      final result = await build(
        const ResponsaOpenReport(
          ok: false,
          failure: ResponsaFailure.mdiWindowLimitReached,
        ),
      ).provider.openBook(_responsaBook());

      expect(result.message, contains('לסגור'));
    });

    test('ביטול', () async {
      final result = await build(
        const ResponsaOpenReport(ok: false, failure: ResponsaFailure.cancelled),
      ).provider.openBook(_responsaBook());

      expect(result.errorCode, 'cancelled');
    });

    test('פתיחה עם סימן מעבירה אותו הלאה', () async {
      final built = build(success);

      await built.provider.open(_responsaBook(), siman: 12);

      expect(built.controller.calls.single.siman, 12);
    });

    test('ביטול מגיע לבקר', () {
      final built = build(success);
      built.provider.cancel();
      expect(built.controller.cancelled, isTrue);
    });
  });

  group('loadBooksByIds', () {
    test('מסנן מזהים של ספקים אחרים', () async {
      final books = await build(
        success,
      ).provider.loadBooksByIds(['rp:1524', 'oh:1524', 'hb:1524']);

      expect(books, hasLength(1));
      expect(books.single.externalLibraryId, 'rp:1524');
    });

    test('קיום ברשומה הוא הזמינות — אין בדיקת קובץ', () async {
      final provider = build(success).provider;

      expect(await provider.loadBooksByIds(['1524']), hasLength(1));
      expect(await provider.loadBooksByIds(['404']), isEmpty);
    });
  });
}
