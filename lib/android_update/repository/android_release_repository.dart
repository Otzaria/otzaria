import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import '../models/android_update.dart';

const maxAndroidApkBytes = 512 * 1024 * 1024;
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

class AndroidReleaseRepository {
  AndroidReleaseRepository({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  Future<AndroidApkRelease?> latest(
    AndroidUpdateEnvironment environment,
  ) async {
    if (environment.distribution != AndroidUpdateDistribution.direct) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    }
    final client = _clientFactory();
    try {
      final release = await _getJson(
        client,
        Uri.https('api.github.com', '/repos/Otzaria/otzaria/releases/latest'),
        limit: 2 * 1024 * 1024,
        allowNotFound: true,
      );
      if (release == null) return null;
      final tag = release['tag_name'];
      if (release['draft'] != false ||
          release['prerelease'] != false ||
          tag is! String ||
          _versionCodeFromTag(tag) == null ||
          release['assets'] is! List) {
        throw const AndroidUpdateException(
          AndroidUpdateFailure.invalidMetadata,
        );
      }
      final assets = (release['assets'] as List).whereType<Map>().toList();
      Map? find(String name) {
        final matches = assets.where((a) => a['name'] == name).toList();
        if (matches.length > 1) {
          throw const AndroidUpdateException(
            AndroidUpdateFailure.invalidMetadata,
          );
        }
        return matches.firstOrNull;
      }

      final apk = find('otzaria-android.apk') ?? find('app-release.apk');
      if (apk == null) {
        throw const AndroidUpdateException(
          AndroidUpdateFailure.metadataMissing,
        );
      }
      final size = _positiveInt(apk['size'], maxAndroidApkBytes);
      final name = apk['name'] as String;
      final url = _assetUri(apk, tag, name);
      final metadata = find('otzaria-android.json');
      if (metadata != null) {
        final manifest = await _getJson(
          client,
          _assetUri(metadata, tag, 'otzaria-android.json'),
          limit: 64 * 1024,
        );
        if (manifest == null ||
            manifest['schemaVersion'] != 1 ||
            manifest['apk'] is! Map) {
          throw const AndroidUpdateException(
            AndroidUpdateFailure.invalidMetadata,
          );
        }
        final binary = manifest['apk'] as Map;
        final hash = _hash(binary['sha256']);
        final versionCode = _positiveInt(manifest['versionCode'], 2100000000);
        if (manifest['applicationId'] != environment.applicationId) {
          throw const AndroidUpdateException(
            AndroidUpdateFailure.packageMismatch,
          );
        }
        if (binary['name'] != name ||
            binary['size'] != size ||
            manifest['versionName'] is! String) {
          throw const AndroidUpdateException(
            AndroidUpdateFailure.invalidMetadata,
          );
        }
        if (apk['digest'] != null && _assetHash(apk['digest']) != hash) {
          throw const AndroidUpdateException(AndroidUpdateFailure.hashMismatch);
        }
        final minSdk = _positiveInt(manifest['minSdk'], 1000);
        final abis = _strings(manifest['abis']);
        final signatures = _strings(
          manifest['signingCertificateSha256'],
        ).map(_hash).toList();
        if (minSdk > environment.sdkInt ||
            !abis.any(environment.abis.contains)) {
          throw const AndroidUpdateException(
            AndroidUpdateFailure.incompatibleDevice,
          );
        }
        if (versionCode <= environment.versionCode) return null;
        return AndroidApkRelease(
          tag: tag,
          displayVersion: tag.replaceFirst(RegExp(r'^v'), ''),
          downloadUri: url,
          size: size,
          sha256: hash,
          versionCode: versionCode,
          applicationId: environment.applicationId,
          signingCertificateSha256: signatures,
        );
      }
      if (_versionCodeFromTag(tag)! <= environment.versionCode) return null;
      return AndroidApkRelease(
        tag: tag,
        displayVersion: tag.replaceFirst(RegExp(r'^v'), ''),
        downloadUri: url,
        size: size,
        sha256: _assetHash(apk['digest']),
        applicationId: environment.applicationId,
      );
    } on AndroidUpdateException {
      rethrow;
    } on FormatException {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    } on TypeError {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    } finally {
      client.close();
    }
  }

  static int? _versionCodeFromTag(String tag) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?(?:\+(\d+))?$',
    ).firstMatch(tag);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 4; i++) int.tryParse(match[i] ?? '0')];
    if (parts.contains(null) || parts.skip(1).any((p) => p! > 99)) return null;
    return parts[0]! * 1000000 +
        parts[1]! * 10000 +
        parts[2]! * 100 +
        parts[3]!;
  }

  static Uri _assetUri(Map asset, String tag, String name) {
    final expected = Uri(
      scheme: 'https',
      host: 'github.com',
      pathSegments: [
        'Otzaria',
        'otzaria',
        'releases',
        'download',
        tag,
        name,
      ],
    );
    final actual = Uri.tryParse(
      asset['browser_download_url'] is String
          ? asset['browser_download_url'] as String
          : '',
    );
    if (actual == null ||
        actual.scheme != 'https' ||
        actual.host != 'github.com' ||
        actual.userInfo.isNotEmpty ||
        actual.hasQuery ||
        actual.hasFragment ||
        actual.port != 443 ||
        actual.pathSegments.join('/') != expected.pathSegments.join('/')) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    }
    return expected;
  }

  static int _positiveInt(Object? value, int max) {
    if (value is! int || value <= 0 || value > max) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    }
    return value;
  }

  static List<String> _strings(Object? value) {
    if (value is! List ||
        value.isEmpty ||
        value.any((v) => v is! String || v.isEmpty)) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    }
    return value.cast<String>();
  }

  static String _hash(Object? value) {
    if (value is! String || !_sha256Pattern.hasMatch(value)) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    }
    return value;
  }

  static String _assetHash(Object? value) {
    if (value is! String || !value.startsWith('sha256:')) {
      throw const AndroidUpdateException(AndroidUpdateFailure.metadataMissing);
    }
    return _hash(value.substring(7));
  }

  static Future<Map<String, dynamic>?> _getJson(
    http.Client client,
    Uri uri, {
    required int limit,
    bool allowNotFound = false,
  }) async {
    final response = await client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 20));
    if (allowNotFound && response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw const AndroidUpdateException(AndroidUpdateFailure.network);
    }
    if ((response.contentLength ?? 0) > limit) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + chunk.length > limit) {
        throw const AndroidUpdateException(
          AndroidUpdateFailure.invalidMetadata,
        );
      }
      bytes.addAll(chunk);
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidMetadata);
    }
    return json;
  }
}
