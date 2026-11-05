import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_download_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _FakeRepo extends Mock implements PluginRegistryRepository {
  @override
  Future<String?> getNewTabPageOwner() async => null;

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => [];
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
}

/// לוכד את גרסת האפליקציה שנשלחת לחנות, ועוצר את ההתקנה מיד אחריה.
class _RecordingDownloadService extends PluginDownloadService {
  final appVersions = <String?>[];

  @override
  Future<String> downloadPluginArchive(
    Uri downloadUri, {
    String? appVersion,
    bool storeOnly = false,
  }) async {
    appVersions.add(appVersion);
    throw Exception('stop');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final (platform, storeVersion) in [
    (TargetPlatform.windows, '0.9.98'),
    (TargetPlatform.iOS, '0.9.9801'),
  ]) {
    test('$platform: store download sends the hotfix version', () async {
      debugDefaultTargetPlatformOverride = platform;
      PackageInfo.setMockInitialValues(
        appName: 'Otzaria',
        packageName: 'com.otzaria.app',
        version: storeVersion,
        buildNumber: '99801',
        buildSignature: '',
      );
      final download = _RecordingDownloadService();
      final bloc = PluginSystemBloc(
        repository: _FakeRepo(),
        downloadService: download,
      );
      addTearDown(bloc.close);

      bloc.add(
        const InstallRemotePluginRequested(
          'https://otzaria.org/api/plugins/test.plugin/download',
        ),
      );
      await pumpEventQueue();

      expect(download.appVersions, ['0.9.98.1']);
    });
  }
}
