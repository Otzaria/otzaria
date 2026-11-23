import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_font_fallback.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final replacementPassword in <String?>['original', 'changed', null]) {
    test('שימוש חוזר בסיסמה בעת רענון גופנים ($replacementPassword)', () async {
      final original = PdfrxEntryFunctions.instance;
      final backend = _PasswordRetryBackend(replacementPassword);
      PdfrxEntryFunctions.instance = backend;
      try {
        var prompts = 0;
        final protected =
            PdfFontFallback.openFile(
              'protected',
              passwordProvider: () async =>
                  prompts++ == 0 ? 'original' : replacementPassword,
            ).then<Object>(
              (document) => document,
              onError: (Object error) => error,
            );
        await backend.unlocked.future;
        final peer = PdfFontFallback.openFile('peer');
        backend.release.complete();
        final document = await protected;
        await (await peer).dispose();

        expect(backend.attemptedPasswords, [
          'original',
          'original',
          if (replacementPassword != 'original') replacementPassword,
        ]);
        expect(prompts, replacementPassword == 'original' ? 1 : 2);
        if (replacementPassword == null) {
          expect(document, isA<PdfPasswordException>());
        } else {
          await (document as PdfDocument).dispose();
        }
      } finally {
        PdfrxEntryFunctions.instance = original;
      }
    });
  }
}

class _PasswordRetryBackend implements PdfrxEntryFunctions {
  _PasswordRetryBackend(this.replacementPassword);

  final String? replacementPassword;
  final unlocked = Completer<void>();
  final release = Completer<void>();
  final attemptedPasswords = <String?>[];
  var _peerOpens = 0;

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    final document = _Document(filePath);
    if (filePath == 'peer') {
      if (_peerOpens++ == 0) {
        document.fonts = [
          PdfFontQuery(
            face: 'OtzariaPasswordRetryFont$replacementPassword',
            weight: 400,
            isItalic: false,
            charset: PdfFontCharset.hebrew,
            pitchFamily: 0,
          ),
        ];
      }
      return document;
    }

    final firstOpen = !unlocked.isCompleted;
    final expectedPassword = firstOpen ? 'original' : replacementPassword;
    while (true) {
      final password = await passwordProvider!();
      attemptedPasswords.add(password);
      if (password == null) throw const PdfPasswordException('Cancelled');
      if (password == expectedPassword) break;
    }
    if (firstOpen) {
      unlocked.complete();
      await release.future;
    }
    return document;
  }

  @override
  Future<void> configureFontEnvironment({
    String? fontCachePath,
    List<String> fontPaths = const [],
  }) async {}

  @override
  Future<void> addFontData({
    required String face,
    required Uint8List data,
    String? resolvedFace,
  }) async {}

  @override
  Future<void> reloadFonts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Document extends PdfDocument {
  _Document(String path) : super(sourceName: path);

  List<PdfFontQuery> fonts = const [];

  @override
  Stream<PdfDocumentEvent> get events => Stream.fromIterable([
    if (fonts.isNotEmpty) PdfDocumentMissingFontsEvent(this, fonts),
  ]);

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
