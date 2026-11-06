import 'dart:async';
import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_webview_settings_updater.dart';

List<ContentBlocker> _rules(String filter) => [
  ContentBlocker(
    trigger: ContentBlockerTrigger(urlFilter: filter),
    action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
  ),
];

InAppWebViewSettings _settings({List<ContentBlocker>? rules}) =>
    InAppWebViewSettings(
      consoleMessageLevels: pluginWarningAndErrorConsoleLevels,
      contentBlockers: rules ?? _rules('initial'),
      allowUniversalAccessFromFileURLs: false,
      useOnRenderProcessGone: true,
      resourceCustomSchemes: ['otzaria-plugin'],
      cacheEnabled: false,
    );

InAppWebViewSettings _copy(InAppWebViewSettings settings) =>
    InAppWebViewSettings.fromMap(settings.toMap())!;

class _Controller extends PlatformInAppWebViewController {
  _Controller({InAppWebViewSettings? initial})
    : current = initial ?? _settings(),
      super.implementation(
        PlatformInAppWebViewControllerCreationParams(id: Object()),
      );

  InAppWebViewSettings current;
  final reads = Queue<Completer<InAppWebViewSettings?>>();
  final writes = Queue<Completer<void>>();
  final attempts = <InAppWebViewSettings>[];
  int readCount = 0;
  int concurrent = 0;
  int maxConcurrent = 0;
  void Function()? afterNextWrite;

  void _begin() {
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
  }

  @override
  Future<InAppWebViewSettings?> getSettings() async {
    _begin();
    readCount++;
    try {
      return reads.isEmpty ? _copy(current) : await reads.removeFirst().future;
    } finally {
      concurrent--;
    }
  }

  @override
  Future<void> setSettings({required InAppWebViewSettings settings}) {
    final done = _writeSettings(settings);
    final afterWrite = afterNextWrite;
    afterNextWrite = null;
    if (afterWrite != null) {
      unawaited(done.then((_) => scheduleMicrotask(afterWrite)));
    }
    return done;
  }

  Future<void> _writeSettings(InAppWebViewSettings settings) async {
    _begin();
    final snapshot = _copy(settings);
    attempts.add(snapshot);
    try {
      if (writes.isNotEmpty) await writes.removeFirst().future;
      current = snapshot;
    } finally {
      concurrent--;
    }
  }
}

