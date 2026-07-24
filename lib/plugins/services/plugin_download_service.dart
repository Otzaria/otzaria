import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';
import 'package:path/path.dart' as p;

class PluginDownloadService {
  final http.Client _client;

  PluginDownloadService({http.Client? client})
    : _client = client ?? http.Client() {
    HttpClientRegistry.register(_client.close);
  }

  Future<String> downloadPluginArchive(Uri downloadUri) async {
    final request = http.Request('GET', downloadUri);
    final response = await _client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'שגיאה בהורדת התוסף (${response.statusCode})',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'otzaria_plugin_download_',
    );
    final archivePath = p.join(
      tempDir.path,
      '${_resolveFileStem(downloadUri)}.otzplugin',
    );
    final targetFile = File(archivePath);
    final sink = targetFile.openWrite();

    try {
      await sink.addStream(response.stream);
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      await _cleanupDirectory(tempDir);
      rethrow;
    }

    return archivePath;
  }

  Future<void> cleanupDownloadedArchive(String archivePath) async {
    final parent = Directory(p.dirname(archivePath));
    if (await parent.exists()) {
      await _cleanupDirectory(parent);
      return;
    }

    final archiveFile = File(archivePath);
    if (await archiveFile.exists()) {
      await archiveFile.delete();
    }
  }

  Future<void> _cleanupDirectory(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  String _resolveFileStem(Uri uri) {
    final lastSegment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final sanitized = lastSegment
        .replaceAll('.otzplugin', '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .trim();

    if (sanitized.isEmpty) {
      return 'plugin';
    }

    return sanitized;
  }
}
