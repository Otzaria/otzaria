import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/search/settings_search_index.g.dart';
import 'package:otzaria/update/my_update_widget.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<Map<String, dynamic>?> fetch(Map<String, dynamic> release) =>
      http.runWithClient(
        fetchLatestAppRelease,
        () => MockClient((request) async {
          expect(request.url.path, '/repos/Otzaria/otzaria/releases/latest');
          expect(request.url.query, isEmpty);
          return http.Response(jsonEncode(release), 200);
        }),
      );

  test(
    'an old development preference cannot change the update source',
    () async {
      await Settings.setValue<bool>('key-dev-channel', true);
      const latest = {
        'id': 42,
        'tag_name': '1.0.0.2+807',
        'draft': false,
        'prerelease': false,
        'assets': [
          {'name': 'otzaria-windows.zip'},
        ],
      };
      expect(await fetch(latest), latest);
      expect(SettingsRepository.allKeys, isNot(contains('key-dev-channel')));
      expect(
        kGeneratedSettingsSearchEntries.map((entry) => entry.id),
        isNot(contains('system.updates.dev_channel')),
      );
    },
  );

  test('a missing Latest does not fall back to the releases list', () async {
    var requests = 0;
    final result = await http.runWithClient(
      fetchLatestAppRelease,
      () => MockClient((request) async {
        requests++;
        expect(request.url.path, endsWith('/releases/latest'));
        return http.Response('{}', 404);
      }),
    );
    expect(result, isNull);
    expect(requests, 1);
  });

  test('API failures do not select an alternative release', () async {
    for (final status in [403, 429, 500]) {
      await expectLater(
        http.runWithClient(
          fetchLatestAppRelease,
          () => MockClient((_) async => http.Response('{}', status)),
        ),
        throwsStateError,
      );
    }
  });

  test('rejects draft, prerelease and malformed Latest responses', () async {
    for (final release in [
      {'tag_name': '1.0.0', 'draft': true},
      {'tag_name': '1.0.0', 'prerelease': true},
      {'tag_name': 'not-a-version'},
      {'tag_name': '1.0.0-dev.1'},
      {'tag_name': '1.0'},
      {'tag_name': null},
    ]) {
      await expectLater(fetch(release), throwsFormatException);
    }
  });

  test('build numbers do not produce an update; hotfixes do', () {
    expect(
      isNewerReleaseVersion(
        latestVersion: '1.0.0+999',
        currentVersion: '1.0.0+1',
      ),
      isFalse,
    );
    expect(
      isNewerReleaseVersion(
        latestVersion: '1.0.0.1+999',
        currentVersion: '1.0.0+1',
      ),
      isTrue,
    );
    expect(
      isNewerReleaseVersion(
        latestVersion: '1.0.0',
        currentVersion: '1.1.0',
      ),
      isFalse,
    );
  });
}
