import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/responsa_bridge_client.dart';
import 'package:otzaria/external_catalog/responsa/responsa_bridge_launcher.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/external_catalog/responsa/responsa_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

const _endpoint = ResponsaBridgeEndpoint(
  port: 39627,
  token: 't',
  pid: 1,
  bridgeVersion: 1,
);

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
    " source_version) VALUES('1524', 'יבמות', 'יבמות',"
    " 'מפרשים > רא\"ש > יבמות', 'רא\"ש יבמות', 25)",
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

http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ResponsaCatalogRepository catalog;

  /// בונה ספק עם גשר מדומה. [bridgeInstalled] false = רכיב החיבור חסר.
  ({ResponsaLibraryProvider provider, List<Uri> calls}) build({
    required Future<http.Response> Function(http.Request request) respond,
    bool bridgeEnabled = true,
    bool bridgeInstalled = true,
    bool bridgeRunning = true,
  }) {
    final calls = <Uri>[];
    final client = ResponsaBridgeClient(
      httpClient: MockClient((request) {
        calls.add(request.url);
        return respond(request);
      }),
    );
    if (bridgeRunning) client.endpointOverride = _endpoint;

    final launcher = ResponsaBridgeLauncher(client: client)
      ..executablePathOverride = bridgeInstalled
          ? path.join(tempDir.path, 'responsa_bridge.exe')
          : path.join(tempDir.path, 'missing.exe');
    if (bridgeInstalled) {
      File(launcher.executablePathOverride!).writeAsStringSync('stub');
    }

    return (
      provider: ResponsaLibraryProvider(
        catalog: catalog,
        bridge: client,
        launcher: launcher,
        bridgeEnabled: () => bridgeEnabled,
      ),
      calls: calls,
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

  group('זהות הספק', () {
    test('מזהה, תחילית ויכולות', () {
      final provider = build(
        respond: (_) async => _json({'ok': true}),
      ).provider;

      expect(provider.id, 'responsa');
      expect(provider.idPrefix, 'rp');
      expect(provider.displayName, 'פרויקט השו"ת');
      expect(provider.capabilities.webOpen, isFalse);
      expect(provider.capabilities.localOpen, isTrue);
      expect(provider.capabilities.inBookSearch, isFalse);
      expect(provider.descriptor, ExternalProviderRegistry.responsa);
    });
  });

  group('canOpen', () {
    test('ספר שבקטלוג — כן', () async {
      final provider = build(
        respond: (_) async => _json({'ok': true}),
      ).provider;
      expect(await provider.canOpen(_responsaBook()), isTrue);
    });

    test('ספר של ספק אחר — לא', () async {
      final provider = build(
        respond: (_) async => _json({'ok': true}),
      ).provider;
      expect(await provider.canOpen(_responsaBook(id: 'oh:1524')), isFalse);
    });

    test('ספר שאינו בקטלוג — לא', () async {
      final provider = build(
        respond: (_) async => _json({'ok': true}),
      ).provider;
      expect(await provider.canOpen(_responsaBook(id: 'rp:99999')), isFalse);
    });
  });

  group('פתיחה — מטריצת המצבים', () {
    test('הצלחה', () async {
      final built = build(
        respond: (_) async =>
            _json({'ok': true, 'window': 'רא"ש מסכת יבמות פרק א'}),
      );

      final result = await built.provider.openBook(_responsaBook());
      expect(result.ok, isTrue);
      // תחילה נבדק שהגשר חי, ורק אז נשלחת הפתיחה.
      expect(
        built.calls.map((u) => u.path),
        containsAllInOrder(['/api/status', '/api/openBook']),
      );
    });

    test('ספר שאינו בקטלוג — כשל מסודר בלי לפנות לגשר', () async {
      final built = build(respond: (_) async => _json({'ok': true}));

      final result = await built.provider.openBook(
        _responsaBook(id: 'rp:99999'),
      );
      expect(result.ok, isFalse);
      expect(result.errorCode, 'notInCatalog');
      expect(built.calls, isEmpty);
    });

    test('ספר של ספק אחר נדחה', () async {
      final provider = build(
        respond: (_) async => _json({'ok': true}),
      ).provider;

      final result = await provider.openBook(_responsaBook(id: 'hb:5'));
      expect(result.errorCode, 'notAResponsaBook');
    });

    test('הגשר כבוי בהגדרות ואינו רץ — לא מנסים להפעיל', () async {
      final built = build(
        respond: (_) async => _json({'ok': true}),
        bridgeEnabled: false,
        bridgeRunning: false,
      );

      final result = await built.provider.openBook(_responsaBook());
      expect(result.errorCode, 'bridgeDisabled');
      expect(result.message, contains('כבויה'));
    });

    test('רכיב החיבור אינו מותקן', () async {
      final built = build(
        respond: (_) async => _json({'ok': true}),
        bridgeInstalled: false,
        bridgeRunning: false,
      );

      final result = await built.provider.openBook(_responsaBook());
      expect(result.errorCode, 'bridgeNotInstalled');
    });

    test('הפניה שלא נותחה מוחזרת כהודעה למשתמש', () async {
      final built = build(
        respond: (_) async => _json({
          'ok': false,
          'error': 'referenceNotParsed',
        }),
      );

      final result = await built.provider.openBook(_responsaBook());
      expect(result.ok, isFalse);
      expect(result.errorCode, 'referenceNotParsed');
      expect(result.message, contains('לא זיהה'));
    });

    test('נפתח ספר שגוי — נחשב כשל, לא הצלחה', () async {
      final built = build(
        respond: (_) async => _json({'ok': false, 'error': 'openedWrongBook'}),
      );

      final result = await built.provider.openBook(_responsaBook());
      expect(result.ok, isFalse);
      expect(result.message, contains('ספר אחר'));
    });

    test('הגשר נופל באמצע הפתיחה — כשל נקי, בלי חריג', () async {
      // הבדיקה שהגשר חי עוברת, והנפילה קורית רק בפתיחה עצמה.
      final built = build(
        respond: (request) async {
          if (request.url.path == '/api/status') {
            return _json({'ok': true, 'supported': true});
          }
          throw const SocketException('gone');
        },
      );

      final result = await built.provider.openBook(_responsaBook());
      expect(result.ok, isFalse);
      expect(result.errorCode, 'bridgeUnavailable');
    });

    test('גשר שהפסיק לענות — מנסים להפעיל מחדש ומדווחים על הכשל', () async {
      final built = build(
        respond: (_) async => throw const SocketException('gone'),
      );

      final result = await built.provider.openBook(_responsaBook());
      expect(result.ok, isFalse);
      expect(result.errorCode, 'bridgeLaunchFailed');
    });

    test('גרסה שאינה נתמכת מוחזרת בשמה', () async {
      final built = build(
        respond: (_) async => _json({
          'ok': false,
          'error': 'unsupportedResponsaVersion',
        }),
      );

      final result = await built.provider.openBook(_responsaBook());
      expect(result.message, contains('אינה נתמכת'));
    });

    test('פתיחה עם סימן פונה גם ל-gotoSiman', () async {
      final built = build(
        respond: (request) async => _json({
          'ok': true,
          'window': 'רא"ש מסכת יבמות סימן ב',
        }),
      );

      final result = await built.provider.open(_responsaBook(), siman: 2);
      expect(result.ok, isTrue);
      expect(
        built.calls.map((u) => u.path),
        containsAllInOrder(['/api/openBook', '/api/gotoSiman']),
      );
    });
  });

  group('loadBooksByIds', () {
    test('מסנן מזהים של ספקים אחרים', () async {
      final provider = build(
        respond: (_) async => _json({'ok': true}),
      ).provider;

      final books = await provider.loadBooksByIds([
        'rp:1524',
        'oh:1524',
        'hb:1524',
      ]);

      expect(books, hasLength(1));
      expect(books.single.externalLibraryId, 'rp:1524');
    });

    test('קיום ברשומה הוא הזמינות — אין בדיקת קובץ', () async {
      final provider = build(
        respond: (_) async => _json({'ok': true}),
      ).provider;

      expect(await provider.loadBooksByIds(['1524']), hasLength(1));
      expect(await provider.loadBooksByIds(['404']), isEmpty);
    });
  });
}
