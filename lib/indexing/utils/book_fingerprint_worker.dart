import 'dart:async';
import 'dart:isolate';

import 'package:otzaria_search_engine/otzaria_search_engine.dart';

// שולחים ערכים בלבד: מודלי הספרייה מכילים מטמונים וידיות native.
typedef _FingerprintInput = ({
  String text,
  String title,
  String topics,
  int catalogueOrder,
  int generationOrder,
  List<String>? extraFacets,
});

class BookFingerprintWorker {
  BookFingerprintWorker._(
    this._isolate,
    this._port,
    this._responses,
    this._send,
  );

  final Isolate _isolate;
  final ReceivePort _port;
  final StreamIterator<dynamic> _responses;
  final SendPort _send;
  bool _closed = false;

  /// עובד אחד לסריקה; ה־FFI מאותחל פעם אחת בתוך ה־isolate שלו.
  static Future<BookFingerprintWorker> start({
    String? nativeLibraryPath,
  }) async {
    final port = ReceivePort();
    final responses = StreamIterator<dynamic>(port);
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _run,
        (port.sendPort, nativeLibraryPath),
        onError: port.sendPort,
        onExit: port.sendPort,
      );
      final send = await _receive(responses) as SendPort;
      return BookFingerprintWorker._(isolate, port, responses, send);
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      await responses.cancel();
      port.close();
      rethrow;
    }
  }

  /// יש להמתין לתוצאה לפני שליחת הספר הבא, כדי לשמור על סדר הסריקה.
  Future<BigInt> compute({
    required String text,
    required String title,
    required String topics,
    required int catalogueOrder,
    required int generationOrder,
    List<String>? extraFacets,
  }) async {
    if (_closed) throw StateError('Fingerprint worker is closed');
    _send.send((
      text: text,
      title: title,
      topics: topics,
      catalogueOrder: catalogueOrder,
      generationOrder: generationOrder,
      extraFacets: extraFacets,
    ));
    return await _receive(_responses) as BigInt;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _send.send(null);
    try {
      // onExit מגיע אחרי dispose של גשר ה־FFI בעובד.
      await _responses.moveNext();
    } finally {
      _isolate.kill(priority: Isolate.immediate);
      await _responses.cancel();
      _port.close();
    }
  }

  static Future<dynamic> _receive(StreamIterator<dynamic> responses) async {
    if (!await responses.moveNext() || responses.current == null) {
      throw StateError('Fingerprint worker exited before returning a result');
    }
    final response = responses.current;
    if (response is List) {
      throw RemoteError(response[0] as String, response[1] as String);
    }
    return response;
  }

  static Future<void> _run((SendPort, String?) startup) async {
    final (reply, libraryPath) = startup;
    final commands = ReceivePort();
    try {
      await RustLib.init(
        externalLibrary: libraryPath == null
            ? null
            : ExternalLibrary.open(libraryPath),
      );
      reply.send(commands.sendPort);
      await for (final message in commands) {
        if (message == null) break;
        final input = message as _FingerprintInput;
        reply.send(
          computeBookFingerprint(
            text: input.text,
            title: input.title,
            topics: input.topics,
            catalogueOrder: input.catalogueOrder,
            generationOrder: input.generationOrder,
            extraFacets: input.extraFacets,
          ),
        );
      }
    } catch (error, stack) {
      reply.send([error.toString(), stack.toString()]);
    } finally {
      commands.close();
      RustLib.dispose();
    }
  }
}
