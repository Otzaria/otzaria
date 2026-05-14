import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

class PreparedIndexDocument {
  final String reference;
  final String text;
  final int segment;
  final int ordinal;

  const PreparedIndexDocument({
    required this.reference,
    required this.text,
    required this.segment,
    required this.ordinal,
  });

  factory PreparedIndexDocument.fromMap(Map<dynamic, dynamic> map) {
    return PreparedIndexDocument(
      reference: map['reference'] as String? ?? '',
      text: map['text'] as String? ?? '',
      segment: (map['segment'] as num?)?.toInt() ?? 0,
      ordinal: (map['ordinal'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract class IndexingIsolateUpdate {
  const IndexingIsolateUpdate();
}

class IndexingBatchReady extends IndexingIsolateUpdate {
  final List<PreparedIndexDocument> documents;
  final Future<void> Function() acknowledge;

  const IndexingBatchReady({
    required this.documents,
    required this.acknowledge,
  });
}

class IndexingWorkComplete extends IndexingIsolateUpdate {
  const IndexingWorkComplete();
}

class IndexingDocumentBuilder {
  static final RegExp _pdfInvisibleChars = RegExp(
    r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'
    r'|\uFEFF',
  );

  static final RegExp _pdfLettersAndDigits =
      RegExp(r'[\u05D0-\u05EAa-zA-Z0-9]');
  static final RegExp _pdfNonLettersNonSpace =
      RegExp(r'[^\s\u05D0-\u05EAa-zA-Z0-9]');

  /// \u05DE\u05E0\u05E8\u05DE\u05DC \u05D8\u05E7\u05E1\u05D8 \u05DC\u05D0\u05D9\u05E0\u05D3\u05D5\u05E7\u05E1 \u05DC\u05E4\u05D9 \u05DB\u05DC\u05DC\u05D9 `SearchQueryBuilder.sanitizeQuery`,
  /// \u05DB\u05DA \u05E9\u05D8\u05D5\u05E7\u05E0\u05D9 \u05D4\u05D0\u05D9\u05E0\u05D3\u05D5\u05E7\u05E1 \u05D5\u05D8\u05D5\u05E7\u05E0\u05D9 \u05D4\u05E9\u05D0\u05D9\u05DC\u05EA\u05D4 \u05D9\u05D9\u05D5\u05D5\u05E6\u05E8\u05D5 \u05DE\u05D0\u05D5\u05EA\u05DD \u05EA\u05D5\u05D5\u05D9\u05DD \u05DE\u05E0\u05D5\u05E8\u05DE\u05DC\u05D9\u05DD.
  static String normalizeTextForIndexing(String input) {
    return SearchQueryBuilder.sanitizeQuery(
      removeVolwels(stripHtmlIfNeeded(input)),
    );
  }

  static List<PreparedIndexDocument> buildTextBookDocuments(String text) {
    final texts = text.split('\n');
    final documents = <PreparedIndexDocument>[];
    final reference = <String>[];

    for (int i = 0; i < texts.length; i++) {
      final rawLine = texts[i];
      if (rawLine.startsWith('<h')) {
        _updateReferenceTrail(reference, rawLine);
        final headerLine = normalizeTextForIndexing(rawLine);
        documents.add(
          PreparedIndexDocument(
            reference: stripHtmlIfNeeded(reference.join(', ')),
            text: headerLine,
            segment: i,
            ordinal: documents.length,
          ),
        );
        continue;
      }

      final line = normalizeTextForIndexing(rawLine);
      documents.add(
        PreparedIndexDocument(
          reference: stripHtmlIfNeeded(reference.join(', ')),
          text: line,
          segment: i,
          ordinal: documents.length,
        ),
      );
    }

    return documents;
  }

  static String normalizePdfTextForIndexing(String input) {
    var text = stripHtmlIfNeeded(input);
    text = text.replaceAll(_pdfInvisibleChars, '');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = removeVolwels(text);
    text = SearchQueryBuilder.sanitizeQuery(text);
    return text;
  }

  static bool isProbablyGarbagePdfText(String normalizedText) {
    final compact = normalizedText.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return true;

    final letters = _pdfLettersAndDigits.allMatches(compact).length;
    if (letters == 0) return true;

    final nonLetters = _pdfNonLettersNonSpace.allMatches(compact).length;
    final ratioLetters = letters / compact.length;

    if (compact.length >= 50 && ratioLetters < 0.10) return true;
    if (compact.length >= 20 && ratioLetters < 0.20 && nonLetters > letters) {
      return true;
    }

    return false;
  }

  static void _updateReferenceTrail(List<String> reference, String line) {
    if (line.length < 4) {
      reference.add(line);
      return;
    }

    if (reference.isNotEmpty) {
      final prefix = line.substring(0, 4);
      final existingIndex = reference.indexWhere(
        (element) => element.length >= 4 && element.substring(0, 4) == prefix,
      );
      if (existingIndex != -1) {
        reference.removeRange(existingIndex, reference.length);
      }
    }

    reference.add(line);
  }
}

class IndexingIsolateService {
  IndexingIsolateService._(
    this._receivePort,
    this._errorPort,
    this._exitPort,
    this._workerToken,
  ) {
    _messagesSubscription = _receivePort.listen(_handleMessage);
    _errorSubscription = _errorPort.listen(_handleUnhandledWorkerError);
    _exitSubscription = _exitPort.listen(_handleWorkerExit);
  }

  static const int _batchSize = 200;

  final ReceivePort _receivePort;
  final ReceivePort _errorPort;
  final ReceivePort _exitPort;
  final RootIsolateToken? _workerToken;

  late final StreamSubscription<dynamic> _messagesSubscription;
  late final StreamSubscription<dynamic> _errorSubscription;
  late final StreamSubscription<dynamic> _exitSubscription;
  final Completer<void> _readyCompleter = Completer<void>();
  final Completer<void> _shutdownCompleter = Completer<void>();

  StreamController<IndexingIsolateUpdate>? _activeController;
  SendPort? _commandPort;
  Isolate? _isolate;
  bool _disposed = false;
  bool _workerFailureReported = false;

  static Future<IndexingIsolateService> create() async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    final service = IndexingIsolateService._(
      receivePort,
      errorPort,
      exitPort,
      RootIsolateToken.instance,
    );

    await service._spawn();
    return service;
  }

  Future<void> _spawn() async {
    _isolate = await Isolate.spawn<_WorkerBootstrapMessage>(
      _indexingWorkerMain,
      _WorkerBootstrapMessage(
        mainSendPort: _receivePort.sendPort,
        rootToken: _workerToken,
      ),
      debugName: 'indexing_worker',
      onError: _errorPort.sendPort,
      onExit: _exitPort.sendPort,
    );
    await _readyCompleter.future;
  }

  Future<Stream<IndexingIsolateUpdate>> processTextBook({
    required String text,
  }) async {
    await _ensureReady();
    _ensureIdle();

    final controller = StreamController<IndexingIsolateUpdate>();
    _activeController = controller;
    _commandPort!.send({
      'type': 'processTextBook',
      'text': text,
    });
    return controller.stream;
  }

  Future<Stream<IndexingIsolateUpdate>> processPdfPages({
    required List<({String reference, String text, int pageIndex})> pages,
  }) async {
    await _ensureReady();
    _ensureIdle();

    final controller = StreamController<IndexingIsolateUpdate>();
    _activeController = controller;
    _commandPort!.send({
      'type': 'processPdfPages',
      'pages': pages
          .map((p) => {
                'reference': p.reference,
                'text': p.text,
                'pageIndex': p.pageIndex,
              })
          .toList(),
    });
    return controller.stream;
  }

  Future<void> cancelActiveWork() async {
    if (_disposed || _commandPort == null) {
      return;
    }

    _commandPort!.send({'type': 'cancel'});
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _commandPort?.send({'type': 'shutdown'});
    await _shutdownCompleter.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );

    await _messagesSubscription.cancel();
    await _errorSubscription.cancel();
    await _exitSubscription.cancel();
    _receivePort.close();
    _errorPort.close();
    _exitPort.close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  Future<void> _ensureReady() async {
    if (_disposed) {
      throw StateError('IndexingIsolateService was disposed');
    }
    await _readyCompleter.future;
  }

  void _ensureIdle() {
    if (_activeController != null) {
      throw StateError('Indexing isolate already processing a book');
    }
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _commandPort = message;
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
      return;
    }

    if (message is! Map) {
      return;
    }

    final type = message['type'] as String?;
    switch (type) {
      case 'batch':
        final rawDocuments =
            (message['documents'] as List<dynamic>? ?? const <dynamic>[]);
        final documents = rawDocuments
            .whereType<Map<dynamic, dynamic>>()
            .map(PreparedIndexDocument.fromMap)
            .toList(growable: false);

        _activeController?.add(
          IndexingBatchReady(
            documents: documents,
            acknowledge: () async {
              _commandPort?.send({'type': 'ackBatch'});
            },
          ),
        );
        break;
      case 'complete':
      case 'cancelled':
        _activeController?.add(const IndexingWorkComplete());
        _closeActiveController();
        break;
      case 'error':
        final error = message['error']?.toString() ?? 'Unknown isolate error';
        _activeController?.addError(StateError(error));
        _closeActiveController();
        break;
      case 'shutdownAck':
        if (!_shutdownCompleter.isCompleted) {
          _shutdownCompleter.complete();
        }
        break;
    }
  }

  void _closeActiveController() {
    final controller = _activeController;
    _activeController = null;
    controller?.close();
  }

  void _handleUnhandledWorkerError(dynamic message) {
    if (_workerFailureReported) {
      return;
    }
    _workerFailureReported = true;

    final parsed = _parseUnhandledIsolateError(message);
    final error = parsed.$1;
    final stackTrace = parsed.$2;

    if (kDebugMode) {
      debugPrint('Unhandled indexing isolate error: $error');
      debugPrintStack(stackTrace: stackTrace);
    } else {
      ErrorLogFile.append(
        title: 'Unhandled Isolate Error',
        error: error,
        stackTrace: stackTrace,
        details: const {
          'Service': 'IndexingIsolateService',
        },
      );
    }

    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error, stackTrace);
    }

    _activeController?.addError(error, stackTrace);
    _closeActiveController();
  }

  void _handleWorkerExit(dynamic _) {
    if (_disposed) {
      if (!_shutdownCompleter.isCompleted) {
        _shutdownCompleter.complete();
      }
      return;
    }

    if (_workerFailureReported) {
      if (!_shutdownCompleter.isCompleted) {
        _shutdownCompleter.complete();
      }
      return;
    }
    _workerFailureReported = true;

    final error = StateError('Indexing isolate exited unexpectedly');
    final stackTrace = StackTrace.current;

    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error, stackTrace);
    }

