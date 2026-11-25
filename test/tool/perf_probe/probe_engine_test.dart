import 'dart:convert';

import 'package:test/test.dart';

import '../../../tool/perf_probe/src/probe_engine.dart';

Map<String, Object?> _identity({
  String mode = 'release',
  bool patched = true,
}) => {
  'schemaVersion': 1,
  'platform': 'windows',
  'architecture': 'x64',
  'buildMode': mode,
  'engineRevision': 'deb287481e3ce9468f3434937ced4240a70539ca',
  'bundleSha256': 'a' * 64,
  'verification': patched ? 'patched-action-sha256' : 'bundle-sha256',
  if (patched) 'expectedSha256': 'a' * 64,
};

Map<String, Object?>? _parse(
  Object? value, {
  String mode = 'release',
  String platform = 'windows',
}) => parsePerfEngineIdentity(
  jsonEncode(value),
  buildMode: mode,
  platform: platform,
);

void main() {
  test('missing host engine identity stays unavailable', () {
    expect(
      parsePerfEngineIdentity('', buildMode: 'profile', platform: 'linux'),
      isNull,
    );
  });

  test('accepts the verified release bundle without inventing heap data', () {
    final value = _parse(_identity())!;
    expect(value, _identity());
    expect(value.containsKey('heap'), isFalse);
    expect(() => value['buildMode'] = 'profile', throwsUnsupportedError);
  });

  test('ordinary bundles record a digest without claiming a patch', () {
    for (final mode in ['debug', 'profile', 'release']) {
      expect(
        _parse(_identity(mode: mode, patched: false), mode: mode),
        _identity(mode: mode, patched: false),
      );
    }
  });

  test('malformed JSON and non-object identities fail closed', () {
    for (final value in [null, [], 'passed', 1]) {
      expect(() => _parse(value), throwsFormatException);
    }
    expect(
      () => parsePerfEngineIdentity(
        '{',
        buildMode: 'release',
        platform: 'windows',
      ),
      throwsFormatException,
    );
  });

  test('identity must match the actual mode, platform and architecture', () {
    for (final entry in <String, Object?>{
      'schemaVersion': 1.0,
      'platform': 'linux',
      'architecture': 'arm64',
      'buildMode': 'profile',
      'unknown': true,
    }.entries) {
      expect(
        () => _parse(_identity()..[entry.key] = entry.value),
        throwsFormatException,
        reason: entry.key,
      );
    }
    expect(() => _parse(_identity(), platform: 'macos'), throwsFormatException);
    expect(() => _parse(_identity(), mode: 'debug'), throwsFormatException);
  });

  test('all engine digests require complete lowercase hexadecimal bytes', () {
    for (final key in ['engineRevision', 'bundleSha256', 'expectedSha256']) {
      for (final value in [null, '', 'bad', 'A' * 64, 1234]) {
        expect(
          () => _parse(_identity()..[key] = value),
          throwsFormatException,
          reason: '$key $value',
        );
      }
    }
  });

  test('patched engine verification requires release and matching bundle hash', () {
    expect(
      () => _parse(_identity(mode: 'profile'), mode: 'profile'),
      throwsFormatException,
    );
    expect(
      () => _parse(_identity()..['expectedSha256'] = 'b' * 64),
      throwsFormatException,
    );
    expect(
      () => _parse(_identity()..remove('expectedSha256')),
      throwsFormatException,
    );
  });

  test('unknown or contradictory verification does not look successful', () {
    expect(
      () => _parse(_identity()..['verification'] = 'trusted'),
      throwsFormatException,
    );
    expect(
      () => _parse(_identity()..['verification'] = 'bundle-sha256'),
      throwsFormatException,
    );
  });
}
