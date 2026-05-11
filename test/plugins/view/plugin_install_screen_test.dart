import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/plugins/view/plugin_install_screen.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/core/ui_snack.dart';

// ────────────────────────────────────────────────
// Fakes & helpers

class _FakeRepo extends Mock implements PluginRegistryRepository {
  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => [];
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
  @override
  Future<InstalledPlugin?> getPlugin(String id) async => null;
  @override
  Future<bool?> getPermission(String id, String perm) async => true;
  @override
  Future<void> setPermission(String id, String perm, bool granted) async {}
  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];
}

/// installer שלא עושה כלום — מונע async תלוי-קבצים ב-tearDown.
class _FakeInstallerService extends PluginInstallerService {
  _FakeInstallerService() : super(repository: _FakeRepo());

  @override
  Future<void> cancelInstall(String tempDirPath) async {}
}

/// מאפשר emit ידני מחוץ לבלוק בטסטים בלבד.
class _TestableBloc extends PluginSystemBloc {
  _TestableBloc()
      : super(
          repository: _FakeRepo(),
          installerService: _FakeInstallerService(),
        );
  void testEmit(PluginSystemState state) => emit(state);
}

PluginManifest _manifest({List<String> permissions = const []}) =>
    PluginManifest(
      schemaVersion: 1,
      id: 'test.plugin',
      name: 'תוסף בדיקה',
      version: '1.0.0',
      description: 'תיאור תוסף',
      author: 'בודק',
      homepage: 'https://test.com',
      entrypoint: 'index.html',
      minAppVersion: '1.0.0',
      sdkVersion: '1.0.0',
      permissions: permissions,
      networkEnabled: false,
      networkAllowlist: [],
      toolTabTitle: 'Tab',
      toolTabOrder: 0,
      defaultPinned: true,
      publishedDataTypes: [],
    );

/// פותח את PluginInstallScreen כ-Dialog (כמו בקוד האמיתי) ומחזיר את ה-Widget.
Future<void> _openDialog(
  WidgetTester tester,
  _TestableBloc bloc,
  PluginManifest manifest,
) async {
  // Dialog height = screen_height - 2*60. Content ~570px → צריך מסך גבוה מ-690px.
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: BlocProvider<PluginSystemBloc>.value(
        value: bloc,
        child: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => showDialog(
                context: ctx,
                barrierDismissible: false,
                builder: (_) => BlocProvider<PluginSystemBloc>.value(
                  value: bloc,
                  child: PluginInstallScreen(
                    manifest: manifest,
                    tempDirPath: '/tmp/t',
                  ),
                ),
              ),
              child: const Text('פתח'),
            ),
          );
        }),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

// ────────────────────────────────────────────────

void main() {
  late _TestableBloc bloc;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    bloc = _TestableBloc();
  });

  tearDown(() => bloc.close());

  // ── מבנה ──

  testWidgets('PluginInstallScreen מוצג כ-Dialog', (tester) async {
    await _openDialog(tester, bloc, _manifest());

    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('PluginInstallScreen מציג שם תוסף', (tester) async {
    await _openDialog(tester, bloc, _manifest());

    expect(find.text('תוסף בדיקה'), findsWidgets);
  });

  testWidgets('PluginInstallScreen מציג מחבר וגרסה', (tester) async {
    await _openDialog(tester, bloc, _manifest());

    expect(find.text('בודק'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
  });

  // ── הרשאות ──

  testWidgets('ללא הרשאות — מוצגת הודעת "אין הרשאות מיוחדות נדרשות"',
      (tester) async {
    await _openDialog(tester, bloc, _manifest());

    expect(find.text('אין הרשאות מיוחדות נדרשות'), findsOneWidget);
  });

  testWidgets('עם הרשאות — כותרת "הרשאות נדרשות" מוצגת', (tester) async {
    await _openDialog(tester, bloc, _manifest(permissions: ['network']));

    expect(find.text('הרשאות נדרשות'), findsOneWidget);
  });

  // ── כפתורים ──

  testWidgets('לחיצה על ביטול סוגרת את הדיאלוג', (tester) async {
    await _openDialog(tester, bloc, _manifest());

    await tester.ensureVisible(find.text('ביטול'));
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('לחיצה על התקן סוגרת את הדיאלוג', (tester) async {
    await _openDialog(tester, bloc, _manifest());

    await tester.ensureVisible(find.text('התקן'));
    await tester.tap(find.text('התקן'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });

  // ── BlocListener פותח Dialog ──

  testWidgets(
      'כש-BlocListener מקבל PluginSystemInstallRequiresPermissions — Dialog נפתח',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: BlocProvider<PluginSystemBloc>.value(
          value: bloc,
          child: BlocListener<PluginSystemBloc, PluginSystemState>(
            listenWhen: (_, current) =>
                current is PluginSystemInstallRequiresPermissions,
            listener: (context, state) {
              if (state is PluginSystemInstallRequiresPermissions) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => BlocProvider<PluginSystemBloc>.value(
                    value: context.read<PluginSystemBloc>(),
                    child: PluginInstallScreen(
                      manifest: state.manifest,
                      tempDirPath: state.tempDirPath,
                    ),
                  ),
                );
              }
            },
            child: const Scaffold(body: Text('מסך ראשי')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);

    bloc.testEmit(PluginSystemInstallRequiresPermissions(
      manifest: _manifest(),
      tempDirPath: '/tmp/dltest',
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(PluginInstallScreen), findsOneWidget);
  });
}
