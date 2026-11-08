import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_font_bootstrap.dart';
import 'package:otzaria/plugins/services/plugin_font_scheme.dart';
import 'package:otzaria/plugins/services/plugin_fonts.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';

class _Controller extends Fake implements InAppWebViewController {
  _Controller({
    this.schemeReason = 'loaded',
    this.dataReason = 'loaded',
    this.markerId = 'document-1',
    this.markerError,
    this.bindingError,
    this.bindingThrows = false,
  });

  final String schemeReason;
  final String dataReason;
  final Object? markerId;
  final String? markerError;
  final String? bindingError;
  final bool bindingThrows;
  final calls = <({String body, Map<String, dynamic> arguments})>[];
  final bootSources = <String>[];
  Completer<void>? pendingReply;
  Completer<void>? pendingBindingReply;
  Future<Object?> Function(String source)? onBoot;
  Object? bootReply;

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const {},
    ContentWorld? contentWorld,
  }) async {
    final index = calls.length;
    calls.add((body: functionBody, arguments: arguments));
    if (pendingReply != null) await pendingReply!.future;
    final css = arguments['css'];
    if (css is! String) {
      if (index == 0) {
        return CallAsyncJavaScriptResult(
          value: {
            'ready': true,
            'reason': 'document-claimed',
            'documentId': markerId,
          },
          error: markerError,
        );
      }
      if (pendingBindingReply != null) await pendingBindingReply!.future;
      if (bindingThrows) throw StateError('Native JavaScript error');
      return CallAsyncJavaScriptResult(
        value: {'ready': true, 'reason': 'document-bound'},
        error: bindingError,
      );
    }
    final reason = css.contains('data:') ? dataReason : schemeReason;
    return CallAsyncJavaScriptResult(
      value: {'ready': reason == 'loaded', 'reason': reason},
    );
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    bootSources.add(source);
    return onBoot == null ? bootReply : await onBoot!(source);
  }
}

const _bootSource = '(function(){boots++;return [];})();';

