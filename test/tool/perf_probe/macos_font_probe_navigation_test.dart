import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// The platform package is pinned by the app's dependency override.
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_macos/flutter_inappwebview_macos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';

import '../../../integration_test/macos_plugin_font_probe_test.dart';
import '../../../integration_test/support/macos_font_probe.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _CapturePlatform platform;
  late InAppWebViewPlatform previous;

  setUp(() {
    previous = InAppWebViewPlatform.instance ?? _CapturePlatform();
    platform = _CapturePlatform();
    InAppWebViewPlatform.instance = platform;
  });
  tearDown(() => InAppWebViewPlatform.instance = previous);

  Future<
    ({
      MacOSInAppWebViewController controller,
      FontProbeViewProgress progress,
      Completer<MacosFontProbeResult> completed,
    })
  >
  mount(
    WidgetTester tester,
    String scenario,
  ) async {
    final completed = Completer<MacosFontProbeResult>();
    unawaited(completed.future.then<void>((_) {}, onError: (Object _) {}));
    final progress = FontProbeViewProgress(0);
    await tester.pumpWidget(
      MaterialApp(
        home: MacosFontProbeView(
          root: '/unused/font-probe',
          scenario: scenario,
          csp: "default-src 'none'",
          theme: const {},
          specs: const [],
          index: 0,
          completed: completed,
          progress: progress,
        ),
      ),
    );
    final params = platform.views.single;
    expect(params.initialSettings!.useShouldOverrideUrlLoading, isTrue);
    final controller = MacOSInAppWebViewController(
      MacOSInAppWebViewControllerCreationParams(
        id: 'font-policy',
        webviewParams: params,
      ),
    );
    addTearDown(controller.dispose);
    params.onWebViewCreated!(params.controllerFromPlatform!(controller));
    return (controller: controller, progress: progress, completed: completed);
  }

  Future<Object?> decide(String? url, {bool mainFrame = true}) async {
    const codec = StandardMethodCodec();
    final reply = Completer<ByteData?>();
    binding.channelBuffers.push(
      'com.pichillilorenzo/flutter_inappwebview_font-policy',
      codec.encodeMethodCall(
        MethodCall('shouldOverrideUrlLoading', {
          'request': {'url': url, 'method': 'GET'},
          'isForMainFrame': mainFrame,
        }),
      ),
      reply.complete,
    );
    return codec.decodeEnvelope((await reply.future)!);
  }

  test(
    'enabling the native gate without a callback returns no allow reply',
    () async {
      final controller = MacOSInAppWebViewController(
        MacOSInAppWebViewControllerCreationParams(
          id: 'font-policy',
          webviewParams: PlatformInAppWebViewWidgetCreationParams(
            initialSettings: buildPluginTabWebViewSettings(
              isDevelopment: false,
            ),
          ),
        ),
      );
      addTearDown(controller.dispose);
      expect(await decide('otzaria-plugin://font.probe/normal.html'), isNull);
    },
  );

  for (final scenario in ['normal', 'font-src-data', 'style-src-none']) {
    testWidgets(
      'the actual $scenario fixture explicitly allows its first document',
      (tester) async {
        final fixture = await mount(tester, scenario);
        final url = 'otzaria-plugin://font.probe/$scenario.html';
        expect(await decide(url), NavigationActionPolicy.ALLOW.toNativeValue());
        expect(fixture.progress.report['status'], 'pending');
        expect(
          (fixture.progress.report['events'] as List).last,
          containsPair('policy', 'allow'),
        );
      },
    );
  }

  final blocked = <({String? url, bool mainFrame})>[
    (url: 'otzaria-plugin://font.probe/other.html', mainFrame: true),
    (url: 'otzaria-plugin://font.probe/normal.html?changed', mainFrame: true),
    (url: 'otzaria-plugin://font.probe/normal.html#changed', mainFrame: true),
    (url: 'otzaria-plugin://font.probe:9/normal.html', mainFrame: true),
    (url: 'otzaria-plugin://font.probe.evil/normal.html', mainFrame: true),
    (url: 'otzaria-plugin://font.probe@evil/normal.html', mainFrame: true),
    (url: 'https://font.probe/normal.html', mainFrame: true),
    (url: 'file:///normal.html', mainFrame: true),
    (url: null, mainFrame: true),
    (url: 'otzaria-plugin://font.probe/normal.html', mainFrame: false),
  ];
  for (final request in blocked) {
    testWidgets('unexpected document is cancelled: $request', (tester) async {
      final fixture = await mount(tester, 'normal');
      final failed = expectLater(fixture.completed.future, throwsStateError);
      expect(
        await decide(request.url, mainFrame: request.mainFrame),
        NavigationActionPolicy.CANCEL.toNativeValue(),
      );
      await failed;
      expect(fixture.progress.report['status'], 'failed');
      expect(
        (fixture.progress.report['events'] as List)
            .where((dynamic e) => e['event'] == 'navigation-decision')
            .single,
        containsPair('policy', 'cancel'),
      );
    });
  }

  testWidgets('disposed fixture never authorizes a late native request', (
    tester,
  ) async {
    final fixture = await mount(tester, 'normal');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      await decide('otzaria-plugin://font.probe/normal.html'),
      NavigationActionPolicy.CANCEL.toNativeValue(),
    );
    expect(fixture.progress.isActive, isFalse);
  });
}

class _CapturePlatform extends InAppWebViewPlatform {
  final views = <PlatformInAppWebViewWidgetCreationParams>[];
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    views.add(params);
    return _CaptureView(params);
  }
}

class _CaptureView extends PlatformInAppWebViewWidget {
  _CaptureView(super.params) : super.implementation();
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      (params.controllerFromPlatform?.call(controller) ?? controller) as T;
  @override
  Widget build(BuildContext context) => const SizedBox();
  @override
  void dispose() {}
}
