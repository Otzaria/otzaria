import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/bridge/plugin_semantic_bridge.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';

void main() {
  test('זרם סמנטי עוצר בביטול ומשלח רק למסמך שהתחיל אותו', () async {
    try {
      if ((await Process.run('node', ['--version'])).exitCode != 0) {
        markTestSkipped('node אינו זמין');
        return;
      }
    } on ProcessException {
      markTestSkipped('node אינו זמין');
      return;
    }

    final boot = buildPluginBootScript(nonceJson: '"test"', payloadJson: '{}');
    final oldDocument = List.filled(16, '01').join();
    final dispatch = PluginBridgeHandler.eventDispatchScript(
      PluginSemanticBridge.streamEvent,
      {
        'streamId': 'semantic_${oldDocument}_1',
        'chunk': {'type': 'hits', 'hits': []},
      },
    );
    final harness =
        '''
var assert = require('node:assert/strict');
var CustomEvent = class extends Event {
  constructor(name, options) {
    super(name);
    this.detail = options.detail;
  }
};
var window;
var calls = [];
var finish;
var deadline = setTimeout(function () {
  console.error('The SDK did not complete the iterator test');
  process.exit(1);
}, 3000);
function boot(byte) {
  window = new EventTarget();
  window.crypto = { getRandomValues: function (bytes) { return bytes.fill(byte); } };
  window.flutter_inappwebview = {
    callHandler: function (name, request) {
      calls.push(request);
      if (request.payload.__cancelStreamId) return Promise.resolve();
      return new Promise(function (resolve) { finish = resolve; });
    }
  };
  $pluginSdkStubScript
  $boot
}
(async function () {
  boot(1);
  var payload = { from: [{ text: 'א' }] };
  var stream = window.Otzaria.call('semantic.nearest', payload);
  var first = stream.next();
  $dispatch
  assert.equal((await first).value.type, 'hits');
  $dispatch
  finish({ success: false, error: { code: 'error.permission_denied', retryable: false } });
  await Promise.resolve();
  await assert.rejects(stream.next(), { code: 'error.permission_denied', retryable: false });

  boot(2);
  var received = 0;
  window.addEventListener('${PluginSemanticBridge.streamEvent}', function () { received++; });
  var next = window.Otzaria.call('semantic.nearest', payload);
  $dispatch
  assert.equal(received, 0);
  var active = next.next();
  assert.equal((await next.return()).done, true);
  assert.equal((await active).done, true);
  assert.equal(calls[2].payload.__cancelStreamId, calls[1].payload.__streamId);
})().then(
  function () { clearTimeout(deadline); },
  function (error) { clearTimeout(deadline); console.error(error); process.exitCode = 1; }
);
''';

    final result = await Process.run('node', ['-e', harness]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
}
