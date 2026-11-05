import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/printing/shaped_text/pdf_shaped_font.dart';
import 'package:otzaria/printing/shaped_text/shaper_font_scope.dart';
import 'package:pdf/pdf.dart';

final _disposed = throwsA(isA<ShaperException>());

void main() {
  final bytes = File(
    'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf',
  ).readAsBytesSync();

  test('30 workers release a partially registered pair', () async {
    for (var cycle = 0; cycle < 30; cycle++) {
      final released = ReceivePort();
      try {
        await expectLater(
          _runRenderWorker(bytes, 'register', released.sendPort),
          throwsA(isA<ShaperException>()),
        );
        final handles = await released.first as List<int>;
        expect(handles, hasLength(1));
        expect(() => ShaperFont.attach(handles.single), _disposed);
      } finally {
        released.close();
      }
    }
  });

  test('30 partial attachments leave their registered owner usable', () async {
    final owner = ShaperFont.register(bytes);
    addTearDown(owner.dispose);
    for (var cycle = 0; cycle < 30; cycle++) {
      late ShaperFont primary;
      await expectLater(
        withShaperFontPair(
          createPrimary: () => primary = ShaperFont.attach(owner.handle),
          createFallback: () => ShaperFont.attach(-1),
          action: (_, _) => fail('The action must not run.'),
        ),
        throwsA(isA<ShaperException>()),
      );
      expect(() => primary.shape(''), _disposed);
      expect(owner.shape('123').isNotEmpty, isTrue);
    }
  });

  for (final failure in [null, 'layout', 'save', 'cancel']) {
    test('30 owned worker cycles: ${failure ?? 'PDF output'}', () async {
      List<int>? expected;
      for (var cycle = 0; cycle < 30; cycle++) {
        final released = ReceivePort();
        try {
          final result = _runRenderWorker(bytes, failure, released.sendPort);
          if (failure == null) {
            final output = await result;
            expected ??= output.$2;
            expect(output.$2, expected);
            final pdf = String.fromCharCodes(output.$1);
            expect(pdf, startsWith('%PDF-'));
            expect(pdf, contains('/ToUnicode'));
            expect(pdf, contains('/CIDToGIDMap/Identity'));
          } else {
            await expectLater(
              result,
              throwsA(
                isA<StateError>().having(
                  (error) => error.message,
                  'message',
                  '$failure failed',
                ),
              ),
            );
          }
          final handles = await released.first as List<int>;
          expect(handles, hasLength(2));
          for (final handle in handles.toSet()) {
            expect(() => ShaperFont.attach(handle), _disposed);
          }
        } finally {
          released.close();
        }
      }
    });
  }

  test('caller timeout keeps worker owners alive until it finishes', () async {
    final ready = ReceivePort();
    try {
      final pending = _runGatedWorker(bytes, ready.sendPort);
      final (handle, resume) = await Future.any<(int, SendPort)>([
        ready.first.then((message) => message as (int, SendPort)),
        pending.then(
          (_) => throw StateError('Worker finished before release.'),
        ),
      ]);
      try {
        await expectLater(
          pending.timeout(const Duration(milliseconds: 10)),
          throwsA(isA<TimeoutException>()),
        );
        final probe = ShaperFont.attach(handle);
        try {
          expect(probe.shape('123').isNotEmpty, isTrue);
        } finally {
          probe.dispose();
        }
      } finally {
        resume.send(null);
      }
      expect(await pending, greaterThan(0));
      expect(() => ShaperFont.attach(handle), _disposed);
    } finally {
      ready.close();
    }
  });
}

Future<int> _runGatedWorker(Uint8List bytes, SendPort ready) => Isolate.run(
  () => withShaperFontPair(
    createPrimary: () => ShaperFont.register(bytes),
    createFallback: () => ShaperFont.register(bytes),
    action: (primary, fallback) async {
      final resume = ReceivePort();
      try {
        ready.send((primary.handle, resume.sendPort));
        await resume.first;
        return primary.shape('456').glyphCount +
            fallback.shape('789').glyphCount;
      } finally {
        resume.close();
      }
    },
  ),
);

Future<(Uint8List, List<int>)> _runRenderWorker(
  Uint8List bytes,
  String? failure,
  SendPort released,
) => Isolate.run(() => _renderInWorker(bytes, failure, released));

Future<(Uint8List, List<int>)> _renderInWorker(
  Uint8List bytes,
  String? failure,
  SendPort released,
) async {
  final owned = <ShaperFont>[];
  ShaperFont register(Uint8List data) {
    final font = ShaperFont.register(data);
    owned.add(font);
    return font;
  }

  try {
    return await withShaperFontPair(
      createPrimary: () => register(bytes),
      createFallback: () => register(
        failure == 'register' ? Uint8List(16) : bytes,
      ),
      action: (primary, fallback) async {
        final document = PdfDocument(
          compress: failure == 'save',
          deflate: failure == 'save'
              ? (_) => throw StateError('save failed')
              : null,
        );
        final pdfFont = PdfShapedFont(
          document,
          shaper: primary,
          fontBytes: bytes,
        );
        final run = primary.shape(
          'אבג 123',
          rtl: true,
          script: 'hebr',
          language: 'he',
          features: 'kern=1',
        );
        fallback.shape('123' * 200, language: 'en');
        if (failure == 'layout') throw StateError('layout failed');
        pdfFont.drawShapedRun(
          PdfPage(document).getGraphics(),
          run,
          x: 30,
          y: 80,
          fontSize: 16,
        );
        await Future<void>.delayed(Duration.zero);
        if (failure == 'cancel') throw StateError('cancel failed');
        return (await document.save(), run.records.toList());
      },
    );
  } finally {
    for (final font in owned) {
      _requireDisposed(font);
    }
    released.send(owned.map((font) => font.handle).toList());
  }
}

void _requireDisposed(ShaperFont font) {
  try {
    font.shape('');
  } on ShaperException {
    return;
  }
  throw StateError('Worker retained an owned font.');
}
