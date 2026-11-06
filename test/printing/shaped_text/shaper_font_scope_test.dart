import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/printing/shaped_text/shaper_font_scope.dart';

bool _isRegistered(int handle) {
  try {
    ShaperFont.attach(handle).dispose();
    return true;
  } on ShaperException {
    return false;
  }
}

Future<int> _shapeAfterResume(
  Uint8List bytes,
  SendPort ready,
) => withShaperFontPair(
  createPrimary: () => ShaperFont.register(bytes),
  createFallback: () => ShaperFont.register(bytes),
  action: (primary, fallback) async {
    final resume = ReceivePort();
    ready.send((primary.handle, resume.sendPort));
    try {
      await resume.first;
      return primary.shape('בדיקה', rtl: true).glyphCount +
          fallback.shape('נוספת', rtl: true).glyphCount;
    } finally {
      resume.close();
    }
  },
);

void main() {
  late Uint8List bytes;

  setUpAll(() {
    bytes = File('fonts/TaameyDavidCLM-Medium.ttf').readAsBytesSync();
  });

  test('disposes both owners after success', () async {
    late ShaperFont primary;
    late ShaperFont fallback;
    final count = await withShaperFontPair(
      createPrimary: () => primary = ShaperFont.register(bytes),
      createFallback: () => fallback = ShaperFont.register(bytes),
      action: (primary, fallback) => primary.shape('בדיקה').glyphCount,
    );

    expect(count, greaterThan(0));
    expect(_isRegistered(primary.handle), isFalse);
    expect(() => primary.shape('א'), throwsA(isA<ShaperException>()));
    expect(() => fallback.shape('א'), throwsA(isA<ShaperException>()));
  });

  test('releases the first owner if the second registration fails', () async {
    late ShaperFont primary;
    await expectLater(
      withShaperFontPair(
        createPrimary: () => primary = ShaperFont.register(bytes),
        createFallback: () => ShaperFont.register(Uint8List(0)),
        action: (_, _) => fail('The action must not start.'),
      ),
      throwsA(isA<ShaperException>()),
    );

    expect(_isRegistered(primary.handle), isFalse);
    expect(() => primary.shape('א'), throwsA(isA<ShaperException>()));
  });

  for (final asynchronous in [false, true]) {
    test(
      'releases owners after an ${asynchronous ? 'async' : 'sync'} failure',
      () async {
        late ShaperFont primary;
        late ShaperFont fallback;
        final failure = StateError('PDF construction or save failed');
        await expectLater(
          withShaperFontPair<void>(
            createPrimary: () => primary = ShaperFont.register(bytes),
            createFallback: () => fallback = ShaperFont.register(bytes),
            action: (_, _) {
              if (asynchronous) return Future<void>.error(failure);
              throw failure;
            },
          ),
          throwsA(same(failure)),
        );

        expect(_isRegistered(primary.handle), isFalse);
        expect(() => primary.shape('א'), throwsA(isA<ShaperException>()));
        expect(() => fallback.shape('א'), throwsA(isA<ShaperException>()));
      },
    );
  }

  test('disposes attached buffers while leaving the owner usable', () async {
    final owner = ShaperFont.register(bytes);
    late ShaperFont primary;
    late ShaperFont fallback;
    try {
      await withShaperFontPair(
        createPrimary: () => primary = ShaperFont.attach(owner.handle),
        createFallback: () => fallback = ShaperFont.attach(owner.handle),
        action: (primary, fallback) {
          primary.shape('בדיקה', language: 'he', features: '+kern');
          fallback.shape('נוספת', language: 'he', features: '+kern');
        },
      );

      expect(() => primary.shape('א'), throwsA(isA<ShaperException>()));
      expect(() => fallback.shape('א'), throwsA(isA<ShaperException>()));
      expect(owner.shape('עדיין חי').glyphCount, greaterThan(0));
    } finally {
      owner.dispose();
    }
    expect(_isRegistered(owner.handle), isFalse);
  });

  test('disposes a partial attachment without releasing its owner', () async {
    final owner = ShaperFont.register(bytes);
    late ShaperFont primary;
    try {
      await expectLater(
        withShaperFontPair(
          createPrimary: () => primary = ShaperFont.attach(owner.handle),
          createFallback: () => ShaperFont.attach(-1),
          action: (_, _) => fail('The action must not start.'),
        ),
        throwsA(isA<ShaperException>()),
      );

      expect(() => primary.shape('א'), throwsA(isA<ShaperException>()));
      expect(owner.shape('עדיין חי').glyphCount, greaterThan(0));
    } finally {
      owner.dispose();
    }
  });

  test('worker owns fonts until asynchronous work has finished', () async {
    final ready = ReceivePort();
    final readyPort = ready.sendPort;
    final fontBytes = bytes;
    final pending = Isolate.run(() => _shapeAfterResume(fontBytes, readyPort));

    try {
      final (handle, resume) = await ready.first.timeout(
        const Duration(seconds: 15),
      ) as (int, SendPort);
      final registeredDuringWork = _isRegistered(handle);
      resume.send(null);
      expect(await pending, greaterThan(0));
      expect(registeredDuringWork, isTrue);
      expect(_isRegistered(handle), isFalse);
    } finally {
      ready.close();
    }
  });
}
