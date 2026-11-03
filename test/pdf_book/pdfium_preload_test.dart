import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdfium_preload.dart';
import 'package:pdfrx/pdfrx.dart';

class _OpenReached implements Exception {}

class _FakeEntryFunctions implements PdfrxEntryFunctions {
  final calls = <String>[];

  @override
  Future<void> init() async => calls.add('init');

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    calls.add('openFile:$filePath');
    throw _OpenReached();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('open waits for the pdfium preload to finish', () async {
    final inner = _FakeEntryFunctions();
    final preload = Completer<void>();
    final gate = PdfiumPreloadGate(inner, () => preload.future);

    final open = gate.openFile('a.pdf');
    await pumpEventQueue();
    expect(inner.calls, isEmpty);

    preload.complete();
    await expectLater(open, throwsA(isA<_OpenReached>()));
    expect(inner.calls, ['openFile:a.pdf']);
  });

  test('a failed preload does not block the open', () async {
    final inner = _FakeEntryFunctions();
    final gate = PdfiumPreloadGate(
      inner,
      () => Future<void>.error(StateError('LoadLibraryW failed')),
    );

    await gate.init();
    expect(inner.calls, ['init']);
  });

  test('preload runs once for all calls', () async {
    final inner = _FakeEntryFunctions();
    var preloads = 0;
    final gate = PdfiumPreloadGate(inner, () async => preloads++);

    await Future.wait([gate.init(), gate.init()]);
    await expectLater(gate.openFile('b.pdf'), throwsA(isA<_OpenReached>()));
    expect(preloads, 1);
  });
}
