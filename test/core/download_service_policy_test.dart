import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/android_update/models/android_update.dart';
import 'package:otzaria/android_update/repository/android_update_repository.dart';
import 'package:otzaria/core/download_http_client.dart';
import 'package:otzaria/core/download_network_policy.dart';
import 'package:otzaria/library/services/hebrew_books_download_service.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/plugins/services/plugin_download_service.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_network_fetch_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../android_update/support.dart';
import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DownloadNetworkPolicy savedPolicy;
  late DownloadNetworkPolicy policy;
  late StreamController<bool> network;
  late Directory directory;
  var requests = 0;
  final bytes = List<int>.generate(8192, (i) => i % 251);
  final uri = Uri.parse('https://example.com/asset.bin');

  MockClient client() => MockClient((request) async {
    requests++;
    return http.Response.bytes(bytes, 200, headers: {'etag': '"asset-v1"'});
  });

  setUp(() async {
    requests = 0;
    savedPolicy = DownloadNetworkPolicy.instance;
    network = StreamController<bool>.broadcast(sync: true);
    policy = DownloadNetworkPolicy(
      isAndroid: true,
      wifiOnlyReader: () => true,
      wifiChanges: () => network.stream,
    );
    DownloadNetworkPolicy.instance = policy;
    final ready = policy.refresh();
    network.add(false);
    await ready;
    directory = await Directory.systemTemp.createTemp(
      'download-policy-service-',
    );
  });
  tearDown(() async {
    DownloadNetworkPolicy.instance = savedPolicy;
    await policy.dispose();
    await network.close();
    await directory.delete(recursive: true);
  });

  test('הורדת ספר היברובוקס ממתינה לפני שליחת בקשה', () async {
    final service = HebrewBooksDownloadService(client: client());
    addTearDown(service.dispose);
    var waiting = false;
    final future = service.download(
      123,
      onWaitingForWifi: () => waiting = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
    expect(waiting, isTrue);
    network.add(true);
    expect((await future).bytes, bytes);
    expect(requests, 1);
  });

  test('נכס companion או מודל סמנטי ממתין ושומר את הקובץ המאומת', () async {
    final target = '${directory.path}/model.bin';
    final waiting = Completer<void>();
    final future = CompanionAssetsService(clientFactory: client)
        .downloadVerifiedFile(
          url: uri.toString(),
          destPath: target,
          resumeIdentity: 'release',
          expectedSize: bytes.length,
          expectedSha256: sha256.convert(bytes).toString(),
          onWaitingForWifi: () => waiting.complete(),
        );
    await waiting.future.timeout(const Duration(seconds: 5));
    expect(requests, 0);
    network.add(true);
    await future;
    expect(await File(target).readAsBytes(), bytes);
  });

  for (final destination in ['downloads', 'path', 'cache']) {
    test('קובץ מתוסף אל $destination ממתין ואינו עוקף בדיקות הרשאה', () async {
      final service = PluginFileDownloadService(client: client());
      addTearDown(service.dispose);
      Future<bool> allowed(Uri _) async => true;
      final future = switch (destination) {
        'downloads' => service.downloadToDownloads(
          uri,
          isAllowed: allowed,
          targetDir: directory,
        ),
        'path' => service.downloadToPath(
          uri,
          '${directory.path}/asset.bin',
          isAllowed: allowed,
          resume: true,
        ),
        _ => service.downloadToDirectory(
          uri,
          directory,
          isAllowed: allowed,
          maxBytes: bytes.length,
        ),
      };
      await Future<void>.delayed(Duration.zero);
      expect(requests, 0);
      network.add(true);
      final result = await future;
      expect(await File(result.path).readAsBytes(), bytes);
    });
  }

  test('סגירת שירות תוסף מבטלת גם המתנה ל־WiFi', () async {
    final service = PluginFileDownloadService(client: client());
    final future = service.downloadToPath(
      uri,
      '${directory.path}/asset.bin',
      isAllowed: (_) async => true,
    );
    final expectation = expectLater(
      future,
      throwsA(isA<http.RequestAbortedException>()),
    );
    await Future<void>.delayed(Duration.zero);
    service.dispose();
    await expectation;
    expect(requests, 0);
  });

  test('ארכיון התקנת תוסף ממתין לפני יצירת ההורדה', () async {
    final service = PluginDownloadService(client: client());
    addTearDown(service.dispose);
    final future = service.downloadPluginArchive(
      Uri.parse('https://example.com/plugin.otzplugin'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
    network.add(true);
    final path = await future;
    expect(await File(path).readAsBytes(), bytes);
    await service.cleanupDownloadedArchive(path);
  });

  test('APK ממתין, מאומת ומועבר לבדיקה נייטיבית פעם אחת', () async {
    final platform = FakeAndroidUpdatePlatform();
    final repo = DefaultAndroidUpdateRepository(
      platform: platform,
      clientFactory: client,
      temporaryDirectory: () async => directory,
    );
    addTearDown(repo.dispose);
    final release = AndroidApkRelease(
      tag: '0.9.98.4',
      displayVersion: '0.9.98.4',
      downloadUri: uri,
      size: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      applicationId: 'org.otzaria.otzaria',
      versionCode: 99804,
    );
    final future = repo.download(
      release,
      AndroidDownloadCancellation(),
      (_, _) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
    expect(platform.calls, isEmpty);
    network.add(true);
    final prepared = await future;
    expect(await File(prepared.path).readAsBytes(), bytes);
    expect(platform.calls, ['inspect']);
  });

  test('תעבורת network.fetchStream של תוסף נשארת מחוץ להגבלה', () async {
    final service = PluginNetworkFetchService(
      client: MockClient((request) async => http.Response('online', 200)),
    );
    addTearDown(service.dispose);
    final response = await service.fetchStream(uri);
    expect(await response.body.join(), 'online');
    expect(policy.status, DownloadNetworkStatus.waitingForWifi);
  });

  test('מצב מנותק לבדו משמר את אפשרות הורדת הספרייה הראשונית', () async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue(SettingsRepository.keyOfflineMode, true);
    await Settings.setValue(SettingsRepository.keyDownloadsWifiOnly, false);
    final unmetered = DownloadNetworkPolicy(
      isAndroid: true,
      wifiChanges: () => throw StateError('no transport lookup'),
    );
    addTearDown(unmetered.dispose);
    final transport = DownloadHttpClient(client(), policy: unmetered);
    addTearDown(transport.close);
    expect((await transport.get(uri)).bodyBytes, bytes);
    expect(requests, 1);
  });
}