    if (kDebugMode) {
      debugPrint('$error');
      debugPrintStack(stackTrace: stackTrace);
    } else {
      ErrorLogFile.append(
        title: 'Unhandled Isolate Error',
        error: error,
        stackTrace: stackTrace,
        details: const {
          'Service': 'IndexingIsolateService',
        },
      );
    }

    _activeController?.addError(error, stackTrace);
    _closeActiveController();

    if (!_shutdownCompleter.isCompleted) {
      _shutdownCompleter.complete();
    }
  }

  (Object, StackTrace) _parseUnhandledIsolateError(dynamic message) {
    if (message is List && message.length >= 2) {
      final error = message[0] ?? 'Unknown isolate error';
      final rawStackTrace = message[1];
      final stackTrace = rawStackTrace is StackTrace
          ? rawStackTrace
          : StackTrace.fromString(rawStackTrace?.toString() ?? '');
      return (error, stackTrace);
    }

    return (message ?? 'Unknown isolate error', StackTrace.current);
  }
}

class _WorkerBootstrapMessage {
  final SendPort mainSendPort;
  final RootIsolateToken? rootToken;

  const _WorkerBootstrapMessage({
    required this.mainSendPort,
    required this.rootToken,
  });
}

void _indexingWorkerMain(_WorkerBootstrapMessage bootstrap) {
  final receivePort = ReceivePort();
  bootstrap.mainSendPort.send(receivePort.sendPort);

  var isProcessing = false;
  var shouldCancel = false;
  Completer<void>? pendingBatchAck;

  Future<void> completePendingAck() async {
    final completer = pendingBatchAck;
    pendingBatchAck = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> emitBatch(List<Map<String, Object?>> documents) async {
    if (documents.isEmpty) {
      return;
    }

    final ackCompleter = Completer<void>();
    pendingBatchAck = ackCompleter;
    bootstrap.mainSendPort.send({
      'type': 'batch',
      'documents': documents,
    });
    await ackCompleter.future;
  }

  Future<void> processTextBook(String text) async {
    final texts = text.split('\n');
    final reference = <String>[];
    var batch = <Map<String, Object?>>[];
    var ordinal = 0;

    for (int i = 0; i < texts.length; i++) {
      if (shouldCancel) {
        return;
      }

      final rawLine = texts[i];
      if (rawLine.startsWith('<h')) {
        IndexingDocumentBuilder._updateReferenceTrail(reference, rawLine);
        final headerLine =
            IndexingDocumentBuilder.normalizeTextForIndexing(rawLine);
        batch.add({
          'reference': stripHtmlIfNeeded(reference.join(', ')),
          'text': headerLine,
          'segment': i,
          'ordinal': ordinal++,
        });
      } else {
        batch.add({
          'reference': stripHtmlIfNeeded(reference.join(', ')),
          'text': IndexingDocumentBuilder.normalizeTextForIndexing(rawLine),
          'segment': i,
          'ordinal': ordinal++,
        });
      }

      if (batch.length >= IndexingIsolateService._batchSize) {
        await emitBatch(batch);
        batch = <Map<String, Object?>>[];
      }
    }

    await emitBatch(batch);
  }

  Future<void> processPdfPages(List<dynamic> rawPages) async {
    var batch = <Map<String, Object?>>[];
    var ordinal = 0;

    for (final rawPage in rawPages) {
      if (shouldCancel) return;

      final page = rawPage as Map<dynamic, dynamic>;
      final reference = page['reference'] as String? ?? '';
      final text = page['text'] as String? ?? '';
      final pageIndex = (page['pageIndex'] as num?)?.toInt() ?? 0;

      final rawLines = text.split('\n');
      for (final rawLine in rawLines) {
        if (shouldCancel) return;

        final normalized =
            IndexingDocumentBuilder.normalizePdfTextForIndexing(rawLine);
        if (IndexingDocumentBuilder.isProbablyGarbagePdfText(normalized)) {
          continue;
        }

        batch.add({
          'reference': reference,
          'text': normalized,
          'segment': pageIndex,
          'ordinal': ordinal++,
        });

        if (batch.length >= IndexingIsolateService._batchSize) {
          await emitBatch(batch);
          batch = <Map<String, Object?>>[];
        }
      }
    }

    await emitBatch(batch);
  }

  receivePort.listen((dynamic message) {
    if (message is! Map) {
      return;
    }

    final type = message['type'] as String?;

    switch (type) {
      case 'processTextBook':
        if (isProcessing) {
          bootstrap.mainSendPort.send({
            'type': 'error',
            'error': 'Indexing worker is already processing a book',
          });
          return;
        }

        isProcessing = true;
        shouldCancel = false;
        unawaited(() async {
          try {
            await processTextBook(message['text'] as String? ?? '');
            bootstrap.mainSendPort.send({
              'type': shouldCancel ? 'cancelled' : 'complete',
            });
          } catch (e) {
            bootstrap.mainSendPort.send({
              'type': 'error',
              'error': e.toString(),
            });
          } finally {
            await completePendingAck();
            isProcessing = false;
          }
        }());
        return;
      case 'processPdfPages':
        if (isProcessing) {
          bootstrap.mainSendPort.send({
            'type': 'error',
            'error': 'Indexing worker is already processing a book',
          });
          return;
        }

        isProcessing = true;
        shouldCancel = false;
        unawaited(() async {
          try {
            await processPdfPages(
              (message['pages'] as List<dynamic>?) ?? const [],
            );
            bootstrap.mainSendPort.send({
              'type': shouldCancel ? 'cancelled' : 'complete',
            });
          } catch (e) {
            bootstrap.mainSendPort.send({
              'type': 'error',
              'error': e.toString(),
            });
          } finally {
            await completePendingAck();
            isProcessing = false;
          }
        }());
        return;
      case 'ackBatch':
        unawaited(completePendingAck());
        return;
      case 'cancel':
        shouldCancel = true;
        unawaited(completePendingAck());
        return;
      case 'shutdown':
        shouldCancel = true;
        unawaited(() async {
          await completePendingAck();
          bootstrap.mainSendPort.send({'type': 'shutdownAck'});
          receivePort.close();
        }());
        return;
    }
  });
}
