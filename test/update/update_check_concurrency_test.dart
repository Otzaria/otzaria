import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_quit.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import 'package:otzaria/update/my_update_widget.dart';
import 'package:otzaria/update/updat_compat.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';

import '../test_helpers/memory_cache_provider.dart';

class _Settings extends Cubit<SettingsState> implements SettingsBloc {
  _Settings() : super(SettingsState.initial());
  void setOffline(bool value) => emit(state.copyWith(isOfflineMode: value));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tour extends Cubit<TourState> implements TourCubit {
  _Tour({bool active = false})
    : super(const TourState.inactive().copyWith(isActive: active));
  void finish() => emit(const TourState.inactive());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Window extends Fake implements AppWindowController, AppWindowGeometry {}

class _Network {
  final head = Completer<void>.sync();
  final download = Completer<void>.sync();
  final downloading = Completer<void>.sync();
  int checks = 0;
  int downloads = 0;

  late final client = MockClient.streaming((request, _) async {
    if (request.method == 'HEAD') {
      checks++;
      await head.future;
      return http.StreamedResponse(
        const Stream.empty(),
        302,
        headers: {'location': '/Otzaria/otzaria/releases/tag/9.0.0'},
      );
    }
    if (request.url.host == 'api.github.com') {
      return _response(
        jsonEncode({
          'tag_name': '9.0.0',
          'assets': [
            for (final name in [
              'otzaria-macos.dmg',
              'otzaria-9.0.0-linux.deb',
              'otzaria-9.0.0-linux-arm64.deb',
              'otzaria-9.0.0-windows.exe',
              'otzaria-9.0.0-windows_arm64.exe',
            ])
              {
                'name': name,
                'browser_download_url': 'https://download.test/$name',
              },
          ],
        }),
      );
    }
    if (request.url.host == 'raw.githubusercontent.com') {
      return _response('## 9.0.0\nעדכון');
    }
    if (request.url.host == 'download.test') {
      downloads++;
      if (!downloading.isCompleted) downloading.complete();
      await download.future;
      return _response('installer bytes');
    }
    throw StateError('Unexpected request: ${request.url}');
  });

  http.StreamedResponse _response(String body) => http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    200,
  );

  void release() {
    if (!head.isCompleted) head.complete();
    if (!download.isCompleted) download.complete();
  }
}

class _Launcher extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;
  final entered = Completer<void>.sync();
  final finish = Completer<bool>.sync();
  @override
  Future<bool> canLaunch(String url) async => true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) {
    entered.complete();
    return finish.future;
  }
}

