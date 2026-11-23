import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/utils/file/mobile_pdf_export_service.dart';

const _control = MethodChannel('otzaria/pdf_export_probe');
const _native = MethodChannel('otzaria/pdf_file_export');
final _exports = <String, _ProbeExport>{};

class _ProbeExport {
  late MobilePdfExportOperation operation;
  String? sourcePath;
  String? digest;
  int? length;
  bool terminal = false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _control.setMethodCallHandler(_command);
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('PDF export native probe'))),
    ),
  );
  await _control.invokeMethod<void>('ready');
}

Future<Object?> _command(MethodCall call) async {
  final arguments = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
  if (call.method == 'start') {
    final record = _ProbeExport();
    record.operation = MobilePdfExportService.instance.start(
      fileName: arguments['fileName'] as String? ?? 'עותק.pdf',
      producer: (path) async {
        record.sourcePath = path;
        await _writePdf(File(path), arguments['padding'] as int? ?? 4096);
        record.length = await File(path).length();
        record.digest = (await sha256.bind(File(path).openRead()).first)
            .toString();
      },
    );
    _exports[record.operation.id] = record;
    unawaited(
      record.operation.result.then<void>(
        (_) {
          record.terminal = true;
        },
        onError: (Object _, StackTrace _) {
          record.terminal = true;
        },
      ),
    );
    return {'operationId': record.operation.id};
  }
  final id = arguments['operationId'] as String;
  final record = _exports[id];
  switch (call.method) {
    case 'result':
      return (await record!.operation.result).toMap();
    case 'cancel':
      await record!.operation.cancel();
      return {'terminal': record.terminal};
    case 'rawCancel':
      return _native.invokeMethod<Object?>('cancelExport', {
        'version': 1,
        'operationId': id,
      });
    case 'busy':
      return _native.invokeMethod<Object?>('exportFile', {
        'version': 1,
        'operationId': id,
        'sourcePath': record!.sourcePath,
        'fileName': record.sourcePath!.split('/').last,
      });
    case 'state':
      final path = record!.sourcePath;
      return {
        'terminal': record.terminal,
        'sourcePath': path,
        'exists': path != null && await File(path).exists(),
        'directoryExists': path != null && await File(path).parent.exists(),
        'sha256': record.digest,
        'length': record.length,
      };
    default:
      throw UnsupportedError('Unknown probe command: ${call.method}');
  }
}

Future<void> _writePdf(File file, int padding) async {
  final output = await file.open(mode: FileMode.write);
  final offsets = <int>[0];
  Future<void> text(String value) async {
    await output.writeFrom(utf8.encode(value));
  }

  Future<void> object(int number, String value) async {
    offsets.add(await output.position());
    await text('$number 0 obj\n$value\nendobj\n');
  }

  try {
    await text('%PDF-1.4\n');
    await object(1, '<< /Type /Catalog /Pages 2 0 R >>');
    await object(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    await object(
      3,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>',
    );
    const drawing = '0 0 1 rg 20 20 80 80 re f\n';
    await object(
      4,
      '<< /Length ${drawing.length} >>\nstream\n${drawing}endstream',
    );
    offsets.add(await output.position());
    await text('5 0 obj\n<< /Length $padding >>\nstream\n');
    final block = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 88);
    for (var remaining = padding; remaining > 0;) {
      final count = remaining < block.length ? remaining : block.length;
      await output.writeFrom(block, 0, count);
      remaining -= count;
    }
    await text('\nendstream\nendobj\n');
    final xref = await output.position();
    await text('xref\n0 6\n0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      await text('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    await text('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    await output.flush();
  } finally {
    await output.close();
  }
}
