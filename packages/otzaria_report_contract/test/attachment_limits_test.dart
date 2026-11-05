import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:test/test.dart';

AppReport report({int schema = AppReport.schemaVersion}) => AppReport(
  schema: schema,
  reportId: 'c3efb70b-1986-4445-aac3-4790a0b1aac8',
  type: AppReportType.bug,
  trigger: AppReportTrigger.manual,
  title: 'תקלה',
  description: 'תיאור התקלה',
  reporterEmail: 'reporter@example.com',
  appVersion: '1.0.0',
  platform: 'windows',
  createdAt: DateTime.utc(2026, 11, 5),
);

AppReportImage image(int size, {String name = 'image.gif'}) => AppReportImage(
  bytes: Uint8List(size),
  fileName: name,
  mimeType: 'image/gif',
);

AppReportMinidump dump(int rawSize) {
  final raw = Uint8List(rawSize)..setRange(0, 4, ascii.encode('MDMP'));
  return AppReportMinidump(
    fileName: 'crash.dmp',
    gzipBytes: Uint8List.fromList(gzip.encode(raw)),
  );
}

void main() {
  const mib = 1024 * 1024;

  test('per-file boundary is 10 MiB inclusive, a byte more is rejected', () {
    expect(report().copyWith(images: [image(10 * mib)]).validate(), isNull);
    expect(
      report().copyWith(images: [image(10 * mib + 1)]).validate(),
      'attachments.images',
    );
    final merged = mergeAppReportImages([], [
      image(10 * mib),
      image(10 * mib + 1),
    ]);
    expect(merged.images.single.bytes.length, 10 * mib);
    expect(merged.rejection, AppReportImageRejection.tooLarge);
  });

  test('aggregate boundary is 20 MiB inclusive across multiple files', () {
    final atLimit = report().copyWith(
      images: [image(10 * mib), image(10 * mib)],
    );
    expect(atLimit.validate(), isNull);
    expect(
      atLimit.copyWith(images: [...atLimit.images, image(1)]).validate(),
      'attachments',
    );
    final merged = mergeAppReportImages(atLimit.images, [image(1)]);
    expect(merged.images, hasLength(2));
    expect(merged.rejection, AppReportImageRejection.totalTooLarge);
  });

  test(
    'removing an attachment makes its exact byte budget available again',
    () {
      final first = image(10 * mib, name: 'first.gif');
      final second = image(10 * mib, name: 'second.gif');
      final initial = mergeAppReportImages([], [first, second]);
      final remaining = [...initial.images]..remove(first);
      final replaced = mergeAppReportImages(remaining, [
        image(10 * mib, name: 'new.gif'),
      ]);
      expect(replaced.rejection, isNull);
      expect(replaced.images.map((i) => i.fileName), ['second.gif', 'new.gif']);
    },
  );

  test('diagnostics and log use transmitted compact UTF-8 bytes', () {
    final text = report().copyWith(
      diagnostics: {'שפה': 'עברית'},
      errorLog: 'א😀',
    );
    final textBytes = utf8.encode(jsonEncode({'שפה': 'עברית'})).length + 6;
    expect(text.otherAttachmentBytes, textBytes);
    final full = text.copyWith(
      images: [image(10 * mib), image(10 * mib - textBytes)],
    );
    expect(full.validate(), isNull);
    expect(full.copyWith(errorLog: 'א😀x').validate(), 'attachments');
    expect(
      mergeAppReportImages(
        [],
        full.images,
        otherAttachmentBytes: textBytes,
      ).rejection,
      isNull,
    );
    expect(
      mergeAppReportImages(
        [],
        full.images,
        otherAttachmentBytes: textBytes + 1,
      ).rejection,
      AppReportImageRejection.totalTooLarge,
    );
    expect(
      report().copyWith(diagnostics: <String, dynamic>{}).otherAttachmentBytes,
      2,
    );
    expect(report().otherAttachmentBytes, 0);
  });

  test(
    'schema 1 keeps legacy truncation and counts only its transmitted bytes',
    () {
      final value = report(schema: 1).copyWith(
        errorLog: 'א' * 200000,
        diagnostics: {'large': 'א' * 200000},
      );
      final attachments = value.toApiPayload()['attachments'] as Map;
      final expected =
          utf8.encode(attachments['errorLog'] as String).length +
          utf8.encode(jsonEncode(attachments['diagnostics'])).length;
      expect(value.otherAttachmentBytes, expected);
      expect(expected, lessThan(300000));
    },
  );

  test(
    'schema 2 keeps diagnostics and logs intact at the exact file limits',
    () {
      const fileLimit = 10 * 1024 * 1024;
      final diag = {'blob': 'x' * (fileLimit - 11)};
      final log = 'א' * (fileLimit ~/ 2);
      final exact = report().copyWith(diagnostics: diag, errorLog: log);
      expect(exact.validate(), isNull);
      expect(exact.otherAttachmentBytes, 20 * 1024 * 1024);
      final payload = exact.toApiPayload()['attachments'] as Map;
      expect(payload['diagnostics'], diag);
      expect(payload['errorLog'], log);
      expect(
        exact.copyWith(errorLog: '${log}x').validate(),
        'attachments.errorLog',
      );
      expect(
        exact.copyWith(diagnostics: {'blob': '${diag['blob']}x'}).validate(),
        'attachments.diagnostics',
      );
      final below = exact.copyWith(errorLog: log.substring(1));
      expect(below.copyWith(images: [image(2)]).validate(), isNull);
      expect(below.copyWith(images: [image(3)]).validate(), 'attachments');
    },
  );

  test(
    'schema 2 preserves escaped text and fits the HTTP transport envelope',
    () {
      const fileLimit = 10 * 1024 * 1024;
      final controlLog = String.fromCharCode(0) * fileLimit;
      final value = report().copyWith(
        diagnostics: {'blob': 'x' * (fileLimit - 11)},
        errorLog: controlLog,
      );
      expect(value.validate(), isNull);
      final payload = value.toApiPayload();
      expect((payload['attachments'] as Map)['errorLog'], controlLog);
      final encoded = utf8.encode(jsonEncode(payload));
      expect(encoded.length, greaterThan(70 * 1024 * 1024));
      expect(encoded.length, lessThanOrEqualTo(AppReport.maxRequestBytes));
    },
  );

  test('minidump uses raw file bytes for per-file and aggregate limits', () {
    final atLimit = dump(10 * mib);
    expect(atLimit.rawByteLength, 10 * mib);
    final full = report().copyWith(
      minidump: atLimit,
      images: [image(10 * mib)],
    );
    expect(full.validate(), isNull);
    expect(full.copyWith(errorLog: 'x').validate(), 'attachments');
    expect(
      report().copyWith(minidump: dump(10 * mib + 1)).validate(),
      'attachments.minidump',
    );
  });

  test('exact raw minidump limit survives gzip overhead', () async {
    final directory = await Directory.systemTemp.createTemp('dump-boundary-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/boundary.dmp');
    final bytes = Uint8List(10 * mib)..setRange(0, 4, ascii.encode('MDMP'));
    // A deterministic xorshift stream gives incompressible input cheaply.
    var state = 0x12345678;
    for (var i = 4; i < bytes.length; i++) {
      state ^= (state << 13) & 0xffffffff;
      state ^= state >> 17;
      state ^= (state << 5) & 0xffffffff;
      bytes[i] = state & 255;
    }
    await file.writeAsBytes(bytes);
    final compressed = await AppReportMinidump.fromFile(file);
    expect(compressed, isNotNull);
    expect(compressed!.gzipBytes.length, greaterThan(bytes.length));
    expect(compressed.rawByteLength, bytes.length);
    expect(report().copyWith(minidump: compressed).validate(), isNull);
    await file.writeAsBytes([0], mode: FileMode.append);
    expect(await AppReportMinidump.fromFile(file), isNull);
  });

  test('schema survives queue JSON, copy, redaction, restore and payload', () {
    for (final schema in [1, 2]) {
      final original = report(schema: schema).copyWith(images: [image(1)]);
      final restored = AppReport.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      final copied = restored
          .copyWith(title: 'updated')
          .redactedWith(AppReportRedactor(environment: const {}));
      expect(copied.schema, schema);
      expect(copied.toApiPayload()['schema'], schema);
      expect(copied.images.single.bytes, original.images.single.bytes);
    }
    final legacy = AppReport.fromJson(report().toJson()..remove('schema'));
    expect(legacy.schema, 1);
    expect(legacy.toApiPayload()['schema'], 1);
    expect(
      legacy.copyWith(images: [image(5 * mib + 1)]).validate(),
      'attachments.images',
    );
    expect(
      legacy.copyWith(schema: 2, images: [image(10 * mib)]).validate(),
      isNull,
    );
    expect(report(schema: 3).validate(), 'schema');
  });

  test(
    'maximum new and legacy payloads fit transport after base64/metadata',
    () {
      final newReport = report().copyWith(
        images: [image(10 * mib), image(10 * mib)],
      );
      final legacyReport = report(schema: 1).copyWith(
        images: [image(5 * mib), image(5 * mib), image(5 * mib)],
        minidump: AppReportMinidump(
          gzipBytes: Uint8List(
            16 * mib + AppReportMinidump.compressionAllowance,
          ),
          fileName: 'legacy.dmp',
        ),
        diagnostics: {'details': 'x' * 290000},
        errorLog: 'x' * 250000,
      );
      for (final value in [newReport, legacyReport]) {
        expect(value.validate(), isNull);
        final encoded = utf8.encode(jsonEncode(value.toApiPayload()));
        expect(encoded.length, lessThanOrEqualTo(AppReport.maxRequestBytes));
      }
    },
  );
}
