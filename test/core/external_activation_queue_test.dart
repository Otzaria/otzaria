import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
  });
}
