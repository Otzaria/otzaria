import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';

class _FakeRepo extends Mock implements PluginRegistryRepository {
  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => [];
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
}

class _OlderArchiveInstaller extends PluginInstallerService {
  _OlderArchiveInstaller() : super(repository: _FakeRepo());

  @override
  Future<PreparedInstall> prepareInstall(
    String archivePath, {
    bool forceOverwrite = false,
  }) async =>
      throw PluginNewerVersionInstalledException('מילון', '1.0.0', '2.0.0');
}

void main() {
  testWidgets(
    'older local archive shows a readable message',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      final bloc = PluginSystemBloc(
        repository: _FakeRepo(),
        installerService: _OlderArchiveInstaller(),
      );
      addTearDown(bloc.close);

      bloc.add(const InstallPluginRequested('/tmp/old.otzplugin'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Instance of'), findsNothing);
      expect(find.textContaining('2.0.0'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    },
  );
}
