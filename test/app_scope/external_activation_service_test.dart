import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/external_activation_service.dart';
import 'package:otzaria/core/external_activation_channel.dart';
import 'package:otzaria/core/external_activation_queue.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:path/path.dart' as p;

const _a = 'otzaria://library/reindex?n=1';
const _b = 'otzaria://library/reindex?n=2';
const _c = 'otzaria://library/reindex?n=3';
const _newWindow = 'otzaria://window/new';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ExternalActivationQueue queue;
  late List<String> delivered;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ext_activation_svc_');
    queue = ExternalActivationQueue(
      queueFilePath: p.join(tempDir.path, 'pending.jsonl'),
    );
    delivered = [];
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<bool> handler(String uri) async {
    delivered.add(uri);
    return true;
  }

  ExternalActivationService service({
    ExternalActivationChannel? channel,
    Stream<FileSystemEvent> Function(Directory)? watchDirectory,
    AppWindowId lastActiveWindow = AppWindowId.primary,
  }) => ExternalActivationService(
    queue: queue,
    channel: channel,
    watchDirectory: watchDirectory,
    lastActiveWindow: () => lastActiveWindow,
  );

  group('drain', () {
    test('delivers queued URIs in order, once', () async {
      for (final uri in [_a, _b, _c]) {
        await queue.enqueueUriString(uri);
      }
      final svc = service()..attachWindow(handler);

      await svc.processPending();
      await svc.processPending();

      expect(delivered, [_a, _b, _c]);
    });

    test('concurrent triggers coalesce without double delivery', () async {
      await queue.enqueueUriString(_a);
      final svc = service()..attachWindow(handler);

      final first = svc.processPending();
      await queue.enqueueUriString(_b);
      final second = svc.processPending();
      await Future.wait([first, second]);

      expect(delivered, [_a, _b]);
    });

    test('leaves the queue untouched while no window is attached', () async {
      await queue.enqueueUriString(_a);
      final svc = service();

      await svc.processPending();
      expect(delivered, isEmpty);

      svc.attachWindow(handler);
      await svc.processPending();
      expect(delivered, [_a]);
    });
  });

  test('start delivers platform URIs, then drains on queue events', () async {
    const channel = MethodChannel('test/external_activation_service');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == ExternalActivationChannel.getPendingUriStringsMethod) {
        return [_a];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final events = StreamController<FileSystemEvent>();
    addTearDown(events.close);
    await queue.enqueueUriString(_b);

    final svc = service(
      channel: ExternalActivationChannel(channel: channel),
      watchDirectory: (_) => events.stream,
    )..attachWindow(handler);
    addTearDown(svc.dispose);

    await svc.start();
    expect(delivered, [_a, _b]);

    await queue.enqueueUriString(_c);
    events.add(
      FileSystemModifyEvent(p.join(tempDir.path, 'other'), false, true),
    );
    await pumpEventQueue();
    expect(delivered, [_a, _b]);

    events.add(
      FileSystemModifyEvent(p.join(tempDir.path, 'pending.jsonl'), false, true),
    );
    await pumpEventQueue();
    await svc.processPending();
    expect(delivered, [_a, _b, _c]);
  });

  test('start watches only the queue directory and drains the legacy file '
      'once', () async {
    final legacyFile = File(p.join(tempDir.path, 'legacy.jsonl'));
    await legacyFile.writeAsString('{"uri":"$_a"}\n');
    queue = ExternalActivationQueue(
      queueFilePath: p.join(tempDir.path, 'queue_dir', 'pending.jsonl'),
      legacyQueueFilePath: legacyFile.path,
    );
    final watched = <String>[];
    final events = StreamController<FileSystemEvent>();
    addTearDown(events.close);
    final svc = service(
      watchDirectory: (dir) {
        watched.add(dir.path);
        return events.stream;
      },
    )..attachWindow(handler);
    addTearDown(svc.dispose);

    await svc.start();
    expect(watched, [p.join(tempDir.path, 'queue_dir')]);
    expect(delivered, [_a]);

    await legacyFile.writeAsString('{"uri":"$_b"}\n');
    await svc.processPending();
    expect(delivered, [_a]);
  });

  group('Dart windows in one isolate', () {
    const viewA = AppWindowId('window-view-2');
    const viewB = AppWindowId('window-view-3');
    late List<(AppWindowId, String)> viewDelivered;
    late Map<AppWindowId, bool> visible;
    late Map<AppWindowId, ExternalUriHandler> viewHandlers;
    var mainVisible = true;

    setUp(() {
      viewDelivered = [];
      visible = {viewA: true, viewB: true};
      viewHandlers = {
        for (final id in [viewA, viewB])
          id: (uri) async {
            viewDelivered.add((id, uri));
            return true;
          },
      };
      mainVisible = true;
    });

    ExternalActivationService hybrid(AppWindowId lastActive) {
      final svc = service(lastActiveWindow: lastActive)
        ..attachWindow(handler, isVisible: () async => mainVisible);
      for (final id in [viewA, viewB]) {
        svc.attachViewWindow(
          id,
          viewHandlers[id]!,
          isVisible: () async => visible[id]!,
        );
      }
      return svc;
    }

    test('the last active Dart window gets the link, not the runner', () async {
      await queue.enqueueUriString(_a);
      await hybrid(viewA).processPending();

      expect(viewDelivered, [(viewA, _a)]);
      expect(delivered, isEmpty);
    });

    test('main last active and visible keeps the link', () async {
      await queue.enqueueUriString(_a);
      await hybrid(AppWindowId.primary).processPending();

      expect(delivered, [_a]);
      expect(viewDelivered, isEmpty);
    });

    test(
      'a hidden main is not raised while a Dart window is visible',
      () async {
        mainVisible = false;
        visible[viewB] = false;
        await queue.enqueueUriString(_a);
        await hybrid(AppWindowId.primary).processPending();

        expect(viewDelivered, [(viewA, _a)]);
        expect(delivered, isEmpty);
      },
    );

    test('with nothing visible main shows itself', () async {
      mainVisible = false;
      visible
        ..[viewA] = false
        ..[viewB] = false;
      await queue.enqueueUriString(_a);
      await hybrid(viewA).processPending();

      expect(delivered, [_a]);
      expect(viewDelivered, isEmpty);
    });

    test('a detached window no longer receives links', () async {
      final svc = hybrid(viewA);
      // ביטול עם handler אחר (חלון שנבנה מחדש) אינו מסיר את הרשום.
      svc.detachViewWindow(viewA, handler);
      await queue.enqueueUriString(_a);
      await svc.processPending();
      expect(viewDelivered, [(viewA, _a)]);

      svc.detachViewWindow(viewA, viewHandlers[viewA]!);
      await queue.enqueueUriString(_b);
      await svc.processPending();
      expect(delivered, [_b]);
    });

    test('"new window" is handled by main', () async {
      await queue.enqueueUriString(_newWindow);
      await hybrid(viewA).processPending();

      expect(delivered, [_newWindow]);
      expect(viewDelivered, isEmpty);
    });
  });
}
