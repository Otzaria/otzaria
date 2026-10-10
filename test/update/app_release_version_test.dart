import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';
import 'package:otzaria/update/app_release_version.dart';
import 'package:package_info_plus/package_info_plus.dart';

PackageInfo _info(String version, String buildNumber) => PackageInfo(
  appName: 'otzaria',
  packageName: 'otzaria',
  version: version,
  buildNumber: buildNumber,
);

void main() {
  group('iOS App Store versions', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('canonical base version is used for plugin bounds and metadata', () {
      expect(canonicalAppVersion(_info('0.9.9801', '99801')), '0.9.98');
      expect(canonicalAppVersion(_info('0.9.9802', '99802')), '0.9.98');
      expect(canonicalAppVersion(_info('0.9.98', '99802')), '0.9.98');
      expect(canonicalAppVersion(_info('0.9.9801', '99802')), '0.9.9801');
      expect(canonicalAppVersion(_info('0.9.9801', '-1')), '0.9.9801');
      expect(canonicalAppVersion(_info('0.9.9801', 'abc')), '0.9.9801');
      expect(canonicalAppVersion(_info('0.100.1', '1000001')), '0.100.1');
      expect(canonicalAppVersion(_info('0.9.10000', '100000')), '0.9.10000');
      final version = canonicalAppVersion(_info('0.9.9801', '99801'));
      expect(
        PluginVersionUtils.compareCoreVersions(version, '0.9.99'),
        lessThan(0),
      );
      expect(PluginVersionUtils.compareCoreVersions(version, '0.9.98'), 0);
    });

    test('encoded store version keeps the canonical hotfix release tag', () {
      expect(appReleaseVersion(_info('0.9.9800', '99800')), '0.9.98');
      expect(appReleaseVersion(_info('0.9.9801', '99801')), '0.9.98.1');
      expect(appReleaseVersion(_info('0.9.9802', '99802')), '0.9.98.2');
      expect(appReleaseVersion(_info('0.9.9900', '99900')), '0.9.99');
      expect(appReleaseVersion(_info('0.10.0', '100000')), '0.10.0');
      expect(appReleaseVersion(_info('1.0.1', '1000001')), '1.0.0.1');
    });

    test(
      'next canonical release stays newer and new plugin APIs stay blocked',
      () {
        final installed = appReleaseVersion(_info('0.9.9801', '99801'));
        expect(
          PluginVersionUtils.compareCoreVersions(installed, '0.9.99'),
          lessThan(0),
        );
        expect(PluginVersionUtils.compareCoreVersions(installed, '0.9.98'), 0);
      },
    );
  });

  test('encoded-looking versions on other platforms retain their meaning', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values.where(
      (value) => value != TargetPlatform.iOS,
    )) {
      debugDefaultTargetPlatformOverride = platform;
      expect(canonicalAppVersion(_info('0.9.9801', '99801')), '0.9.9801');
      expect(appReleaseVersion(_info('0.9.98', '99801')), '0.9.98.1');
    }
  });

  group('appReleaseVersion (issue #1547)', () {
    test('hotfix מקוד הגרסה נוסף כחלק רביעי', () {
      expect(appReleaseVersion(_info('0.9.97', '99702')), '0.9.97.2');
      expect(appReleaseVersion(_info('1.2.3', '1020399')), '1.2.3.99');
    });

    test('hotfix 0 נשאר בפורמט הרגיל', () {
      expect(appReleaseVersion(_info('0.9.97', '99700')), '0.9.97');
      expect(appReleaseVersion(_info('0.10.0', '100000')), '0.10.0');
    });

    test('build שאינו קוד הגרסה של אותה גרסה אינו נחשב hotfix', () {
      expect(appReleaseVersion(_info('0.9.97', '99802')), '0.9.97');
      expect(appReleaseVersion(_info('0.9.97', '790')), '0.9.97');
      expect(appReleaseVersion(_info('0.9.97', '')), '0.9.97');
      expect(appReleaseVersion(_info('0.9.97', 'abc')), '0.9.97');
      expect(appReleaseVersion(_info('0.9', '90002')), '0.9');
    });
  });
}
