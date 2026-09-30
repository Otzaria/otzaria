import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';

import '../helpers/seforim_fixture_db.dart';

Future<int> _one(SeforimRepository repository) async => 1;
Future<int> _slow(SeforimRepository repository) async {
  await Future<void>.delayed(const Duration(milliseconds: 450));
  return 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('המתנה מאחורי עבודה תקינה אינה גורמת timeout והשבתת המסד', () async {
    await QueryLoader.initialize();
    final worker = AttachedFindRefWorker.instance;
    worker.reset();
    final directory = await Directory.systemTemp.createTemp('attached_queue');
    final path = SeforimFixtureDb.create(directory, SeforimFixtureVariant.full);
    final timeouts = (
      AttachedFindRefWorker.callTimeout,
      AttachedFindRefWorker.perCallTimeout,
    );
    addTearDown(() async {
      worker.reset();
      AttachedFindRefWorker.callTimeout = timeouts.$1;
      AttachedFindRefWorker.perCallTimeout = timeouts.$2;
      await directory.delete(recursive: true);
    });
    await worker.run(path, immutable: false, version: 'v', job: _one);
    AttachedFindRefWorker.callTimeout = const Duration(milliseconds: 300);
    AttachedFindRefWorker.perCallTimeout = const Duration(milliseconds: 500);
    final first = worker
        .run(
          path,
          immutable: false,
          version: 'v',
          job: _slow,
          calls: 3,
        )
        .then<Object>((value) => value, onError: (Object error) => error);
    final second = worker
        .run(
          path,
          immutable: false,
          version: 'v',
          job: _one,
        )
        .then<Object>((value) => value, onError: (Object error) => error);
    final secondResult = await second;
    final firstResult = await first;
    expect(secondResult, 1);
    expect(firstResult, 1);
    expect(
      await worker.run(path, immutable: false, version: 'v', job: _one),
      1,
    );
  });
}
