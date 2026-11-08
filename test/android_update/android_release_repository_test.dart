import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/android_update/models/android_update.dart';
import 'package:otzaria/android_update/repository/android_release_repository.dart';

import 'support.dart';

void main() {
  final hash = 'a' * 64;
  Map<String, Object?> asset(
    String name, {
    int size = 4,
    String tag = '0.9.98.4',
  }) => {
    'name': name,
    'size': size,
    'digest': 'sha256:$hash',
    'browser_download_url':
        'https://github.com/Otzaria/otzaria/releases/download/$tag/$name',
  };
  Map<String, Object?> manifest() => {
    'schemaVersion': 1,
    'applicationId': 'org.otzaria.otzaria',
    'versionCode': 99804,
    'versionName': '0.9.98',
    'minSdk': 24,
    'targetSdk': 36,
    'abis': ['arm64-v8a'],
    'apk': {'name': 'otzaria-android.apk', 'size': 4, 'sha256': hash},
    'signingCertificateSha256': ['b' * 64],
  };
  Future<AndroidApkRelease?> fetch({
    List<Map<String, Object?>>? assets,
    Map<String, Object?>? metadata,
    AndroidUpdateEnvironment environment = directEnvironment,
    String tag = '0.9.98.4',
  }) {
    final api = {
      'tag_name': tag,
      'draft': false,
      'prerelease': false,
      'assets':
          assets ??
          [
            asset('otzaria-android.apk'),
            asset('app-release.apk'),
            asset('otzaria-android.json'),
          ],
    };
    return AndroidReleaseRepository(
      clientFactory: () => MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.host == 'api.github.com' ? api : metadata ?? manifest(),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    ).latest(environment);
  }

  Matcher failure(AndroidUpdateFailure expected) => throwsA(
    isA<AndroidUpdateException>().having((e) => e.failure, 'failure', expected),
  );

  test(
    'prefers the renamed APK and uses artifact versionCode metadata',
    () async {
      final result = await fetch();
      expect(result!.downloadUri.pathSegments.last, 'otzaria-android.apk');
      expect(result.versionCode, 99804);
      expect(result.sha256, hash);
      expect(result.signingCertificateSha256, ['b' * 64]);
    },
  );

  test(
    'same or older versionCode is not offered even when the tag looks new',
    () async {
      expect(
        await fetch(metadata: manifest()..['versionCode'] = 99803),
        isNull,
      );
      expect(
        await fetch(metadata: manifest()..['versionCode'] = 99802),
        isNull,
      );
    },
  );

  test('legacy app-release.apk uses the GitHub asset digest', () async {
    final result = await fetch(assets: [asset('app-release.apk')]);
    expect(result!.downloadUri.pathSegments.last, 'app-release.apk');
    expect(result.sha256, hash);
    expect(
      result.versionCode,
      isNull,
      reason: 'the APK is the final version authority for old releases',
    );
  });

  test('legacy tag build suffix is not the Android versionCode', () async {
    const installed = AndroidUpdateEnvironment(
      distribution: AndroidUpdateDistribution.direct,
      applicationId: 'org.otzaria.otzaria',
      versionCode: 99700,
      versionName: '0.9.97',
      sdkInt: 35,
      abis: ['arm64-v8a'],
    );
    const tag = '0.9.98.3+809';
    final result = await fetch(
      environment: installed,
      tag: tag,
      assets: [asset('app-release.apk', tag: tag)],
    );
    expect(result, isNotNull);
    expect(result!.tag, tag);
    expect(
      await fetch(
        tag: tag,
        assets: [asset('app-release.apk', tag: tag)],
      ),
      isNull,
      reason: '0.9.98.3 maps to 99803, not to the CI build suffix 809',
    );
  });

  test(
    'missing legacy digest does not silently disable integrity validation',
    () async {
      await expectLater(
        fetch(assets: [asset('app-release.apk')..remove('digest')]),
        failure(AndroidUpdateFailure.metadataMissing),
      );
    },
  );

  test('invalid sidecar never falls back to weaker legacy metadata', () async {
    await expectLater(
      fetch(metadata: manifest()..['schemaVersion'] = 99),
      failure(AndroidUpdateFailure.invalidMetadata),
    );
  });

  test(
    'rejects package, Android version and ABI incompatibility before download',
    () async {
      await expectLater(
        fetch(metadata: manifest()..['applicationId'] = 'other.app'),
        failure(AndroidUpdateFailure.packageMismatch),
      );
      await expectLater(
        fetch(metadata: manifest()..['minSdk'] = 36),
        failure(AndroidUpdateFailure.incompatibleDevice),
      );
      await expectLater(
        fetch(metadata: manifest()..['abis'] = ['x86_64']),
        failure(AndroidUpdateFailure.incompatibleDevice),
      );
    },
  );

  test('rejects inconsistent hash and sizes', () async {
    final badHash = manifest();
    (badHash['apk'] as Map)['sha256'] = 'c' * 64;
    await expectLater(
      fetch(metadata: badHash),
      failure(AndroidUpdateFailure.hashMismatch),
    );
    final badSize = manifest();
    (badSize['apk'] as Map)['size'] = 5;
    await expectLater(
      fetch(metadata: badSize),
      failure(AndroidUpdateFailure.invalidMetadata),
    );
    await expectLater(
      fetch(assets: [asset('app-release.apk', size: maxAndroidApkBytes + 1)]),
      failure(AndroidUpdateFailure.invalidMetadata),
    );
  });

  test(
    'rejects release URLs pointing outside the official repository',
    () async {
      await expectLater(
        fetch(
          assets: [
            asset(
              'app-release.apk',
            )..['browser_download_url'] = 'https://example.org/app-release.apk',
          ],
        ),
        failure(AndroidUpdateFailure.invalidMetadata),
      );
    },
  );

  test('Play never contacts GitHub', () async {
    var contacted = false;
    final repository = AndroidReleaseRepository(
      clientFactory: () {
        contacted = true;
        throw StateError('HTTP must not be created');
      },
    );
    await expectLater(
      repository.latest(playEnvironment),
      failure(AndroidUpdateFailure.invalidMetadata),
    );
    expect(contacted, isFalse);
  });

  test('caps sidecar response bytes while receiving', () async {
    final api = {
      'tag_name': '0.9.98.4',
      'draft': false,
      'prerelease': false,
      'assets': [asset('otzaria-android.apk'), asset('otzaria-android.json')],
    };
    final repository = AndroidReleaseRepository(
      clientFactory: () => MockClient(
        (request) async => http.Response(
          request.url.host == 'api.github.com'
              ? jsonEncode(api)
              : ' ' * (65 * 1024),
          200,
        ),
      ),
    );
    await expectLater(
      repository.latest(directEnvironment),
      failure(AndroidUpdateFailure.invalidMetadata),
    );
  });
}
