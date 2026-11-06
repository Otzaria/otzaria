import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:test/test.dart';

AppReport report() => AppReport(
  reportId: 'compatibility-report',
  type: AppReportType.bug,
  trigger: AppReportTrigger.manual,
  title: 'תקלה',
  description: 'תיאור 😀',
  reporterEmail: 'reporter@example.com',
  appVersion: '1.0.0',
  platform: 'windows',
  createdAt: DateTime.utc(2026, 11, 6),
);

AppReportImage image(int size) => AppReportImage(
  bytes: Uint8List(size)..setRange(0, 6, ascii.encode('GIF89a')),
  fileName: 'animated.gif',
  mimeType: 'image/gif',
);

AppReportMinidump dump(int size) => AppReportMinidump(
  gzipBytes: Uint8List.fromList(
    gzip.encode(Uint8List(size)..setRange(0, 4, ascii.encode('MDMP'))),
  ),
  fileName: 'crash.dmp',
);

void expectLosslessLegacy(AppReport value) {
  final compatible = value.forCompatibleTransport();
  expect(compatible.schema, 1);
  expect(compatible.toApiPayload(), value.toApiPayload()..['schema'] = 1);
  expect(compatible.toJson(), value.toJson()..['schema'] = 1);
  expect(value.schema, 2);
}

void main() {
  test(
    'ordinary small report selects schema1 without changing any content',
    () {
      expectLosslessLegacy(
        report().copyWith(
          diagnostics: {'שפה': 'עברית 😀'},
          errorLog: 'first\nlast\u0000',
          images: [image(128)],
          minidump: dump(512),
        ),
      );
    },
  );

  test('legacy and unknown stored schemas retain their original policy', () {
    final legacy = report().copyWith(schema: 1, errorLog: 'x' * 300000);
    final unknown = report().copyWith(schema: 3);
    expect(identical(legacy.forCompatibleTransport(), legacy), isTrue);
    expect(identical(unknown.forCompatibleTransport(), unknown), isTrue);
  });

  test('old encoder diagnostics and UTF8 log exact limits are lossless', () {
    final diagnostic = {'blob': 'x' * (300000 - 11)};
    expect(utf8.encode(jsonEncode(diagnostic)).length, 300000);
    final exact = report().copyWith(
      diagnostics: diagnostic,
      errorLog: 'א' * 125000,
    );
    expectLosslessLegacy(exact);
    expect(
      exact
          .copyWith(errorLog: '${exact.errorLog}x')
          .forCompatibleTransport()
          .schema,
      2,
    );
    expect(
      exact
          .copyWith(diagnostics: {'blob': '${diagnostic['blob']}x'})
          .forCompatibleTransport()
          .schema,
      2,
    );
  });

  test('JSON escaping is counted at the old text-envelope boundary', () {
    final base = report().copyWith(
      diagnostics: {'blob': 'x' * (300000 - 11)},
      errorLog: '\u0000' * 66000,
    );
    final extra = 700000 - utf8.encode(jsonEncode(base.toApiPayload())).length;
    expect(extra, greaterThan(0));
    final exact = base.copyWith(errorLog: '${base.errorLog}${'x' * extra}');
    expect(utf8.encode(jsonEncode(exact.toApiPayload())).length, 700000);
    expectLosslessLegacy(exact);
    final over = exact.copyWith(errorLog: '${exact.errorLog}x');
    expect(over.validate(), isNull);
    expect(identical(over.forCompatibleTransport(), over), isTrue);
    expect(
      over.toApiPayload()['attachments'],
      over.forCompatibleTransport().toApiPayload()['attachments'],
    );
  });

  test(
    'old image boundaries decide the contract without reducing 10/20 MiB',
    () {
      const mib = 1024 * 1024;
      expectLosslessLegacy(report().copyWith(images: [image(5 * mib)]));
      expect(
        report()
            .copyWith(images: [image(5 * mib + 1)])
            .forCompatibleTransport()
            .schema,
        2,
      );
      final total = report().copyWith(
        images: [image(5 * mib), image(5 * mib), image(5 * mib)],
      );
      expectLosslessLegacy(total);
      expect(
        total
            .copyWith(
              images: [
                image(5 * mib),
                image(5 * mib),
                image(4 * mib),
                image(mib + 1),
              ],
            )
            .forCompatibleTransport()
            .schema,
        2,
      );
      final full = report().copyWith(
        images: [image(10 * mib), image(10 * mib)],
      );
      expect(full.validate(), isNull);
      expect(identical(full.forCompatibleTransport(), full), isTrue);
    },
  );

  test('legacy selection cannot bypass the new dump or total limits', () {
    const mib = 1024 * 1024;
    final tooLarge = report().copyWith(minidump: dump(10 * mib + 1));
    expect(tooLarge.copyWith(schema: 1).validate(), isNull);
    expect(tooLarge.validate(), 'attachments.minidump');
    expect(identical(tooLarge.forCompatibleTransport(), tooLarge), isTrue);
    final total = report().copyWith(
      images: [image(5 * mib), image(5 * mib), image(5 * mib)],
      minidump: dump(5 * mib + 1),
    );
    expect(total.copyWith(schema: 1).validate(), isNull);
    expect(total.validate(), 'attachments');
    expect(identical(total.forCompatibleTransport(), total), isTrue);
  });
}
