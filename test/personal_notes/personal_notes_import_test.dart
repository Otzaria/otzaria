import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_import_export_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_changes.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = PersonalNotesDatabase.instance;
  final service = PersonalNotesImportExportService();
  late Directory root;
  late List<String> changes;
  late StreamSubscription<String> subscription;

  PersonalNote note(
    String id, {
    String content = 'local',
    int day = 1,
    String bookId = 'ספר',
  }) => PersonalNote(
    id: id,
    bookId: bookId,
    lineNumber: 5,
    anchorText: 'כוס',
    anchorPrefix: 'לפני ',
    anchorSuffix: ' אחרי',
    anchorStart: 10,
    anchorEnd: 13,
    lastKnownLineNumber: null,
    status: PersonalNoteStatus.located,
    content: content,
    contentPlain: content,
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: DateTime.utc(2026, 6, 14),
    updatedAt: DateTime.utc(2026, 10, day),
  );

  Map<String, dynamic> withoutAnchor(PersonalNote note) =>
      note.toJson()..removeWhere((key, _) => key.startsWith('anchor'));

  Map<String, dynamic> backup(
    List<Object?> notes, {
    String version = '1.0',
  }) => {
    'version': version,
    'includes': {'notes': true},
    'notes': [
      {'bookId': 'ספר', 'notes': notes},
    ],
  };

  Future<NotesImportSummary> import(
    Map<String, dynamic> payload,
    NotesImportConflictStrategy strategy,
  ) async {
    final file = File('${root.path}/notes.json');
    await file.writeAsString(jsonEncode(payload));
    return service.importFromFile(path: file.path, strategy: strategy);
  }

  void expectCounts(
    NotesImportSummary summary, {
    int inserted = 0,
    int updated = 0,
    int skipped = 0,
    int duplicated = 0,
  }) {
    expect(
      [summary.inserted, summary.updated, summary.skipped, summary.duplicated],
      [inserted, updated, skipped, duplicated],
    );
  }

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await database.close();
    root = await Directory.systemTemp.createTemp('personal_notes_import_');
    await Directory('${root.path}/databases').create();
    AppPaths.debugOverrideDataRootPath(root.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/databases',
    );
    await database.insertNote(note('same'));
    await database.insertNote(note('untouched'));
    await database.setUserBookKeysPending(false);
    await pumpEventQueue();
    changes = [];
    subscription = PersonalNotesChanges.stream.listen(changes.add);
  });

  tearDown(() async {
    await subscription.cancel();
    expect(
      (await database.getNote('untouched'))!.toJson(),
      note('untouched').toJson(),
    );
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    await root.delete(recursive: true);
  });

  for (final strategy in [
    NotesImportConflictStrategy.overwrite,
    NotesImportConflictStrategy.merge,
  ]) {
    group(strategy.name, () {
      for (final version in ['1.0', '2.0']) {
        test('preserves local anchors from grouped backup $version', () async {
          final incoming = note('same', content: 'imported', day: 2);
          final summary = await import(
            backup([withoutAnchor(incoming)], version: version),
            strategy,
          );

          expectCounts(summary, updated: 1);
          expect((await database.getNote('same'))!.toJson(), incoming.toJson());
          expect(await database.userBookKeysPending(), isTrue);
        });
      }

      for (final (field, value) in <(String, Object?)>[
        ('bookId', 'ספר אחר'),
        ('lineNumber', 12),
        ('displayTitle', 'הקשר חדש'),
        ('status', PersonalNoteStatus.missing.name),
      ]) {
        test('changed $field does not inherit the local anchor', () async {
          final incoming = withoutAnchor(
            note('same', content: 'relocated', day: 2),
          )..[field] = value;
          final summary = await import(backup([incoming]), strategy);

          expectCounts(summary, updated: 1);
          expect(
            (await database.getNote('same'))!.toJson(),
            PersonalNote.fromJson(incoming).toJson(),
          );
        });
      }

      test('a previous line hint does not change a valid location', () async {
        final incoming = note(
          'same',
          content: 'imported',
          day: 2,
        ).copyWith(lastKnownLineNumber: 4);
        final summary = await import(
          backup([withoutAnchor(incoming)]),
          strategy,
        );

        expectCounts(summary, updated: 1);
        expect((await database.getNote('same'))!.toJson(), incoming.toJson());
      });

      test(
        'a changed missing-location hint does not inherit the anchor',
        () async {
          final local = note('same').copyWith(
            clearLineNumber: true,
            lastKnownLineNumber: 5,
            status: PersonalNoteStatus.missing,
          );
          await database.updateNote(local);
          final incoming = local.copyWith(
            lastKnownLineNumber: 12,
            content: 'relocated',
            contentPlain: 'relocated',
            updatedAt: DateTime.utc(2026, 10, 2),
            clearAnchor: true,
          );
          final summary = await import(
            backup([withoutAnchor(incoming)]),
            strategy,
          );

          expectCounts(summary, updated: 1);
          expect((await database.getNote('same'))!.toJson(), incoming.toJson());
        },
      );

      test(
        'an unchanged missing location preserves its local anchor',
        () async {
          final local = note('same').copyWith(
            clearLineNumber: true,
            lastKnownLineNumber: 5,
            status: PersonalNoteStatus.missing,
          );
          await database.updateNote(local);
          final incoming = local.copyWith(
            content: 'imported',
            contentPlain: 'imported',
            updatedAt: DateTime.utc(2026, 10, 2),
          );
          final summary = await import(
            backup([withoutAnchor(incoming)]),
            strategy,
          );

          expectCounts(summary, updated: 1);
          expect((await database.getNote('same'))!.toJson(), incoming.toJson());
        },
      );

      test(
        'preserves the complete local anchor including null hints',
        () async {
          final local = note(
            'same',
          ).copyWith(clearAnchor: true).copyWith(anchorText: 'כוס');
          await database.updateNote(local);
          final incoming = local.copyWith(
            content: 'imported',
            contentPlain: 'imported',
            updatedAt: DateTime.utc(2026, 10, 2),
          );
          final json = withoutAnchor(incoming)
            ..addAll({
              'anchorPrefix': 'foreign',
              'anchorSuffix': 'context',
              'anchorStart': 40,
              'anchorEnd': 43,
            });
          final summary = await import(backup([json]), strategy);

          expectCounts(summary, updated: 1);
          expect((await database.getNote('same'))!.toJson(), incoming.toJson());
        },
      );

      test('explicit null clears the local anchor', () async {
        final incoming = note(
          'same',
          content: 'line note',
          day: 2,
        ).copyWith(clearAnchor: true);
        final summary = await import(backup([incoming.toJson()]), strategy);

        expectCounts(summary, updated: 1);
        expect((await database.getNote('same'))!.toJson(), incoming.toJson());
      });

      test('supplied anchor replaces every local anchor field', () async {
        final incoming = note('same', content: 'new anchor', day: 2)
            .copyWith(clearAnchor: true)
            .copyWith(anchorText: 'מים', anchorStart: 20, anchorEnd: 23);
        final summary = await import(backup([incoming.toJson()]), strategy);

        expectCounts(summary, updated: 1);
        expect((await database.getNote('same'))!.toJson(), incoming.toJson());
      });

      test('missing anchor stays null without a local word anchor', () async {
        final local = note('same').copyWith(clearAnchor: true);
        await database.updateNote(local);
        final updated = local.copyWith(
          content: 'updated',
          contentPlain: 'updated',
          updatedAt: DateTime.utc(2026, 10, 2),
        );
        final added = note('new').copyWith(clearAnchor: true);
        final summary = await import(
          backup([withoutAnchor(updated), withoutAnchor(added)]),
          strategy,
        );

        expectCounts(summary, inserted: 1, updated: 1);
        expect((await database.getNote('same'))!.toJson(), updated.toJson());
        expect((await database.getNote('new'))!.toJson(), added.toJson());
      });

      test(
        'duplicate IDs preserve the anchor from the preceding write',
        () async {
          final first = note(
            'same',
            content: 'first',
            day: 2,
          ).copyWith(anchorText: 'מים', anchorStart: 20, anchorEnd: 23);
          final second = first.copyWith(
            content: 'second',
            contentPlain: 'second',
            updatedAt: DateTime.utc(2026, 10, 3),
          );
          final summary = await import(
            backup([first.toJson(), withoutAnchor(second)]),
            strategy,
          );

          expectCounts(summary, updated: 2);
          expect((await database.getNote('same'))!.toJson(), second.toJson());
        },
      );
    });
  }

  test('keepBoth does not give a new legacy note the local anchor', () async {
    final incoming = note(
      'same',
      content: 'duplicate',
      day: 2,
    ).copyWith(clearAnchor: true);
    final summary = await import(
      backup([withoutAnchor(incoming)]),
      NotesImportConflictStrategy.keepBoth,
    );

    expectCounts(summary, duplicated: 1);
    expect((await database.getNote('same'))!.toJson(), note('same').toJson());
    final duplicate = (await database.loadNotes(
      'ספר',
    )).singleWhere((n) => n.id != 'same' && n.id != 'untouched');
    expect(duplicate.toJson()..remove('id'), incoming.toJson()..remove('id'));
    expect(await database.userBookKeysPending(), isTrue);
  });

  for (final (strategy, day) in [
    (NotesImportConflictStrategy.skip, 2),
    (NotesImportConflictStrategy.merge, 0),
    (NotesImportConflictStrategy.merge, 1),
  ]) {
    test(
      '${strategy.name} keeps the local note for incoming day $day',
      () async {
        final summary = await import(
          backup([withoutAnchor(note('same', content: 'ignored', day: day))]),
          strategy,
        );

        expectCounts(summary, skipped: 1);
        expect(
          (await database.getNote('same'))!.toJson(),
          note('same').toJson(),
        );
        expect(await database.userBookKeysPending(), isFalse);
      },
    );
  }

  for (final strategy in NotesImportConflictStrategy.values) {
    test(
      '${strategy.name} imports repeated IDs in order with one refresh',
      () async {
        final first = note(
          'new',
          content: 'first',
          day: 2,
          bookId: 'ספר אחר',
        );
        final second = first.copyWith(
          content: 'second',
          contentPlain: 'second',
          updatedAt: DateTime.utc(2026, 10, 3),
        );
        final newer = note('same', content: 'newer', day: 2);
        final older = note('same', content: 'older', day: 1);
        final revision = database.revision.value;
        final generation = await database.userBookKeysGeneration();
        final loaded = <Future<List<PersonalNote>>>[];
        void reload() => loaded.add(database.loadNotes('ספר אחר'));
        database.revision.addListener(reload);
        addTearDown(() => database.revision.removeListener(reload));

        final summary = await import(
          backup([
            first.toJson(),
            newer.toJson(),
            second.toJson(),
            older.toJson(),
          ]),
          strategy,
        );
        await pumpEventQueue();
        final snapshots = await Future.wait(loaded);
        expect(database.revision.value - revision, 1);
        expect(snapshots, hasLength(1));
        expect(await database.userBookKeysGeneration(), generation + 1);
        expect(
          changes,
          unorderedEquals(
            strategy == NotesImportConflictStrategy.skip
                ? ['ספר אחר']
                : ['ספר אחר', 'ספר'],
          ),
        );

        switch (strategy) {
          case NotesImportConflictStrategy.skip:
            expectCounts(summary, inserted: 1, skipped: 3);
            expect(
              (await database.getNote('same'))!.toJson(),
              note('same').toJson(),
            );
            expect(snapshots.single.single.toJson(), first.toJson());
            break;
          case NotesImportConflictStrategy.merge:
            expectCounts(summary, inserted: 1, updated: 2, skipped: 1);
            expect((await database.getNote('same'))!.toJson(), newer.toJson());
            expect(snapshots.single.single.toJson(), second.toJson());
            break;
          case NotesImportConflictStrategy.overwrite:
            expectCounts(summary, inserted: 1, updated: 3);
            expect((await database.getNote('same'))!.toJson(), older.toJson());
            expect(snapshots.single.single.toJson(), second.toJson());
            break;
          case NotesImportConflictStrategy.keepBoth:
            expectCounts(summary, inserted: 1, duplicated: 3);
            expect(
              (await database.getNote('same'))!.toJson(),
              note('same').toJson(),
            );
            expect((await database.getNote('new'))!.toJson(), first.toJson());
            final all = [
              ...await database.loadNotes('ספר'),
              ...snapshots.single,
            ];
            expect(all.map((n) => n.id).toSet(), hasLength(6));
            final duplicates = all.where((n) => n.id.startsWith('pn_'));
            expect(
              duplicates.map((n) => n.toJson()..remove('id')),
              unorderedEquals(
                [newer, second, older].map((n) => n.toJson()..remove('id')),
              ),
            );
            break;
        }
      },
    );
  }

  test(
    'keepBoth preserves every copy when the clock does not advance',
    () async {
      final instant = DateTime.utc(2026, 11, 6);
      final fixedClockService = PersonalNotesImportExportService(
        database: database,
        random: Random(1),
        now: () => instant,
      );
      final anotherService = PersonalNotesImportExportService(
        database: database,
        random: Random(2),
        now: () => instant,
      );
      final incoming = [
        for (var index = 0; index < 32; index++)
          note('same', content: 'copy $index', day: 2),
      ];
      final file = File('${root.path}/fixed-clock-notes.json');
      await file.writeAsString(
        jsonEncode(backup(incoming.map((note) => note.toJson()).toList())),
      );
      final revision = database.revision.value;

      for (final importer in [
        fixedClockService,
        fixedClockService,
        anotherService,
      ]) {
        final summary = await importer.importFromFile(
          path: file.path,
          strategy: NotesImportConflictStrategy.keepBoth,
        );
        expectCounts(summary, duplicated: incoming.length);
      }

      await pumpEventQueue();
      final all = await database.loadNotes('ספר');
      expect(all.map((note) => note.id).toSet(), hasLength(98));
      expect((await database.getNote('same'))!.toJson(), note('same').toJson());
      expect(
        all
            .where((note) => note.id.startsWith('pn_'))
            .map(
              (note) => note.toJson()..remove('id'),
            ),
        unorderedEquals([
          for (var iteration = 0; iteration < 3; iteration++)
            ...incoming.map((note) => note.toJson()..remove('id')),
        ]),
      );
      expect(database.revision.value - revision, 3);
      expect(changes, ['ספר', 'ספר', 'ספר']);
    },
  );

  for (final strategy in [
    NotesImportConflictStrategy.skip,
    NotesImportConflictStrategy.merge,
  ]) {
    test('${strategy.name} with no writes publishes no change', () async {
      final revision = database.revision.value;
      final generation = await database.userBookKeysGeneration();
      final summary = await import(
        backup([note('same').toJson(), note('same').toJson()]),
        strategy,
      );
      await pumpEventQueue();

      expectCounts(summary, skipped: 2);
      expect(database.revision.value, revision);
      expect(changes, isEmpty);
      expect(await database.userBookKeysGeneration(), generation);
      expect(await database.userBookKeysPending(), isFalse);
    });
  }

  test('an empty import publishes no change', () async {
    final revision = database.revision.value;
    final generation = await database.userBookKeysGeneration();
    expectCounts(await import(backup([]), NotesImportConflictStrategy.merge));
    await pumpEventQueue();
    expect(database.revision.value, revision);
    expect(changes, isEmpty);
    expect(await database.userBookKeysGeneration(), generation);
  });

  for (final operation in ['INSERT', 'UPDATE']) {
    for (final failFirst in [true, false]) {
      test(
        '$operation failure preserves the committed prefix and its notification ($failFirst)',
        () async {
          final failedId = operation == 'INSERT' ? 'failed' : 'same';
          final db = await database.database;
          db.execute("""
          CREATE TRIGGER fail_import BEFORE $operation ON personal_notes
          WHEN NEW.id = '$failedId'
          BEGIN SELECT RAISE(ABORT, 'import failed'); END
        """);
          final first = note(
            'first',
            content: 'committed',
            bookId: 'ספר אחר',
          );
          final revision = database.revision.value;
          final generation = await database.userBookKeysGeneration();

          await expectLater(
            import(
              backup([
                if (!failFirst) ...[
                  first.toJson(),
                  first.copyWith(id: 'second').toJson(),
                ],
                note(failedId, content: 'failed', day: 2).toJson(),
                note('later').toJson(),
              ]),
              NotesImportConflictStrategy.overwrite,
            ),
            throwsA(isA<SqliteException>()),
          );
          await pumpEventQueue();

          expect(
            (await database.getNote('first'))?.toJson(),
            failFirst ? null : first.toJson(),
          );
          expect(
            (await database.getNote('second'))?.toJson(),
            failFirst ? null : first.copyWith(id: 'second').toJson(),
          );
          expect(
            (await database.getNote('same'))!.toJson(),
            note('same').toJson(),
          );
          expect(await database.getNote('failed'), isNull);
          expect(await database.getNote('later'), isNull);
          expect(database.revision.value - revision, failFirst ? 0 : 1);
          expect(changes, failFirst ? isEmpty : ['ספר אחר']);
          expect(await database.userBookKeysGeneration(), generation);
          expect(await database.userBookKeysPending(), isFalse);
        },
      );
    }
  }

  for (final strategy in [
    NotesImportConflictStrategy.merge,
    NotesImportConflictStrategy.overwrite,
  ]) {
    for (final anchorField in ['missing', 'null', 'provided']) {
      test(
        '${strategy.name} preserves PDF anchor field semantics ($anchorField)',
        () async {
          const anchor = PdfNoteAnchor(
            pageNumber: 5,
            x: 0.2,
            y: 0.6,
            documentId: 'edition',
          );
          final local = note('same').copyWith(pdfAnchor: anchor);
          await database.updateNote(local);
          final incoming = note('same', content: 'imported', day: 2).copyWith(
            pdfAnchor: anchorField == 'provided'
                ? const PdfNoteAnchor(
                    pageNumber: 5,
                    x: 0.7,
                    y: 0.4,
                    documentId: 'edition',
                  )
                : null,
          );
          final json = incoming.toJson();
          if (anchorField == 'missing') json.remove('pdfAnchor');
          final summary = await import(backup([json]), strategy);

          expectCounts(summary, updated: 1);
          expect(
            (await database.getNote('same'))!.toJson(),
            (anchorField == 'missing'
                    ? incoming.copyWith(pdfAnchor: anchor)
                    : incoming)
                .toJson(),
          );
        },
      );
    }
  }

  test('malformed later note prevents both inserts and updates', () async {
    final revision = database.revision.value;
    final generation = await database.userBookKeysGeneration();
    await expectLater(
      import(
        backup([
          withoutAnchor(note('same', content: 'not written', day: 2)),
          withoutAnchor(note('new')),
          {'id': 'invalid'},
        ]),
        NotesImportConflictStrategy.overwrite,
      ),
      throwsA(isA<TypeError>()),
    );

    expect((await database.getNote('same'))!.toJson(), note('same').toJson());
    expect(await database.getNote('new'), isNull);
    expect(database.revision.value, revision);
    expect(await database.userBookKeysGeneration(), generation);
  });

  test('flat v2 export retains its content and anchor', () async {
    final added = note('new');
    final summary = await import(
      service.buildExport(notes: [added]),
      NotesImportConflictStrategy.merge,
    );

    expectCounts(summary, inserted: 1);
    expect((await database.getNote('new'))!.toJson(), added.toJson());
  });
}
