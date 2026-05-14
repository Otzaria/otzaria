import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

const int _maxSearchResults = 1000;
const int _searchChunkSize = 128;

void _updateAddress(List<String> address, String line) {
  if (line.length < 4) {
    address.add(line);
    return;
  }

  final index = address.indexWhere(
    (e) => e.length >= 4 && e.substring(0, 4) == line.substring(0, 4),
  );

  if (index != -1) {
    address.removeRange(index, address.length);
  }
  address.add(line);
}

bool _isHebrewLetter(int codeUnit) {
  return (codeUnit >= 0x05D0 && codeUnit <= 0x05EA) ||
      (codeUnit >= 0x05F0 && codeUnit <= 0x05F4) ||
      (codeUnit >= 0xFB1D && codeUnit <= 0xFBB1);
}

bool _containsWholeWord(String text, String query) {
  if (!text.contains(query)) return false;

  int idx = text.indexOf(query);
  while (idx != -1) {
    final before = idx > 0 ? text.codeUnitAt(idx - 1) : -1;
    final after = idx + query.length < text.length
        ? text.codeUnitAt(idx + query.length)
        : -1;

    if (!_isHebrewLetter(before) && !_isHebrewLetter(after)) return true;

    idx = text.indexOf(query, idx + 1);
  }
  return false;
}

class _SearchWorkerHost {
  _SearchWorkerHost._();

  static final _SearchWorkerHost instance = _SearchWorkerHost._();

  ReceivePort? _receivePort;
  SendPort? _workerSendPort;
  Isolate? _isolate;
  Future<void>? _startFuture;
  Completer<void>? _startCompleter;
  int _nextRequestId = 0;
  final Map<int, Completer<List<TextSearchResult>>> _pending = {};

  Future<List<TextSearchResult>> search({
    required List<String> content,
    required String query,
  }) async {
    await _ensureStarted();

    final requestId = ++_nextRequestId;
    final completer = Completer<List<TextSearchResult>>();
    _pending[requestId] = completer;

    _workerSendPort!.send({
      'type': 'search',
      'requestId': requestId,
      'content': content,
      'query': query,
    });

    return completer.future;
  }

  Future<void> _ensureStarted() {
    if (_workerSendPort != null) {
      return Future.value();
    }

    final existingStart = _startFuture;
    if (existingStart != null) {
      return existingStart;
    }

    final completer = Completer<void>();
    _startCompleter = completer;
    _startFuture = completer.future;
    _receivePort = ReceivePort();
    _receivePort!.listen(_handleMessage);

    Isolate.spawn<SendPort>(
      _searchWorkerMain,
      _receivePort!.sendPort,
    ).then((isolate) {
      _isolate = isolate;
    }).catchError((Object error, StackTrace stackTrace) {
      _startFuture = null;
      final startCompleter = _startCompleter;
      _startCompleter = null;
      _receivePort?.close();
      _receivePort = null;
      if (startCompleter != null && !startCompleter.isCompleted) {
        startCompleter.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _workerSendPort = message;
      final startCompleter = _startCompleter;
      _startCompleter = null;
      _startFuture = null;
      if (startCompleter != null && !startCompleter.isCompleted) {
        startCompleter.complete();
      }
      return;
    }

    if (message is! Map) {
      return;
    }

    final requestId = message['requestId'] as int?;
    if (requestId == null) {
      return;
    }

    final completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) {
      return;
    }

    final type = message['type'] as String?;
    switch (type) {
      case 'result':
        final rawResults = message['results'] as List<dynamic>? ?? const [];
        completer.complete(
          rawResults
              .cast<Map<dynamic, dynamic>>()
              .map(
                (raw) => TextSearchResult(
                  index: raw['index'] as int,
                  snippet: raw['snippet'] as String,
                  address: raw['address'] as String,
                  query: raw['query'] as String,
                ),
              )
              .toList(growable: false),
        );
        break;
      case 'canceled':
        completer.complete(const []);
        break;
      case 'error':
        completer.completeError(
          StateError(message['message'] as String? ?? 'Search worker failed'),
        );
        break;
    }
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(const []);
      }
    }
    _pending.clear();
    _receivePort?.close();
    _receivePort = null;
    _workerSendPort = null;
    _startFuture = null;
    _startCompleter = null;
    _nextRequestId = 0;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

void _searchWorkerMain(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);
  final runtime = SectionSearchWorkerRuntime(mainSendPort);
  commandPort.listen(runtime.onMessage);
}

@visibleForTesting
class SectionSearchWorkerRuntime {
  SectionSearchWorkerRuntime(this._mainSendPort);

  final SendPort _mainSendPort;
  Map<String, dynamic>? _queuedRequest;
  bool _isProcessing = false;

  void onMessage(dynamic message) {
    if (message is! Map) {
      return;
    }

    final type = message['type'];
    if (type != 'search') {
      return;
    }

    _queuedRequest = Map<String, dynamic>.from(message);
    if (!_isProcessing) {
      unawaited(_processLoop());
    }
  }

  Future<void> _processLoop() async {
    _isProcessing = true;
    try {
      while (_queuedRequest != null) {
        final request = _queuedRequest!;
        _queuedRequest = null;
        final requestId = request['requestId'] as int;

        try {
          final content = (request['content'] as List<dynamic>).cast<String>();
          final query = request['query'] as String;

          final results = <Map<String, dynamic>>[];
          final address = <String>[];
          bool canceled = false;

          for (int i = 0; i < content.length; i++) {
            final line = content[i];

            if (line.contains('<h') && !line.startsWith('<h1')) {
              _updateAddress(address, line);
            }

            final cleanLine =
                utils.removeVolwels(utils.stripHtmlIfNeeded(line));
            if (_containsWholeWord(cleanLine, query)) {
              results.add({
                'index': i,
                'snippet': cleanLine,
                'address': utils
                    .removeVolwels(utils.stripHtmlIfNeeded(address.join(', '))),
                'query': query,
              });
              if (results.length >= _maxSearchResults) {
                break;
              }
            }

            if ((i + 1) % _searchChunkSize == 0) {
              await Future<void>.delayed(Duration.zero);
              if (_queuedRequest != null) {
                canceled = true;
                break;
              }
            }
          }

          if (canceled) {
            _mainSendPort.send({
              'type': 'canceled',
              'requestId': requestId,
            });
            continue;
          }

          _mainSendPort.send({
            'type': 'result',
            'requestId': requestId,
            'results': results,
          });
        } catch (error) {
          _mainSendPort.send({
            'type': 'error',
            'requestId': requestId,
            'message': error.toString(),
          });
        }
      }
    } finally {
      _isProcessing = false;
    }
  }
}

Future<List<TextSearchResult>> searchInContent({
  required List<String> content,
  required String query,
}) async {
  if (query.isEmpty || content.isEmpty) return [];

  return _SearchWorkerHost.instance.search(
    content: content,
    query: query,
  );
}

@visibleForTesting
Future<void> resetSectionSearchWorkerForTesting() {
  return _SearchWorkerHost.instance.resetForTesting();
}
