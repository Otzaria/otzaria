import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef ProbeEventSink =
    Future<void> Function(String topic, Map<String, dynamic> payload);
typedef ProbeRpc =
    Future<dynamic> Function(
      Object? request,
      ProbeEventSink eventSink,
      ProbeCancellation cancellation,
    );

class ProbeCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void _cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

/// מארח ניסוי בתהליך נפרד; אינו runtime מותקן או sandbox של מערכת ההפעלה.
class DomlessProcess {
  DomlessProcess._(this._process, this.pluginId, this._rpc) {
    // Buffered write errors arrive through done, after writeln has returned.
    _stdinDone = _process.stdin.done.then<void>(
      (_) {},
      onError: (Object error) => _fail('host_write: $error'),
    );
    final stdoutDone = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(_receive)
        .catchError((Object error) => _fail('protocol_error: $error'));
    final stderrDone = _process.stderr
        .transform(utf8.decoder)
        .forEach(_stderr.write)
        .catchError((Object error) => _fail('stderr_error: $error'));
    _exitDone = _process.exitCode.then((code) async {
      _exited = true;
      await Future.wait([stdoutDone, stderrDone]);
      if (!_closing) _fail('process_exit: $code ${_stderr.toString()}');
      _cancelRpcs();
      _finishCommands(StateError('Runtime closed'));
      try {
        await _process.stdin.close();
      } catch (error) {
        _fail('host_write: $error');
      }
      await _stdinDone;
    });
  }

  final Process _process;
  final String pluginId;
  final ProbeRpc _rpc;
  final _ready = Completer<void>();
  final _failed = Completer<String>();
  final _commands = <int, Completer<dynamic>>{};
  final _rpcs = <int, ProbeCancellation>{};
  final _stderr = StringBuffer();
  late final Future<void> _stdinDone;
  late final Future<void> _exitDone;
  Future<void>? _closeFuture;
  var _sequence = 0;
  var _closing = false;
  var _exited = false;
  var acceptedRpcCount = 0;

  Future<String> get failed => _failed.future;
  int get pid => _process.pid;
  int get activeRpcCount => _rpcs.length;
  bool get canFallbackWithoutReplay => acceptedRpcCount == 0;

  static Future<DomlessProcess> start({
    required String executable,
    required String pluginId,
    required ProbeRpc rpc,
  }) async {
    final process = DomlessProcess._(
      await Process.start(executable, const []),
      pluginId,
      rpc,
    );
    try {
      await process._ready.future.timeout(const Duration(seconds: 5));
      return process;
    } catch (error) {
      process._fail('startup_failed: $error');
      await process.close();
      rethrow;
    }
  }

  void _receive(String line) {
    try {
      final message = jsonDecode(line) as Map<String, dynamic>;
      switch (message['kind']) {
        case 'ready':
          if (!_ready.isCompleted) _ready.complete();
        case 'result':
          _commands.remove(message['id'])?.complete(message['value']);
        case 'rpc':
          if (!_closing && !_exited) {
            unawaited(_dispatch(message));
          }
        case 'fatal':
          _fail(message['code'] as String);
        default:
          _fail('unknown_protocol_message');
      }
    } catch (error) {
      _fail('invalid_protocol: $error');
    }
  }

  Future<void> _dispatch(Map<String, dynamic> message) async {
    final id = message['id'] as int;
    final cancellation = ProbeCancellation();
    _rpcs[id] = cancellation;
    acceptedRpcCount++;
    dynamic result;
    try {
      result = await _rpc(
        message['request'],
        (topic, payload) async {
          if (!cancellation.isCancelled && !_closing && !_exited) {
            await _command('event', {
              'source':
                  'window.dispatchEvent(new CustomEvent(${jsonEncode(topic)}, '
                  '{detail:${jsonEncode(payload)}}));',
            });
          }
        },
        cancellation,
      );
    } catch (error) {
      result = {
        'success': false,
        'data': null,
        'error': {'code': 'experiment.broker_failed', 'message': '$error'},
      };
    } finally {
      _rpcs.remove(id);
    }
    if (!cancellation.isCancelled && !_closing && !_exited) {
      _send({'op': 'reply', 'id': id, 'value': result});
    }
  }

  void _send(Map<String, dynamic> message) {
    try {
      final line = jsonEncode(message);
      if (utf8.encode(line).length >= 1024 * 1024) {
        _fail('host_input_size');
        return;
      }
      _process.stdin.writeln(line);
    } catch (error) {
      _fail('host_write: $error');
    }
  }

  Future<dynamic> _command(
    String op, [
    Map<String, dynamic> fields = const {},
  ]) async {
    if (_exited || (_closing && op != 'close')) {
      throw StateError('Runtime closed');
    }
    final id = ++_sequence;
    final result = Completer<dynamic>();
    _commands[id] = result;
    try {
      _send({'op': op, 'id': id, ...fields});
      return await result.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _fail('host_deadline');
      rethrow;
    } finally {
      _commands.remove(id);
    }
  }

  Future<dynamic> evaluate(String source) =>
      _command('eval', {'source': source});

  Future<Map<String, dynamic>> stats() async =>
      Map<String, dynamic>.from(await _command('stats') as Map);

  Future<double?> cpuSeconds() async =>
      (await _command('cpu') as num?)?.toDouble();

  void _cancelRpcs() {
    for (final cancellation in _rpcs.values) {
      cancellation._cancel();
    }
  }

  void _finishCommands(Object error) {
    for (final pending in _commands.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _commands.clear();
  }

  void _fail(String reason) {
    if (_failed.isCompleted) return;
    _failed.complete(reason);
    _closing = true;
    if (!_ready.isCompleted) _ready.completeError(StateError(reason));
    _cancelRpcs();
    _finishCommands(StateError(reason));
    if (!_exited) _process.kill();
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (!_exited && !_closing) {
      _closing = true;
      _cancelRpcs();
      try {
        await _command('close');
      } catch (error) {
        _fail('close_failed: $error');
      }
    }
    try {
      await _exitDone.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      if (!_exited) _process.kill(ProcessSignal.sigkill);
      await _exitDone;
    }
  }
}
