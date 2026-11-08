import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const installedAndroidPackage = 'org.otzaria.otzaria.installedprobe';
const installedAndroidDirectory = 'installed-plugin-android';

/// Push-only control keeps host ADB observations outside the quiet windows.
class InstalledAndroidControl {
  InstalledAndroidControl._(
    this._server,
    this.identity,
    this._token,
    this._completion,
  );

  final HttpServer _server;
  final Map<String, Object?> identity;
  final String _token;
  final File _completion;
  final _connected = Completer<void>();
  HttpResponse? _events;
  Completer<Map<String, Object?>>? _reply;
  String? _action;
  int _sequence = 0;
  bool _closed = false;
  bool _closeCompleted = false;
  bool _completionAcknowledged = false;

  static Future<InstalledAndroidControl> start({
    required Directory support,
    required File report,
    required String campaignId,
    required String token,
    required String runId,
    required int processId,
    required String package,
  }) async {
    if (!RegExp(r'^campaign-[a-f0-9]{32}$').hasMatch(campaignId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
        !RegExp('^$processId-[0-9]+\$').hasMatch(runId) ||
        processId <= 0 ||
        package != installedAndroidPackage) {
      throw ArgumentError('Invalid dedicated Android probe identity');
    }
    final anchor = await support.resolveSymbolicLinks();
    final dataRoot = p.dirname(anchor);
    final output = await report.parent.resolveSymbolicLinks();
    final relativeReport = p.relative(
      p.join(output, p.basename(report.path)),
      from: dataRoot,
    );
    if (!RegExp(
      r'^(?:cache|code_cache)/otzaria-installed-probe-[A-Za-z0-9_-]+/output/installed-plugin-report\.json$',
    ).hasMatch(relativeReport)) {
      throw ArgumentError(
        'Report must belong to the fresh private probe cache',
      );
    }
    final directory = Directory(p.join(anchor, installedAndroidDirectory));
    if (await FileSystemEntity.isLink(directory.path)) {
      throw StateError('Control directory cannot be a link');
    }
    final campaign = Directory(p.join(directory.path, campaignId));
    if (await campaign.exists() ||
        await FileSystemEntity.isLink(campaign.path)) {
      throw StateError('Android control campaign already exists');
    }
    await campaign.create(recursive: true);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final control = InstalledAndroidControl._(
      server,
      {
        'protocol': 1,
        'campaignId': campaignId,
        'runId': runId,
        'pid': processId,
        'package': package,
      },
      token,
      File(p.join(campaign.path, 'completion.json')),
    );
    server.listen((request) {
      unawaited(control._handle(request));
    });
    try {
      final pending = File(p.join(campaign.path, 'bootstrap.pending'));
      await pending.writeAsString(
        jsonEncode({
          ...control.identity,
          'port': server.port,
          'reportPath': relativeReport,
        }),
        flush: true,
      );
      await pending.rename(p.join(campaign.path, 'bootstrap.json'));
      return control;
    } catch (_) {
      await control.close();
      rethrow;
    }
  }

  Future<void> connected({Duration timeout = const Duration(seconds: 120)}) =>
      _connected.future.timeout(timeout);

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.headers.value('X-Installed-Probe') != _token || _closed) {
        request.response.statusCode = HttpStatus.forbidden;
      } else if (request.method == 'GET' && request.uri.path == '/events') {
        if (_events != null) {
          request.response.statusCode = HttpStatus.conflict;
        } else {
          _events = request.response;
          request.response.bufferOutput = false;
          request.response.headers.contentType = ContentType(
            'application',
            'x-ndjson',
            charset: 'utf-8',
          );
          request.response.write(
            '${jsonEncode({...identity, 'sequence': 0, 'action': 'connected'})}\n',
          );
          await request.response.flush();
          _connected.complete();
          return;
        }
      } else if (request.method == 'POST' && request.uri.path == '/reply') {
        final bytes = <int>[];
        await for (final chunk in request.timeout(const Duration(seconds: 5))) {
          bytes.addAll(chunk);
          if (bytes.length > 64 * 1024) {
            throw const FormatException('Control reply exceeds limit');
          }
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map ||
            identity.entries.any(
              (entry) => decoded[entry.key] != entry.value,
            ) ||
            decoded['sequence'] != _sequence ||
            decoded['action'] != _action ||
            _reply == null ||
            _reply!.isCompleted ||
            decoded['ok'] is! bool ||
            decoded['result'] is! Map) {
          request.response.statusCode = HttpStatus.conflict;
        } else {
          final reply = _reply!;
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          if (decoded['ok'] == true) {
            reply.complete(Map<String, Object?>.from(decoded['result'] as Map));
          } else {
            reply.completeError(
              StateError('Host control failed: ${decoded['result']}'),
            );
          }
          return;
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    } catch (error, stack) {
      if (_reply case final reply? when !reply.isCompleted) {
        reply.completeError(error, stack);
      }
      try {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      } catch (_) {
        // A disconnected host is also bounded by the pending command deadline.
      }
    }
  }

  Future<Map<String, Object?>> request(
    String action,
    Map<String, Object?> payload, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_closed || _events == null || _reply != null) {
      throw StateError('Control is disconnected, closed, or already pending');
    }
    final pending = Completer<Map<String, Object?>>();
    _reply = pending;
    _action = action;
    _sequence++;
    try {
      final completed = await Future.wait<Object?>([
        pending.future.timeout(timeout),
        Future<void>.sync(() async {
          _events!.write(
            '${jsonEncode({...identity, 'sequence': _sequence, 'action': action, 'payload': payload})}\n',
          );
          await _events!.flush();
        }),
      ], eagerError: true);
      return completed.first! as Map<String, Object?>;
    } catch (error, stack) {
      if (!pending.isCompleted) pending.completeError(error, stack);
      rethrow;
    } finally {
      _reply = null;
      _action = null;
    }
  }

  Future<void> finish(File report, {required bool frameworkPassed}) async {
    final bytes = await report.readAsBytes();
    await request('complete', {
      'frameworkPassed': frameworkPassed,
      'reportBytes': bytes.length,
      'reportSha256': sha256.convert(bytes).toString(),
    });
    _completionAcknowledged = true;
  }

  Future<void> writeCompletion(
    File report, {
    required bool frameworkPassed,
  }) async {
    if (!_closeCompleted || !_completionAcknowledged) {
      throw StateError(
        'Completion requires acknowledged work and a closed control',
      );
    }
    if (await FileSystemEntity.type(_completion.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Control completion already exists');
    }
    final bytes = await report.readAsBytes();
    final pending = File(p.setExtension(_completion.path, '.pending'));
    await pending.create(exclusive: true);
    await pending.writeAsString(
      jsonEncode({
        ...identity,
        'sequence': _sequence,
        'controlClosed': true,
        'frameworkPassed': frameworkPassed,
        'reportBytes': bytes.length,
        'reportSha256': sha256.convert(bytes).toString(),
      }),
      flush: true,
    );
    await pending.rename(_completion.path);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_reply case final reply? when !reply.isCompleted) {
      reply.completeError(StateError('Control closed before acknowledgement'));
    }
    await _server.close(force: true);
    _closeCompleted = true;
  }
}
