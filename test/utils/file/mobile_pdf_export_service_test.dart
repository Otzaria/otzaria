import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/mobile_pdf_export_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('otzaria/pdf_file_export');
  const id = '0123456789abcdef0123456789abcdef';

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('host support does not follow Flutter theme/platform overrides', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final expected = Platform.isAndroid
        ? MobilePdfExportPlatform.android
        : Platform.isIOS
        ? MobilePdfExportPlatform.ios
        : MobilePdfExportPlatform.unsupported;
    expect(MobilePdfExportService.instance.platform, expected);
    expect(
      MobilePdfExportService.instance.isSupported,
      expected != MobilePdfExportPlatform.unsupported,
    );
  });

  test(
    'exportFile sends paths only and retains the actual provider name',
    () async {
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return const MobilePdfExportResult(
          operationId: id,
          status: MobilePdfExportStatus.saved,
          documentUri: 'content://provider/42',
          displayName: 'השם בפועל (2).pdf',
        ).toMap();
      });
      const request = MobilePdfExportRequest(
        operationId: id,
        sourcePath: '/private/cache/otzaria-pdf-exports-v1/$id/ספר.pdf',
        fileName: 'ספר.pdf',
      );
      final result = await const MethodChannelMobilePdfExportBackend()
          .exportFile(request);
      expect(calls.single.method, 'exportFile');
      expect(calls.single.arguments, request.toMap());
      expect(result.displayName, 'השם בפועל (2).pdf');
      expect(result.documentUri, 'content://provider/42');
    },
  );

  test(
    'cancelExport has an explicit acknowledgement, not an export result',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'cancelExport');
        expect(call.arguments, {'version': 1, 'operationId': id});
        return {'operationId': id, 'accepted': false};
      });
      expect(
        await const MethodChannelMobilePdfExportBackend().cancelExport(id),
        isFalse,
      );
    },
  );

  test(
    'malformed acknowledgements are rejected by the channel adapter',
    () async {
      for (final response in [
        null,
        {'operationId': 'other', 'accepted': true},
        {'operationId': id, 'accepted': 'true'},
      ]) {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => response,
        );
        await expectLater(
          const MethodChannelMobilePdfExportBackend().cancelExport(id),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'real injected service retains its file through a channel cancel ACK',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'mobile-pdf-channel-',
      );
      final nativeEntered = Completer<Map>();
      final nativeResult = Completer<Map<String, Object?>>();
      MobilePdfExportOperation? operation;
      var callbacks = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        final args = call.arguments as Map;
        if (call.method == 'exportFile') {
          nativeEntered.complete(args);
          return nativeResult.future;
        }
        if (call.method == 'cancelExport') {
          return {'operationId': args['operationId'], 'accepted': true};
        }
        throw MissingPluginException(call.method);
      });
      try {
        final service = MobilePdfExportService.withBackend(
          platform: MobilePdfExportPlatform.ios,
          backend: const MethodChannelMobilePdfExportBackend(),
          temporaryDirectory: () async => temporary,
        );
        expect(service.platform, MobilePdfExportPlatform.ios);
        expect(service.isSupported, isTrue);
        operation = service.start(
          fileName: 'ספר.pdf',
          producer: (path) async {
            await File(path).writeAsString('%PDF-channel-fixture');
          },
          onCancelRequested: () => callbacks++,
        );
        final args = await nativeEntered.future;
        final source = File(args['sourcePath'] as String);
        var terminal = false;
        unawaited(operation.result.then((_) => terminal = true));
        await operation.cancel();
        expect(callbacks, 1);
        expect(terminal, isFalse);
        expect(await source.exists(), isTrue);
        nativeResult.complete(
          MobilePdfExportResult(
            operationId: operation.id,
            status: MobilePdfExportStatus.cancelled,
            residualDocument: 'file:///provider/partial.pdf',
            residualDisplayName: 'partial.pdf',
            cleanupStatus: MobilePdfExportCleanupStatus.unknown,
          ).toMap(),
        );
        final result = await operation.result;
        expect(result.residualDocument, 'file:///provider/partial.pdf');
        expect(result.status, MobilePdfExportStatus.cancelled);
        expect(await source.exists(), isFalse);
      } finally {
        if (operation != null) {
          final cancel = operation.cancel();
          if (!nativeResult.isCompleted) {
            nativeResult.complete(
              MobilePdfExportResult(
                operationId: operation.id,
                status: MobilePdfExportStatus.cancelled,
              ).toMap(),
            );
          }
          await operation.result;
          await cancel;
        }
        if (await temporary.exists()) await temporary.delete(recursive: true);
      }
    },
  );
}
