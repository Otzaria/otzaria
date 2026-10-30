import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/external_activation_queue.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ExternalActivationQueue', () {
    test('enqueue and drain returns pending URIs once', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'external_activation_queue_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final queue = ExternalActivationQueue(
        queueFilePath: p.join(tempDir.path, 'queue.jsonl'),
      );

      await queue.enqueueUriString(
        'otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Fone.otzplugin',
      );
      await queue.enqueueUriString(
        'otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Ftwo.otzplugin',
      );

      expect(
        await queue.drainUriStrings(),
        [
          'otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Fone.otzplugin',
          'otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Ftwo.otzplugin',
        ],
      );
      expect(await queue.drainUriStrings(), isEmpty);
    });

    test('drain ignores malformed lines and keeps valid records', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'external_activation_queue_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final queueFile = File(p.join(tempDir.path, 'queue.jsonl'));
      await queueFile.parent.create(recursive: true);
      await queueFile.writeAsString(
        'not-json\n{"uri":""}\n'
        '{"uri":"otzaria://plugin/install?url=https://example.com/plugin.otzplugin"}\n',
      );

      final queue = ExternalActivationQueue(queueFilePath: queueFile.path);

      expect(
        await queue.drainUriStrings(),
        [
          'otzaria://plugin/install?url=https://example.com/plugin.otzplugin',
        ],
      );
    });

    test('drain recovers entries left in processing file after a crash', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'external_activation_queue_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final queuePath = p.join(tempDir.path, 'queue.jsonl');
      final processingFile = File('$queuePath.processing');
      await processingFile.parent.create(recursive: true);
      await processingFile.writeAsString(
        '{"uri":"otzaria://plugin/install?url=https://example.com/recovered.otzplugin"}\n',
      );

      final queue = ExternalActivationQueue(queueFilePath: queuePath);

      expect(
        await queue.drainUriStrings(),
        [
          'otzaria://plugin/install?url=https://example.com/recovered.otzplugin',
        ],
      );
      expect(await processingFile.exists(), isFalse);
    });

    test('התור בתיקייה ייעודית ולא בשורש הנתונים (#3590)', () async {
      final dataRoot = await Directory.systemTemp.createTemp('ext_act_root_');
      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      addTearDown(() async {
        AppPaths.debugOverrideDataRootPath(null);
        await dataRoot.delete(recursive: true);
      });
      const queue = ExternalActivationQueue();

      final queueDir = p.dirname(await queue.resolveQueueFilePath());
      expect(queueDir, isNot(p.normalize(dataRoot.path)));
      expect(queueDir, p.join(dataRoot.path, 'external_activations'));

      const uri = 'otzaria://library/reindex?n=1';
      await queue.enqueueUriString(uri);
      expect(await queue.drainUriStrings(), [uri]);
      expect(await queue.drainUriStrings(), isEmpty);
    });

    test('מנקז קובץ שנשאר בנתיב הישן בשורש הנתונים', () async {
      final dataRoot = await Directory.systemTemp.createTemp('ext_act_root_');
      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      addTearDown(() async {
        AppPaths.debugOverrideDataRootPath(null);
        await dataRoot.delete(recursive: true);
      });
      final legacyFile = File(
        p.join(dataRoot.path, 'pending_external_activations.jsonl'),
      );
      await legacyFile.writeAsString('{"uri":"otzaria://legacy"}\n');
      const queue = ExternalActivationQueue();

      expect(await queue.drainUriStrings(), isEmpty);
      expect(await queue.drainLegacyUriStrings(), ['otzaria://legacy']);
      expect(await legacyFile.exists(), isFalse);
    });
  });

  group('CoalescingDrainRunner', () {
    test('קריאה באמצע ניקוז מריצה ניקוז נוסף אחריו', () async {
      final gate = Completer<void>();
      var runs = 0;
      final runner = CoalescingDrainRunner(() async {
        runs++;
        if (runs == 1) await gate.future;
      });

      final first = runner.run();
      final second = runner.run();
      final third = runner.run();
      gate.complete();
      await Future.wait([first, second, third]);

      expect(runs, 2);
    });

    test('קריאה אחרי סיום מתחילה ריצה חדשה', () async {
      var runs = 0;
      final runner = CoalescingDrainRunner(() async => runs++);

      await runner.run();
      await runner.run();

      expect(runs, 2);
    });
  });
}