Future<Map<String, dynamic>> _executeBoot(
  String source, {
  String? documentId = 'document-1',
  String? owner,
  String beforeBoot = '',
}) async {
  final process = await Process.run('node', [
    '-e',
    '''
let boots = 0;
const document = {
  __otzariaFontDocumentId: ${jsonEncode(documentId)},
  __otzariaFontBootAttempt: ${jsonEncode(owner)}
};
$beforeBoot
const value = eval(${jsonEncode(source)});
console.log(JSON.stringify({boots, value}));
''',
  ]);
  expect(process.exitCode, 0, reason: process.stderr.toString());
  return Map<String, dynamic>.from(
    jsonDecode(process.stdout.toString()) as Map,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const theme = {
    'typography': {
      'fontFamily': 'FrankRuhlCLM',
      'commentatorsFontFamily': 'NotoRashiHebrew',
      'uiFontFamily': 'Rubik',
    },
  };
  late PluginFontSchemeLease lease;
  setUp(() {
    debugResetPluginFonts();
    lease = PluginFontSchemeLease(origin: 'otzaria-plugin://test.plugin');
  });
  tearDown(() {
    lease.dispose();
    debugResetPluginFonts();
  });

  test(
    'scheme keeps CSS small and reports exactly the submitted UTF-8 payloads',
    () async {
      final controller = _Controller();
      final result = await preparePluginFontExperiment(
        controller,
        lease: lease,
        theme: theme,
        isCurrent: () => true,
      );
      expect(result.ready, isTrue);
      expect(result.transport, 'scheme');
      expect(result.schemeFailure, isNull);
      expect(result.cssUtf8Bytes, lessThan(5000));
      expect(
        result.argumentJsonUtf8Bytes,
        controller.calls.fold<int>(
          0,
          (sum, call) => sum + utf8.encode(jsonEncode(call.arguments)).length,
        ),
      );
      expect(
        result.javascriptUtf8Bytes,
        controller.calls.fold<int>(
          0,
          (sum, call) => sum + utf8.encode(call.body).length,
        ),
      );
      expect(
        lease.responseBytes,
        0,
        reason: 'registering CSS does not read fonts',
      );
    },
  );

  test(
    'queued boot runs only in its own document and preparation attempt',
    () async {
      final result = await preparePluginFontExperiment(
        _Controller(),
        lease: lease,
        theme: theme,
        isCurrent: () => true,
      );
      final source = result.guardBoot(_bootSource);
      final current = await _executeBoot(source, owner: lease.id);
      expect(current['boots'], 1);
      expect(current['value'], {
        'booted': true,
        'documentId': 'document-1',
        'owner': lease.id,
        'eventOptions': <dynamic>[],
      });
      for (final (documentId, owner) in [
        ('document-2', lease.id),
        ('document-1', 'replacement-attempt'),
      ]) {
        final stale = await _executeBoot(
          source,
          documentId: documentId,
          owner: owner,
        );
        expect(stale['boots'], 0);
        expect(stale['value'], {'booted': false, 'reason': 'stale-document'});
      }
    },
  );

  for (final failure in ['timeout', 'native-error', 'exception']) {
    test('known identity still fences boot after binding $failure', () async {
      final controller = _Controller(
        bindingError: failure == 'native-error' ? 'native error' : null,
        bindingThrows: failure == 'exception',
      );
      if (failure == 'timeout') {
        controller.pendingBindingReply = Completer<void>();
        addTearDown(() => controller.pendingBindingReply!.complete());
      }
      final result = await preparePluginFontExperiment(
        controller,
        lease: lease,
        theme: theme,
        isCurrent: () => true,
        timeout: const Duration(milliseconds: 50),
      );
      expect(result.ready, isFalse);
      expect(result.documentBound, isFalse);
      expect(result.documentId, 'document-1');
      expect(
        result.outcome['reason'],
        switch (failure) {
          'timeout' => 'preparation-timeout',
          'native-error' => 'javascript-unavailable',
          _ => 'preparation-error',
        },
      );
      final source = result.guardBoot(_bootSource);
      expect((await _executeBoot(source, owner: lease.id))['boots'], 1);
      for (final (id, owner) in [
        ('replacement-document', lease.id),
        ('document-1', 'replacement-attempt'),
        ('document-1', null),
      ]) {
        final skipped = await _executeBoot(
          source,
          documentId: id,
          owner: owner,
        );
        expect(skipped['boots'], 0);
        expect(skipped['value'], {'booted': false, 'reason': 'stale-document'});
      }
    });
  }

  for (final marker in [null, '', 42]) {
    test('missing or malformed marker $marker never schedules boot', () async {
      final controller = _Controller(markerId: marker);
      final result = await preparePluginFontExperiment(
        controller,
        lease: lease,
        theme: theme,
        isCurrent: () => true,
      );
      expect(result.ready, isFalse);
      expect(result.documentId, isNull);
      expect(result.documentBound, isFalse);
      expect(controller.calls, hasLength(1));
      final skipped = await _executeBoot(
        result.guardBoot(_bootSource),
        owner: lease.id,
      );
      expect(skipped['boots'], 0);
      expect(skipped['value'], {
        'booted': false,
        'reason': 'document-identity-unavailable',
      });
      await expectLater(
        result.evaluateBoot(
          controller,
          source: _bootSource,
          isCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(controller.bootSources, isEmpty);
    });
  }

  test('native marker error cannot schedule a boot', () async {
    final controller = _Controller(markerError: 'JavaScript unavailable');
    final result = await preparePluginFontExperiment(
      controller,
      lease: lease,
      theme: theme,
      isCurrent: () => true,
    );
    expect(result.outcome['reason'], 'javascript-unavailable');
    expect(result.documentId, isNull);
    expect(controller.calls, hasLength(1));
    await expectLater(
      result.evaluateBoot(
        controller,
        source: _bootSource,
        isCurrent: () => true,
      ),
      throwsStateError,
    );
    expect(controller.bootSources, isEmpty);
  });

  test('boot requires matching acknowledgement and event options', () async {
    final controller = _Controller();
    final result = await preparePluginFontExperiment(
      controller,
      lease: lease,
      theme: theme,
      isCurrent: () => true,
    );
    final good = {
      'booted': true,
      'documentId': 'document-1',
      'owner': lease.id,
      'eventOptions': [
        {'topic': 'book.opened', 'rawDivineNames': true},
      ],
    };
    for (final response in [
      null,
      [],
      {'booted': false, 'reason': 'stale-document'},
      {...good, 'documentId': 'replacement'},
      {...good, 'owner': 'replacement'},
      {...good, 'eventOptions': null},
    ]) {
      controller.bootReply = response;
      await expectLater(
        result.evaluateBoot(
          controller,
          source: _bootSource,
          isCurrent: () => true,
        ),
        throwsStateError,
      );
    }
    controller.bootReply = good;
    final boot = await result.evaluateBoot(
      controller,
      source: _bootSource,
      isCurrent: () => true,
    );
    expect(boot.eventOptions, good['eventOptions']);
    expect(
      boot.javascriptUtf8Bytes,
      utf8.encode(controller.bootSources.last).length,
    );
  });

  for (final guarded in [false, true]) {
    test(
      'real SDK boots synchronously ${guarded ? 'with a font guard' : 'without a font guard'}',
      () async {
        final controller = _Controller(
          bindingError: 'font binding unavailable',
        );
        final preparation = await preparePluginFontExperiment(
          controller,
          lease: lease,
          theme: theme,
          isCurrent: () => true,
        );
        expect(preparation.ready, isFalse);
        controller.onBoot = (source) async {
          final process = await Process.run('node', [
            '-e',
            '''
const document = {
  __otzariaFontDocumentId: 'document-1',
  __otzariaFontBootAttempt: ${jsonEncode(lease.id)}
};
const listeners = new Map();
let ready = 0, boots = 0;
const window = {
  addEventListener(type, fn) {
    if (!listeners.has(type)) listeners.set(type, []);
    listeners.get(type).push(fn);
  },
  removeEventListener(type, fn) {
    listeners.set(type, (listeners.get(type) || []).filter(f => f !== fn));
  },
  dispatchEvent(event) {
    for (const fn of listeners.get(event.type) || []) fn(event);
  }
};
class CustomEvent {
  constructor(type, options) { this.type = type; this.detail = options.detail; }
}
eval(${jsonEncode(pluginSdkStubScript)});
window.addEventListener('plugin.ready', () => ready++);
window.addEventListener('plugin.boot', () => boots++);
window.Otzaria.on('book.opened', () => {}, {rawDivineNames: true});
const value = eval(${jsonEncode(source)});
console.log(JSON.stringify({value, ready, boots,
  isPromise: !!value && typeof value.then === 'function',
  eventOptionsPromise: !!value?.eventOptions && typeof value.eventOptions.then === 'function'}));
''',
          ]);
          expect(process.exitCode, 0, reason: process.stderr.toString());
          final output = jsonDecode(process.stdout.toString()) as Map;
          expect(output['ready'], 1);
          expect(output['boots'], 1);
          expect(output['isPromise'], isFalse);
          expect(output['eventOptionsPromise'], isFalse);
          return output['value'];
        };
        final source = buildPluginBootScript(
          nonceJson: jsonEncode('font-test'),
          payloadJson: jsonEncode({'theme': theme}),
        );
        final eventOptions = guarded
            ? (await preparation.evaluateBoot(
                controller,
                source: source,
                isCurrent: () => true,
              )).eventOptions
            : await controller.evaluateJavascript(source: source);
        expect(eventOptions, [
          {'topic': 'book.opened', 'rawDivineNames': true},
        ]);
      },
    );
  }

  test(
    'navigation before queued native execution cannot report boot success',
    () async {
      final controller = _Controller(bindingError: 'font binding unavailable');
      final result = await preparePluginFontExperiment(
        controller,
        lease: lease,
        theme: theme,
        isCurrent: () => true,
      );
      controller.onBoot = (source) async {
        final native = await _executeBoot(
          source,
          documentId: 'replacement-document',
          owner: lease.id,
        );
        expect(native['boots'], 0);
        return native['value'];
      };
      await expectLater(
        result.evaluateBoot(
          controller,
          source: _bootSource,
          isCurrent: () => true,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'a Dart generation change rejects even a matching native acknowledgement',
    () async {
      var current = true;
      final controller = _Controller();
      final result = await preparePluginFontExperiment(
        controller,
        lease: lease,
        theme: theme,
        isCurrent: () => current,
      );
      controller.onBoot = (source) async {
        final native = await _executeBoot(source, owner: lease.id);
        expect(native['boots'], 1);
        current = false;
        return native['value'];
      };
      await expectLater(
        result.evaluateBoot(
          controller,
          source: _bootSource,
          isCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(controller.bootSources, hasLength(1));
      await expectLater(
        result.evaluateBoot(
          controller,
          source: _bootSource,
          isCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(controller.bootSources, hasLength(1));
    },
  );

  test(
    'boot acknowledgement is bounded and late queued source expires',
    () async {
      final controller = _Controller();
      final result = await preparePluginFontExperiment(
        controller,
        lease: lease,
        theme: theme,
        isCurrent: () => true,
      );
      final pending = Completer<Object?>();
      controller.onBoot = (_) => pending.future;
      await expectLater(
        result.evaluateBoot(
          controller,
          source: _bootSource,
          isCurrent: () => true,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      final late = await _executeBoot(
        controller.bootSources.single,
        owner: lease.id,
      );
      expect(late['boots'], 0);
      expect(late['value'], {'booted': false, 'reason': 'boot-expired'});
      pending.complete(late['value']);
    },
  );

  test(
    'scheme denial tries embedded data and waits for its result before boot',
    () async {
      final controller = _Controller(schemeReason: 'font-load-failed');
      final result = await preparePluginFontExperiment(
        controller,
        lease: lease,
        theme: theme,
        isCurrent: () => true,
      );
      expect(result.transport, 'data');
      expect(result.ready, isTrue);
      expect(result.schemeFailure, 'font-load-failed');
      final installs = controller.calls
          .where((call) => call.arguments['css'] != null)
          .toList();
      expect(installs, hasLength(2));
      expect(installs.first.arguments['css'], contains('__otzaria_fonts__'));
      expect(installs.last.arguments['css'], contains('data:font/ttf;base64,'));
      expect(
        installs.last.arguments['targets'],
        contains('bold 16px "FrankRuhlCLM"'),
      );
      expect(
        installs.last.arguments['targets'],
        contains('bold 16px "NotoRashiHebrew"'),
      );
      expect(installs.last.arguments['targets'], contains('16px "Rubik"'));
    },
  );

  test(
    'style CSP remains explicitly unavailable after the data attempt',
    () async {
      final controller = _Controller(
        schemeReason: 'style-blocked',
        dataReason: 'style-blocked',
      );
      final result = await preparePluginFontExperiment(
        controller,
        lease: lease,
        theme: theme,
        isCurrent: () => true,
      );
      expect(result.ready, isFalse);
      expect(result.transport, 'unavailable');
      expect(result.outcome['reason'], 'style-blocked');
      expect(result.schemeFailure, 'style-blocked');
      final boot = await _executeBoot(
        result.guardBoot(_bootSource),
        owner: lease.id,
      );
      expect(boot['boots'], 1);
      expect((boot['value'] as Map)['eventOptions'], isEmpty);
    },
  );

  test(
    'releasing a host during a pending callback prevents later installation',
    () async {
      final controller = _Controller()..pendingReply = Completer<void>();
      final pending = preparePluginFontExperiment(
        controller,
        lease: lease,
        theme: theme,
        isCurrent: () => true,
      );
      lease.dispose();
      controller.pendingReply!.complete();
      final result = await pending;
      expect(result.ready, isFalse);
      expect(result.outcome['reason'], 'stale-document');
      expect(controller.calls, hasLength(1));
      expect(controller.calls.single.arguments['css'], isNull);
    },
  );

  test('a native reply that never returns cannot hang plugin boot', () async {
    final controller = _Controller()..pendingReply = Completer<void>();
    final result = await preparePluginFontExperiment(
      controller,
      lease: lease,
      theme: theme,
      isCurrent: () => true,
      timeout: const Duration(milliseconds: 20),
    );
    expect(result.ready, isFalse);
    expect(result.outcome['reason'], 'preparation-timeout');
    expect(result.elapsedMicroseconds, lessThan(1000000));
    expect(result.documentId, isNull);
    expect(result.documentBound, isFalse);
    await expectLater(
      result.evaluateBoot(
        controller,
        source: _bootSource,
        isCurrent: () => true,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Plugin boot: document-identity-unavailable',
        ),
      ),
    );
    expect(controller.bootSources, isEmpty);
    controller.pendingReply!.complete();
  });

  test('data control uses embedded CSS without scheme registrations', () async {
    final controller = _Controller();
    final result = await preparePluginFontExperiment(
      controller,
      lease: lease,
      theme: theme,
      isCurrent: () => true,
      useScheme: false,
    );
    expect(result.transport, 'data');
    expect(result.ready, isTrue);
    expect(result.cssUtf8Bytes, greaterThan(100000));
    expect(
      controller.calls.last.arguments['css'],
      isNot(contains('__otzaria_fonts__')),
    );
    expect(lease.requestCount, 0);
  });
}