void main() {
  late List<Object> errors;
  late PluginWebViewSettingsUpdater updater;
  late _Controller native;
  late InAppWebViewController controller;

  setUp(() {
    errors = [];
    updater = PluginWebViewSettingsUpdater(onError: errors.add);
    native = _Controller();
    controller = InAppWebViewController.fromPlatform(platform: native);
  });

  tearDown(() => updater.dispose());

  Future<void> attach() => updater.attach(
    controller,
    consoleMessageLevels: pluginWarningAndErrorConsoleLevels,
    contentBlockers: _rules('initial'),
  );

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test(
    'initial matching settings need no write; console preserves security settings',
    () async {
      await attach();
      expect(native.attempts, isEmpty);
      await updater.setConsoleMessageLevels(null);
      expect(native.current.consoleMessageLevels, isNull);
      expect(
        native.current.contentBlockers!.single.trigger.urlFilter,
        'initial',
      );
      expect(native.current.allowUniversalAccessFromFileURLs, isFalse);
      expect(native.current.useOnRenderProcessGone, isTrue);
      expect(native.current.resourceCustomSchemes, ['otzaria-plugin']);
      expect(native.current.cacheEnabled, isFalse);
      expect(errors, isEmpty);
    },
  );

  test('rapid toggles coalesce behind one pending native read', () async {
    await attach();
    final gate = Completer<InAppWebViewSettings?>();
    native.reads.add(gate);
    final pending = updater.setConsoleMessageLevels(null);
    for (var i = 0; i < 100; i++) {
      unawaited(
        updater.setConsoleMessageLevels(
          i.isEven ? pluginWarningAndErrorConsoleLevels : null,
        ),
      );
    }
    expect(native.readCount, 2);
    gate.complete(_copy(native.current));
    await pending;
    expect(native.attempts, hasLength(1));
    expect(native.current.consoleMessageLevels, isNull);
    expect(native.maxConcurrent, 1);
    expect(errors, isEmpty);
  });

  for (final microtasks in [0, 1, 2]) {
    test(
      'a security request awaits its write at completion boundary $microtasks',
      () async {
        await attach();
        final consoleGate = Completer<void>();
        final securityGate = Completer<void>();
        native.writes.addAll([consoleGate, securityGate]);
        Future<void>? security;
        var completed = false;
        var remaining = microtasks;
        void queueSecurity() {
          if (remaining-- > 0) {
            scheduleMicrotask(queueSecurity);
            return;
          }
          security = updater
              .setContentBlockers(_rules('deny-all'))
              .then((_) => completed = true);
        }

        native.afterNextWrite = queueSecurity;
        final update = updater.setConsoleMessageLevels(null);
        await flush();
        consoleGate.complete();
        await flush();
        try {
          expect(native.attempts, hasLength(2));
          expect(security, isNotNull);
          expect(
            completed,
            isFalse,
            reason: 'The queued security write is still pending.',
          );
        } finally {
          securityGate.complete();
          await Future.wait([update, if (security != null) security!]);
        }
        expect(
          native.current.contentBlockers!.single.trigger.urlFilter,
          'deny-all',
        );
        expect(errors, isEmpty);
      },
    );
  }

  test(
    'a console change waits for a blocked network update and preserves the latest restriction',
    () async {
      await attach();
      final gate = Completer<void>();
      native.writes.add(gate);
      final security = updater.setContentBlockers(_rules('strict'));
      await flush();
      expect(
        native.attempts.single.contentBlockers!.single.trigger.urlFilter,
        'strict',
      );
      final console = updater.setConsoleMessageLevels(null);
      final newestSecurity = updater.setContentBlockers(_rules('strictest'));
      await flush();
      expect(
        native.readCount,
        2,
        reason: 'A stale settings read must not overlap the in-flight write.',
      );
      gate.complete();
      await Future.wait([security, console, newestSecurity]);
      expect(native.current.consoleMessageLevels, isNull);
      expect(
        native.current.contentBlockers!.single.trigger.urlFilter,
        'strictest',
      );
      expect(native.maxConcurrent, 1);
      expect(errors, isEmpty);
    },
  );

  test(
    'a failed console write cannot discard a pending security update',
    () async {
      await attach();
      final gate = Completer<void>();
      native.writes.add(gate);
      final console = updater.setConsoleMessageLevels(null);
      await flush();
      final security = updater.setContentBlockers(_rules('deny-all'));
      final newestConsole = updater.setConsoleMessageLevels(
        pluginWarningAndErrorConsoleLevels,
      );
      gate.completeError(StateError('console write failed'));
      await Future.wait([console, security, newestConsole]);
      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains('console write failed'));
      expect(
        native.current.contentBlockers!.single.trigger.urlFilter,
        'deny-all',
      );
      expect(
        native.current.consoleMessageLevels,
        pluginWarningAndErrorConsoleLevels,
      );
      expect(native.attempts, hasLength(2));
      expect(native.maxConcurrent, 1);
    },
  );

  test(
    'failed content blockers remain reported and are retried on the next request',
    () async {
      await attach();
      final gate = Completer<void>();
      native.writes.add(gate);
      final security = updater.setContentBlockers(_rules('deny-all'));
      await flush();
      gate.completeError(StateError('content blockers rejected'));
      await security;
      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains('content blockers rejected'));
      expect(
        native.current.contentBlockers!.single.trigger.urlFilter,
        'initial',
      );
      expect(
        native.attempts,
        hasLength(1),
        reason: 'A persistent native failure must not cause a retry loop.',
      );
      await updater.setConsoleMessageLevels(null);
      expect(
        native.current.contentBlockers!.single.trigger.urlFilter,
        'deny-all',
      );
      expect(native.current.consoleMessageLevels, isNull);
    },
  );

  test(
    'a failed read still permits the newer pending security request',
    () async {
      await attach();
      final gate = Completer<InAppWebViewSettings?>();
      native.reads.add(gate);
      final console = updater.setConsoleMessageLevels(null);
      final security = updater.setContentBlockers(_rules('deny-all'));
      gate.completeError(StateError('read failed'));
      await Future.wait([console, security]);
      expect(errors, hasLength(1));
      expect(native.current.consoleMessageLevels, isNull);
      expect(
        native.current.contentBlockers!.single.trigger.urlFilter,
        'deny-all',
      );
      expect(native.maxConcurrent, 1);
    },
  );

  test(
    'a null settings response waits for another request without losing desired rules',
    () async {
      await attach();
      final gate = Completer<InAppWebViewSettings?>();
      native.reads.add(gate);
      final security = updater.setContentBlockers(_rules('deny-all'));
      gate.complete(null);
      await security;
      expect(native.attempts, isEmpty);
      await updater.setConsoleMessageLevels(null);
      expect(
        native.current.contentBlockers!.single.trigger.urlFilter,
        'deny-all',
      );
      expect(errors, isEmpty);
    },
  );

  for (final lateError in [false, true]) {
    test(
      'replacement completes before the old read ${lateError ? 'fails' : 'succeeds'} without stale writes',
      () async {
        final gate = Completer<InAppWebViewSettings?>();
        native.reads.add(gate);
        final oldAttach = attach();
        final replacement = _Controller();
        await updater.attach(
          InAppWebViewController.fromPlatform(platform: replacement),
          consoleMessageLevels: null,
          contentBlockers: _rules('replacement-only'),
        );
        expect(
          replacement.current.contentBlockers!.single.trigger.urlFilter,
          'replacement-only',
        );
        if (lateError) {
          gate.completeError(StateError('obsolete read'));
        } else {
          gate.complete(_copy(native.current));
        }
        await oldAttach;
        expect(native.attempts, isEmpty);
        expect(replacement.attempts, hasLength(1));
        expect(replacement.current.consoleMessageLevels, isNull);
        expect(errors, isEmpty);
      },
    );
  }

  test(
    'disposal invalidates a pending read and ignores later attachment',
    () async {
      final gate = Completer<InAppWebViewSettings?>();
      native.reads.add(gate);
      final pending = attach();
      unawaited(updater.setConsoleMessageLevels(null));
      updater.dispose();
      gate.complete(_copy(native.current));
      await pending;
      await attach();
      expect(native.readCount, 1);
      expect(native.attempts, isEmpty);
      expect(errors, isEmpty);
    },
  );

  test(
    'keepAlive ownership across wrappers serializes an old write before the new policy',
    () async {
      await attach();
      final gate = Completer<void>();
      native.writes.add(gate);
      final oldWrite = updater.setConsoleMessageLevels(null);
      await flush();
      final replacementErrors = <Object>[];
      final replacement = PluginWebViewSettingsUpdater(
        onError: replacementErrors.add,
      );
      addTearDown(replacement.dispose);
      final attached = replacement.attach(
        InAppWebViewController.fromPlatform(platform: native),
        consoleMessageLevels: pluginWarningAndErrorConsoleLevels,
        contentBlockers: _rules('replacement-only'),
      );
      await updater.setContentBlockers(_rules('obsolete'));
      updater.dispose();
      expect(native.readCount, 2);
      gate.complete();
      await Future.wait([oldWrite, attached]);
      expect(
        native.current.contentBlockers!.single.trigger.urlFilter,
        'replacement-only',
      );
      expect(
        native.current.consoleMessageLevels,
        pluginWarningAndErrorConsoleLevels,
      );
      expect(native.maxConcurrent, 1);
      expect(errors, isEmpty);
      expect(replacementErrors, isEmpty);
    },
  );
}
