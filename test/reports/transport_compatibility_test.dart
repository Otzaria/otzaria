import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/core/otzaria_capabilities.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:package_info_plus/package_info_plus.dart';

AppReport _report(String id) => AppReport(
  reportId: id,
  type: AppReportType.bug,
  trigger: AppReportTrigger.manual,
  title: 'Compatibility report',
  description: 'תיאור עם ניקוד: שָׁלוֹם 😀',
  reporterEmail: 'qa@example.com',
  appVersion: '1.0.0',
  platform: 'windows',
  osVersion: 'Windows 11 QA',
  createdAt: DateTime.utc(2026, 11, 6),
);

AppReportMinidump _dump() => AppReportMinidump(
  gzipBytes: Uint8List.fromList(
    gzip.encode(ascii.encode('MDMP-exact-minidump-content')),
  ),
  fileName: 'compat.dmp',
);

// These bodies are consumed by the pinned old website's actual validator.
// Digests come from the original attachments before any transport selection.
List<Map<String, dynamic>> _transportCases() {
  final cases = <Map<String, dynamic>>[];
  String digest(List<int> bytes) => sha256.convert(bytes).toString();
  AppReportImage image(int size) => AppReportImage(
    bytes: Uint8List(size)..setRange(0, 6, ascii.encode('GIF89a')),
    fileName: 'same-bytes.gif',
    mimeType: 'image/gif',
  );
  void add(String name, AppReport report, int expectedSchema) {
    expect(report.validate(), isNull, reason: name);
    final wire = report.forCompatibleTransport();
    expect(wire.schema, expectedSchema, reason: name);
    expect(
      wire.toApiPayload(),
      report.toApiPayload()..['schema'] = wire.schema,
      reason: name,
    );
    cases.add({
      'name': name,
      'schema': expectedSchema,
      'payload': wire.toApiPayload(),
      'digests': {
        if (report.diagnostics != null)
          'diagnostics': digest(utf8.encode(jsonEncode(report.diagnostics))),
        if (report.errorLog != null)
          'errorLog': digest(utf8.encode(report.errorLog!)),
        'images': [for (final image in report.images) digest(image.bytes)],
        if (report.minidump != null)
          'minidump': digest(gzip.decode(report.minidump!.gzipBytes)),
      },
    });
  }

  final base = _report('transport-boundary');
  add(
    'ordinary_text_image_dump',
    base.copyWith(
      diagnostics: {'language': 'עברית 😀'},
      errorLog: 'first\nlast\u0000',
      images: [image(64)],
      minidump: _dump(),
    ),
    1,
  );
  final diagnostics = {'blob': 'x' * (300000 - 11)};
  add(
    'legacy_diagnostics_exact_300000',
    base.copyWith(diagnostics: diagnostics),
    1,
  );
  add(
    'legacy_diagnostics_plus_one',
    base.copyWith(diagnostics: {'blob': '${diagnostics['blob']}x'}),
    2,
  );
  add('legacy_log_exact_250000_utf8', base.copyWith(errorLog: 'א' * 125000), 1);
  add('legacy_log_plus_one', base.copyWith(errorLog: '${'א' * 125000}x'), 2);
  final escapedBase = base.copyWith(
    diagnostics: diagnostics,
    errorLog: '\u0000' * 66000,
  );
  final padding =
      700000 - utf8.encode(jsonEncode(escapedBase.toApiPayload())).length;
  final exactEnvelope = escapedBase.copyWith(
    errorLog: '${escapedBase.errorLog}${'x' * padding}',
  );
  expect(utf8.encode(jsonEncode(exactEnvelope.toApiPayload())).length, 700000);
  add('legacy_text_envelope_exact_700000', exactEnvelope, 1);
  add(
    'legacy_text_envelope_plus_one',
    exactEnvelope.copyWith(errorLog: '${exactEnvelope.errorLog}x'),
    2,
  );
  add(
    'legacy_image_exact_5_mib',
    base.copyWith(images: [image(5 * 1024 * 1024)]),
    1,
  );
  add(
    'legacy_image_plus_one',
    base.copyWith(images: [image(5 * 1024 * 1024 + 1)]),
    2,
  );
  return cases;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late UserStateDatabase database;
  late PendingReportStore store;
  late AppReportService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('report_compat_');
    Hive.init(temp.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    await Settings.init(cacheProvider: HiveCache());
    database = UserStateDatabase.openAt('${temp.path}/user_state.db');
    store = PendingReportStore(database: database);
    service = AppReportService(
      reportStore: store,
      sentCounter: SentReportsCounter.inMemory(),
    );
  });

  tearDown(() async {
    await AppReportService.suspendAutomaticFlush();
    database.close();
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test(
    'additive draft tables preserve new and existing layout versions',
    () async {
      final first = await database.database;
      expect(first.select('PRAGMA user_version').single.values.single, 1);
      expect(
        first
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((row) => row['name']),
        containsAll(['report_drafts', 'report_draft_attachments']),
      );

      // Opening a database created by an earlier PR build, or a future version,
      // must never claim that its layout is understood by the old updater.
      for (final version in [1, 2, 3]) {
        first.execute('PRAGMA user_version = $version');
        final other = UserStateDatabase.openAt('${temp.path}/user_state.db');
        final reopened = await other.database;
        expect(
          reopened.select('PRAGMA user_version').single.values.single,
          version,
        );
        other.close();
      }
    },
  );

  test(
    'mixed queues retain rows when an explicit edit changes transport kind',
    () async {
      final original = _report('editable');
      await service.queueReport(original);
      final firstRow = (await store.listByKind(
        AppReportService.pendingKind,
      )).single;
      expect(firstRow.payload['schema'], 1);
      expect(await service.getPendingReportsCount(), 1);

      final expanded = (await service.updatePendingReport(
        AppReport.fromJson(firstRow.payload).copyWith(errorLog: 'x' * 250001),
      ))!;
      final expandedRow = (await store.listByKind(
        AppReportService.currentPendingKind,
      )).single;
      expect(expanded.schema, 2);
      expect(expandedRow.id, firstRow.id);
      expect(expanded.errorLog, 'x' * 250001);
      expect(await store.countByKind(AppReportService.pendingKind), 0);
      expect(await service.getPendingReportsCount(), 1);

      final reduced = (await service.updatePendingReport(
        expanded.copyWith(errorLog: 'short complete log'),
      ))!;
      final reducedRow = (await store.listByKind(
        AppReportService.pendingKind,
      )).single;
      expect(reduced.schema, 1);
      expect(reducedRow.id, firstRow.id);
      expect(reduced.reportId, isNot(expanded.reportId));
      expect(reduced.errorLog, 'short complete log');
      expect(await store.countByKind(AppReportService.currentPendingKind), 0);
      expect(await service.getPendingReportsCount(), 1);
      expect(
        (await service.getPendingReports()).single.reportId,
        reduced.reportId,
      );
    },
  );

  test(
    'both kinds support counting, deduplication, deletion and clearing',
    () async {
      final compatible = _report('small');
      final extended = _report('extended').copyWith(errorLog: 'x' * 250001);
      await service.queueReport(compatible);
      await service.queueReport(extended);
      expect(await service.getPendingReportsCount(), 2);
      // An already queued row is returned as it is stored, including one that
      // originated in an earlier build under the protected kind.
      final oldBuild = _report('already-protected');
      await store.add(AppReportService.currentPendingKind, oldBuild.toJson());
      expect((await service.queueReport(oldBuild)).toJson(), oldBuild.toJson());
      expect(await service.getPendingReportsCount(), 3);
      await service.deletePendingReport(extended.reportId);
      expect((await service.getPendingReports()).map((r) => r.reportId), [
        'small',
        'already-protected',
      ]);
      await service.clearPendingReports();
      expect(await store.countByKind(AppReportService.pendingKind), 0);
      expect(await store.countByKind(AppReportService.currentPendingKind), 0);
    },
  );

  test(
    'write actual mixed database and capabilities for old-consumer gates',
    () async {
      final image = AppReportImage(
        bytes: Uint8List.fromList([
          ...ascii.encode('GIF89a'),
          1,
          0,
          1,
          0,
          0,
          0,
          0,
          0x21,
          0xfe,
          4,
          0x74,
          0x65,
          0x73,
          0x74,
          0,
          0x3b,
        ]),
        fileName: 'animated.gif',
        mimeType: 'image/gif',
      );
      final small = _report('small-new').copyWith(
        diagnostics: {
          'עברית': 'ניקוד שָׁלוֹם 😀',
          'lines': ['one', 'two'],
        },
        errorLog: 'first\nsecond\u0000\\"',
        images: [image],
      );
      final legacy = _report('existing-legacy').copyWith(
        schema: 1,
        diagnostics: {'legacy': true},
        errorLog: 'legacy log',
        images: [image],
        minidump: _dump(),
      );
      final rawLegacy = legacy.toJson()..remove('schema');
      await store.add(AppReportService.legacyPendingKind, rawLegacy);
      await service.queueReport(small);

      final extended = _report(
        'large-current',
      ).copyWith(errorLog: 'א' * 125001);
      await service.queueReport(extended);
      final withDump = small.copyWith(
        reportId: 'new-with-dump',
        minidump: _dump(),
      );
      await service.queueReport(withDump);

      final book = DirectErrorReport(
        id: 'existing-book',
        senderEmail: 'qa@example.com',
        subject: 'תיקון בספר',
        bookTitle: 'ספר בדיקה',
        currentRef: 'פרק א',
        lineNumber: 7,
        selectedText: 'טעות',
        errorDetails: 'יש לקרוא: תיקון',
        contextText: 'הקשר של הטעות',
        filePath: 'ספר בדיקה.txt',
        sourceFolder: 'Otzaria',
        libraryVersion: 'fixture',
        createdAt: DateTime.utc(2026, 11, 6),
      );
      await store.add('error_reports_queue/pending_reports', book.toJson());
      final plugin = PluginReportRecord(
        reportId: 'existing-plugin',
        pluginUid: 'qa.plugin',
        pluginName: 'QA plugin',
        pluginVersion: '1.0.0',
        reportType: 'bug',
        details: 'A queued plugin report',
        reporterEmail: 'qa@example.com',
        appVersion: '1.0.0',
        platform: 'windows',
        createdAt: DateTime.utc(2026, 11, 6),
      );
      await store.add('plugin_reports_queue/pending_reports', plugin.toJson());
      final drafts = ReportDraftStore.forDatabase(database);
      for (final kind in [
        ReportDraftStore.appKind,
        ReportDraftStore.bookKind,
      ]) {
        await drafts.write(
          id: 'draft-$kind-local',
          kind: kind,
          title: 'LOCAL_ONLY_DRAFT_$kind',
          payload: {'partial': 'LOCAL_ONLY_DRAFT_$kind'},
          attachments: {'private': base64Encode(utf8.encode('PRIVATE_$kind'))},
          revision: 0,
        );
      }

      final queued = await service.getPendingReports();
      expect(queued, hasLength(4));
      expect(queued.singleWhere((r) => r.reportId == small.reportId).schema, 1);
      expect(
        queued.singleWhere((r) => r.reportId == extended.reportId).schema,
        2,
      );
      expect(
        queued.singleWhere((r) => r.reportId == withDump.reportId).schema,
        2,
      );
      expect(
        (await store.listByKind(
          AppReportService.legacyPendingKind,
        )).singleWhere((r) => r.payload['reportId'] == legacy.reportId).payload,
        rawLegacy,
        reason: 'Reading or exporting cannot rewrite existing queued content.',
      );

      final capabilities = OtzariaCapabilities.build(
        packageInfo: PackageInfo(
          appName: 'otzaria',
          packageName: 'otzaria',
          version: '1.0.0',
          buildNumber: '1',
        ),
        arch: 'x64',
        portable: true,
        exePath: '/qa/otzaria',
        libraryDbPath: '/qa/books.db',
      );
      await OtzariaCapabilities.writeIfChanged(temp.path, capabilities);
      final capabilitiesFile = File(
        '${temp.path}/${OtzariaCapabilities.capabilitiesFileName}',
      );
      expect(
        jsonDecode(await capabilitiesFile.readAsString())['reportsQueueFormat'],
        1,
      );
      final db = await database.database;
      expect(db.select('PRAGMA user_version').single.values.single, 1);
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      database.close();

      final output = Directory('build/reporting_qa');
      await output.create(recursive: true);
      await File(
        '${temp.path}/user_state.db',
      ).copy('${output.path}/compat-user-state.db');
      await capabilitiesFile.copy('${output.path}/compat-capabilities.json');
      await File('${output.path}/compat-payloads.json').writeAsString(
        jsonEncode({
          'bodies': {
            'app-${legacy.reportId}': legacy.toApiPayload(),
            'app-${small.reportId}': small
                .forCompatibleTransport()
                .toApiPayload(),
            book.id: book.toApiPayload(),
            'plugin-${plugin.reportId}': plugin.toApiPayload(),
          },
          'pendingIds': [
            legacy.reportId,
            small.reportId,
            extended.reportId,
            withDump.reportId,
            book.id,
            plugin.reportId,
          ],
          'draftIds': ['draft-app-local', 'draft-book-local'],
          'extendedReportId': extended.reportId,
          'protectedDumpReportId': withDump.reportId,
          'extendedReportIds': [extended.reportId, withDump.reportId],
          'extendedPayloads': {
            extended.reportId: extended.toJson(),
            withDump.reportId: withDump.toJson(),
          },
          'transportCases': _transportCases(),
          'directBodies': {
            'with-dump': withDump.forCompatibleTransport().toApiPayload(),
            'exact-diagnostics-log': _report('exact-text')
                .copyWith(
                  diagnostics: {'blob': 'x' * (300000 - 11)},
                  errorLog: 'א' * 125000,
                )
                .forCompatibleTransport()
                .toApiPayload(),
          },
        }),
      );
    },
  );
}
