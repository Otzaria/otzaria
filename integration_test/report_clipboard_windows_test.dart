import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app_report/services/app_report_image_sources.dart';
import 'package:super_clipboard/super_clipboard.dart';

// Runs inside the native Windows application. Keyboard shortcuts and the
// Windows clipboard-history UI are deliberately outside this roundtrip test.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const sources = AppReportImageSources();
  late SystemClipboard clipboard;
  final passed = <String>[];
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOwSdnyHwAEiAJU2GM8WwAAAABJRU5ErkJggg==',
  );
  final gif = base64Decode(
    'R0lGODlhAgACAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACwAAAAAAgACAAAIBgABCAQQEAAh+QQBCgABACwAAAAAAgACAIEAAP8AAAAAAAAAAAAIBgABCAQQEAA7',
  );

  setUpAll(() {
    expect(
      Platform.isWindows,
      isTrue,
      reason: 'Run this integration test with -d windows.',
    );
    final native = SystemClipboard.instance;
    expect(
      native,
      isNotNull,
      reason: 'The actual registered Windows clipboard plugin is required.',
    );
    clipboard = native!;
  });

  tearDownAll(() async {
    await Clipboard.setData(const ClipboardData(text: ''));
    final evidence = <String, Object?>{
      'renderer': 'Native Flutter Windows integration test',
      'hostPlatform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'provider': 'Registered super_clipboard Windows plugin',
      'commit': Platform.environment['REPORT_QA_COMMIT'],
      'reviewedHead': Platform.environment['REPORT_QA_REVIEWED_HEAD'],
      'passed': passed,
      'nativeClipboard': true,
      'nativeKeyboardInput': false,
      'windowsClipboardHistoryUi': false,
    };
    binding.reportData = evidence;
    final file = File(
      Platform.environment['REPORT_QA_NATIVE_OUTPUT'] ??
          'build/reporting_qa/native-clipboard.json',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(evidence),
    );
  });

  testWidgets(
    'native Flutter text is readable by the reporting clipboard provider',
    (tester) async {
      const text = 'טקסט רגיל בעברית + English 😀';
      await Clipboard.setData(const ClipboardData(text: text));
      final reader = await clipboard.read();
      expect(await reader.readValue(Formats.plainText), text);
      expect(await sources.readClipboard(skipIfText: true), isEmpty);
      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, text);
      passed.add('Flutter text -> native provider -> unchanged Flutter text');
    },
  );

  testWidgets('native PNG reaches the production report source unchanged', (
    tester,
  ) async {
    final item = DataWriterItem(suggestedName: 'native.png')
      ..add(Formats.png(png));
    await clipboard.write([item]);
    for (final skipIfText in [false, true]) {
      final images = await sources.readClipboard(skipIfText: skipIfText);
      expect(images, hasLength(1));
      expect(images.single.mimeType, 'image/png');
      expect(images.single.bytes, png);
    }
    passed.add('Native PNG -> production source, both text-precedence modes');
  });

  testWidgets(
    'native two-frame GIF wins over PNG without losing animation bytes',
    (tester) async {
      final item = DataWriterItem(suggestedName: 'animated.gif')
        ..add(Formats.gif(gif))
        ..add(Formats.png(png));
      await clipboard.write([item]);
      final images = await sources.readClipboard();
      expect(images, hasLength(1));
      expect(images.single.mimeType, 'image/gif');
      expect(images.single.bytes, gif);
      final codec = await ui.instantiateImageCodec(images.single.bytes);
      try {
        expect(codec.frameCount, 2);
      } finally {
        codec.dispose();
      }
      passed.add('Native GIF + PNG -> exact GIF bytes with two decoded frames');
    },
  );

  testWidgets('native mixed text and PNG preserves ordinary text precedence', (
    tester,
  ) async {
    const text = 'טקסט להדבקה רגילה';
    final item = DataWriterItem()
      ..add(Formats.png(png))
      ..add(Formats.plainText(text));
    await clipboard.write([item]);
    expect(await sources.readClipboard(skipIfText: true), isEmpty);
    expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, text);
    final explicit = await sources.readClipboard();
    expect(explicit.single.bytes, png);
    expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, text);
    passed.add(
      'Native text + PNG -> ordinary text precedence without changing clipboard',
    );
  });

  testWidgets('native advertised empty text does not hide its PNG', (
    tester,
  ) async {
    final item = DataWriterItem()
      ..add(Formats.png(png))
      ..add(Formats.plainText(''));
    await clipboard.write([item]);
    final reader = await clipboard.read();
    expect(reader.canProvide(Formats.plainText), isTrue);
    final images = await sources.readClipboard(skipIfText: true);
    expect(images, hasLength(1));
    expect(images.single.bytes, png);
    passed.add(
      'Native empty text + PNG -> production image source retains PNG',
    );
  });
}