void main() {
  late Directory isolatedTemp;
  late _Settings settings;
  late _Tour tour;
  late _Network network;
  late ManagedUpdateScope update;

  setUp(() async {
    isolatedTemp = Directory.systemTemp.createTempSync('otzaria-update-test-');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    PackageInfo.setMockInitialValues(
      appName: 'otzaria',
      packageName: 'otzaria',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(() async {
    network.release();
    await settings.close();
    await tour.close();
    releaseCacheForTesting.clear();
    isolatedTemp.deleteSync(recursive: true);
  });

  void arrange({bool activeTour = false}) {
    settings = _Settings();
    tour = _Tour(active: activeTour);
    network = _Network();
  }

  Future<void> withNetwork(Future<void> Function() body) =>
      IOOverrides.runZoned(
        () => http.runWithClient(body, () => network.client),
        getSystemTempDirectory: () => isolatedTemp,
      );

  Future<void> mount(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      network.release();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    });
    final window = _Window();
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TourCubit>.value(value: tour),
          ],
          child: AppWindowScope(
            controller: window,
            geometry: window,
            child: ManagedUpdateHost(
              child: Builder(
                builder: (context) {
                  update = ManagedUpdateScope.maybeOf(context)!;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> finishDownload(WidgetTester tester) async {
    network.download.complete();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 600; attempt++) {
        final files = updateWorkingDirectory().listSync().whereType<File>();
        if (files.any((file) => !file.path.endsWith('.part'))) return;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('המתקין לא הוכן בתיקיית הבדיקה');
    });
    await tester.pumpAndSettle();
  }

  testWidgets('manual check joins the real automatic check', (tester) async {
    arrange();
    await withNetwork(() async {
      await mount(tester);
      await tester.pump();
      expect(network.checks, 1);
      final first = update.checkForUpdate();
      final second = update.checkForUpdate();
      await tester.pump();
      expect(network.checks, 1);
      network.head.complete();
      await tester.pumpAndSettle();
      expect(await first, UpdatStatus.availableWithChangelog);
      expect(await second, UpdatStatus.availableWithChangelog);
      expect(update.status, UpdatStatus.availableWithChangelog);
      await tester.pumpWidget(const SizedBox());
    });
  });

  for (final ready in [false, true]) {
    testWidgets(
      'manual check preserves ${ready ? 'prepared installer' : 'active download'}',
      (tester) async {
        arrange();
        network.head.complete();
        await withNetwork(() async {
          await mount(tester);
          await tester.pumpAndSettle();
          expect(update.status, UpdatStatus.availableWithChangelog);
          await tester.runAsync(() async {
            update.startUpdate();
            await network.downloading.future.timeout(
              const Duration(seconds: 10),
            );
          });
          if (ready) await finishDownload(tester);
          await tester.pumpAndSettle();
          final before = ready
              ? UpdatStatus.readyToInstall
              : UpdatStatus.downloading;
          expect(update.status, before);
          expect(await update.checkForUpdate(), isNull);
          await tester.pumpAndSettle();
          expect(update.status, before);
          expect(network.checks, 1);
          await Settings.setValue(SettingsRepository.keyOfflineMode, true);
          settings.setOffline(true);
          await tester.pump();
          expect(await update.checkForUpdate(), isNull);
          await tester.pump();
          expect(update.status, before);
          await Settings.setValue(SettingsRepository.keyOfflineMode, false);
          settings.setOffline(false);
          await tester.pump();
          expect(network.checks, 1);
          expect(update.status, before);
          if (ready && Platform.isMacOS) {
            final original = UrlLauncherPlatform.instance;
            final launcher = _Launcher();
            UrlLauncherPlatform.instance = launcher;
            addTearDown(() => UrlLauncherPlatform.instance = original);
            final launched = update.launchInstaller();
            await tester.pump();
            await launcher.entered.future;
            expect(update.awaitingClose, isTrue);
            expect(await update.checkForUpdate(), isNull);
            await tester.pump();
            expect(network.checks, 1);
            AppQuit.install(() async {});
            addTearDown(AppQuit.resetForTest);
            launcher.finish.complete(true);
            await tester.pump();
            await launched;
          } else if (!ready) {
            update.startUpdate();
          }
          await tester.pump();
          expect(network.downloads, 1);
          if (!ready) {
            network.download.complete();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
          }
          await tester.pumpWidget(const SizedBox());
        });
      },
    );
  }

  testWidgets(
    'ending a tour before the next due date preserves a manual result',
    (tester) async {
      arrange(activeTour: true);
      await Settings.setValue(
        SettingsRepository.keyUpdateCheckFrequency,
        'daily',
      );
      await Settings.setValue(
        SettingsRepository.keyLastSoftwareUpdateCheck,
        DateTime.now().toIso8601String(),
      );
      network.head.complete();
      await withNetwork(() async {
        await mount(tester);
        final checked = update.checkForUpdate();
        await tester.pumpAndSettle();
        expect(await checked, UpdatStatus.availableWithChangelog);
        tour.finish();
        await tester.pumpAndSettle();
        expect(update.status, UpdatStatus.availableWithChangelog);
        expect(network.checks, 1);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
  testWidgets(
    'ending a tour waits for a pending manual check despite frequency',
    (tester) async {
      arrange(activeTour: true);
      await Settings.setValue(
        SettingsRepository.keyUpdateCheckFrequency,
        'daily',
      );
      await Settings.setValue(
        SettingsRepository.keyLastSoftwareUpdateCheck,
        DateTime.now().toIso8601String(),
      );
      await withNetwork(() async {
        await mount(tester);
        final check = update.checkForUpdate();
        await tester.pump();
        var resolved = false;
        initialSoftwareUpdateResultForTesting.then((_) => resolved = true);
        tour.finish();
        await tester.pump();
        expect(resolved, isFalse);
        expect(network.checks, 1);
        network.head.complete();
        await tester.pumpAndSettle();
        expect(await check, UpdatStatus.availableWithChangelog);
        expect(await initialSoftwareUpdateResultForTesting, isTrue);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
  testWidgets(
    'prepared installer before tour completion keeps startup priority',
    (tester) async {
      arrange(activeTour: true);
      await Settings.setValue(
        SettingsRepository.keyUpdateCheckFrequency,
        'daily',
      );
      await Settings.setValue(
        SettingsRepository.keyLastSoftwareUpdateCheck,
        DateTime.now().toIso8601String(),
      );
      network.head.complete();
      await withNetwork(() async {
        await mount(tester);
        final checked = update.checkForUpdate();
        await tester.pumpAndSettle();
        expect(await checked, UpdatStatus.availableWithChangelog);
        await tester.runAsync(() async {
          update.startUpdate();
          await network.downloading.future.timeout(const Duration(seconds: 10));
        });
        await finishDownload(tester);
        await tester.pumpAndSettle();
        expect(update.status, UpdatStatus.readyToInstall);
        tour.finish();
        await tester.pumpAndSettle();
        expect(update.status, UpdatStatus.readyToInstall);
        expect(await initialSoftwareUpdateResultForTesting, isTrue);
        expect(network.checks, 1);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
}
