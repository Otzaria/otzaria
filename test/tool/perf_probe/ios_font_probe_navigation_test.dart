import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// The platform package is pinned by the app's dependency override.
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_ios/flutter_inappwebview_ios.dart' as ios;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';

import '../../../integration_test/support/apple_font_probe_view.dart';
import '../../../integration_test/support/ios_font_probe.dart';
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
      ios.IOSInAppWebViewController controller,
      FontProbeViewProgress progress,
      Completer<AppleFontProbeResult> completed,
    })
  >
  mount(
    WidgetTester tester,
    IosFontProbeCase config,
  ) async {
    final completed = Completer<AppleFontProbeResult>();
    unawaited(completed.future.then<void>((_) {}, onError: (Object _) {}));
    final progress = FontProbeViewProgress(0);
    await tester.pumpWidget(
      MaterialApp(
        home: AppleFontProbeView(
          root: '/unused/font-probe',
          scenario: config.scenario,
          csp: config.csp,
          theme: iosFontProbeTheme,
          specs: iosFontProbeSpecs,
          index: 0,
          completed: completed,
          progress: progress,
          documentUrl: config.documentUrl('/unused/font-probe'),
          fontOrigin: iosFontProbeOrigin,
          pluginId: iosFontProbePluginId,
          appPlatform: 'ios',
          useScheme: config.useScheme,
          settings: config.settings,
          capturePolicyDiagnostics: true,
          navigationUrl: config.documentUrl(
            '/unused/font-probe',
            navigation: true,
          ),
        ),
      ),
    );
    final params = platform.views.single;
    expect(params.initialSettings!.useShouldOverrideUrlLoading, isTrue);
    final controller = ios.IOSInAppWebViewController(
      ios.IOSInAppWebViewControllerCreationParams(
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
      final controller = ios.IOSInAppWebViewController(
        ios.IOSInAppWebViewControllerCreationParams(
          id: 'font-policy',
          webviewParams: PlatformInAppWebViewWidgetCreationParams(
            initialSettings: buildPluginTabWebViewSettings(
              isDevelopment: false,
            ),
          ),
        ),
      );
      addTearDown(controller.dispose);
      expect(await decide('file:///unused/font-probe/normal.html'), isNull);
    },
  );

  const root = '/unused/font-probe';
  for (final config in iosFontProbeCases) {
    testWidgets(
      'iOS ${config.id} permits exact initial and deliberate replacement',
      (tester) async {
        final fixture = await mount(tester, config);
        expect(
          await decide(config.documentUrl(root)),
          NavigationActionPolicy.ALLOW.toNativeValue(),
        );
        expect(fixture.progress.report['status'], 'pending');
        fixture.progress.complete();
        expect(
          await decide(config.documentUrl(root, navigation: true)),
          NavigationActionPolicy.ALLOW.toNativeValue(),
        );
        expect(fixture.progress.report['status'], 'completed');
      },
    );
  }

  const config = IosFontProbeCase(
    IosFontProbeRoute.fileProductionPolicy,
    'normal',
    true,
  );
  testWidgets('replacement before preparation completes is cancelled', (
    tester,
  ) async {
    final fixture = await mount(tester, config);
    expect(
      await decide(config.documentUrl(root, navigation: true)),
      NavigationActionPolicy.CANCEL.toNativeValue(),
    );
    expect(fixture.completed.isCompleted, isTrue);
    await expectLater(fixture.completed.future, throwsStateError);
  });

  for (final request in <({String? url, bool mainFrame})>[
    (
      url: '${config.documentUrl(root, navigation: true)}?changed',
      mainFrame: true,
    ),
    (
      url: '${config.documentUrl(root, navigation: true)}#changed',
      mainFrame: true,
    ),
    (url: 'file:///another/plugin.html', mainFrame: true),
    (url: '$iosFontProbeOrigin/foreign.html', mainFrame: true),
    (url: config.documentUrl(root, navigation: true), mainFrame: false),
    (url: null, mainFrame: true),
  ]) {
    testWidgets('completed iOS view rejects unexpected navigation: $request', (
      tester,
    ) async {
      final fixture = await mount(tester, config);
      fixture.progress.complete();
      expect(
        await decide(request.url, mainFrame: request.mainFrame),
        NavigationActionPolicy.CANCEL.toNativeValue(),
      );
      expect(fixture.completed.isCompleted, isTrue);
      await expectLater(fixture.completed.future, throwsStateError);
      expect(fixture.progress.report['status'], 'failed');
    });
  }

  testWidgets('disposed iOS fixture rejects its authorized replacement', (
    tester,
  ) async {
    final fixture = await mount(tester, config);
    fixture.progress.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      await decide(config.documentUrl(root, navigation: true)),
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
