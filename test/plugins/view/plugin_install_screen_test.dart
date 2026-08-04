import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/plugins/view/plugin_install_screen.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/controls/custom_switch.dart';

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

  @override
  Future<void> finalizeInstall(
    String tempDirPath,
    dynamic manifest, {
    required bool allowOrderBeforeBuiltInsGranted,
  }) async {}
}

/// מאפשר emit ידני מחוץ לבלוק בטסטים בלבד.
/// מאחסן את כל האירועים שנשלחים ב-[capturedEvents] לאימות ב-payload tests.
class _TestableBloc extends PluginSystemBloc {
  _TestableBloc({this.processEvents = true})
    : super(
        repository: _FakeRepo(),
        installerService: _FakeInstallerService(),
      );
  final bool processEvents;

  void testEmit(PluginSystemState state) => emit(state);

  final List<PluginSystemEvent> capturedEvents = [];

  @override
  void add(PluginSystemEvent event) {
    capturedEvents.add(event);
    if (processEvents) {
      super.add(event);
    }
  }
}

PluginManifest _manifest({
  List<String> permissions = const [],
  String version = '1.0.0',
  bool allowOrderBeforeBuiltIns = false,
}) => PluginManifest(
  schemaVersion: 1,
  id: 'test.plugin',
  name: 'תוסף בדיקה',
  version: version,
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
  allowOrderBeforeBuiltIns: allowOrderBeforeBuiltIns,
  defaultPinned: true,
  publishedDataTypes: [],
);

/// פותח את PluginInstallScreen כ-Dialog (כמו בקוד האמיתי) ומחזיר את ה-Widget.
///
/// [screenHeight] — גובה מסך הבדיקה. ברירת מחדל 900px מתאימה לתוכן בסיסי.
/// כשיש באנר + הרשאות (תוכן ארוך יותר) יש להעביר ערך גבוה יותר (למשל 1400).
Future<void> _openDialog(
  WidgetTester tester,
  _TestableBloc bloc,
  PluginManifest manifest, {
  String? previousVersion,
  bool? previousAllowOrderBeforeBuiltInsGranted,
  PluginInstallReportContext? reportContext,
  bool isOfflineMode = false,
  double screenHeight = 900,
}) async {
  // רוחב 1400 מדמה דסקטופ — הדיאלוג מקבל width = 1400 * 0.5 = 700px,
  // מספיק רחב כדי שתוכן הדיאלוג לא יתעטף לגובה בלתי צפוי בטסטים.
  tester.view.physicalSize = Size(1400, screenHeight);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: BlocProvider<PluginSystemBloc>.value(
        value: bloc,
        child: Builder(
          builder: (ctx) {
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
                      previousVersion: previousVersion,
                      previousAllowOrderBeforeBuiltInsGranted:
                          previousAllowOrderBeforeBuiltInsGranted,
                      reportContext: reportContext,
                      isOfflineMode: isOfflineMode,
                    ),
                  ),
                ),
                child: const Text('פתח'),
              ),
            );
          },
        ),
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

    expect(find.textContaining('תוסף בדיקה'), findsWidgets);
  });

  testWidgets('PluginInstallScreen מציג מחבר וגרסה', (tester) async {
    await _openDialog(tester, bloc, _manifest());

    expect(find.text('מחבר: בודק'), findsOneWidget);
    expect(find.text('גרסה 1.0.0'), findsOneWidget);
  });

  // ── הרשאות ──

  testWidgets('ללא הרשאות — מוצגת הודעת "אין הרשאות מיוחדות נדרשות"', (
    tester,
  ) async {
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

  testWidgets('הקשר דיווח נשמר באירועי אישור וביטול ההתקנה', (tester) async {
    final captureOnlyBloc = _TestableBloc(processEvents: false);
    addTearDown(captureOnlyBloc.close);
    final reportContext = PluginInstallReportContext(
      token: 'one-time',
      callbackUrl: Uri(scheme: 'https', host: 'store.example.com'),
    );

    await _openDialog(
      tester,
      captureOnlyBloc,
      _manifest(),
      reportContext: reportContext,
    );
    await tester.ensureVisible(find.text('התקן'));
    await tester.tap(find.text('התקן'));
    await tester.pumpAndSettle();

    expect(
      captureOnlyBloc.capturedEvents
          .whereType<ConfirmPluginInstall>()
          .single
          .reportContext,
      reportContext,
    );

    await _openDialog(
      tester,
      captureOnlyBloc,
      _manifest(),
      reportContext: reportContext,
    );
    await tester.ensureVisible(find.text('ביטול'));
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(
      captureOnlyBloc.capturedEvents
          .whereType<CancelPluginInstall>()
          .single
          .reportContext,
      reportContext,
    );
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
                        previousAllowOrderBeforeBuiltInsGranted:
                            state.previousAllowOrderBeforeBuiltInsGranted,
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

      bloc.testEmit(
        PluginSystemInstallRequiresPermissions(
          manifest: _manifest(),
          tempDirPath: '/tmp/dltest',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(PluginInstallScreen), findsOneWidget);
    },
  );

  // ── מצב עדכון ──

  testWidgets('עדכון — כותרת הדיאלוג כוללת שם תוסף ו"עדכון"', (tester) async {
    await _openDialog(tester, bloc, _manifest(), previousVersion: '1.0.0');

    expect(find.text('עדכון תוסף: תוסף בדיקה'), findsOneWidget);
    expect(find.text('התקנת תוסף: תוסף בדיקה'), findsNothing);
  });

  testWidgets('התקנה ראשונה — כותרת הדיאלוג כוללת שם תוסף ו"התקנת"', (
    tester,
  ) async {
    await _openDialog(tester, bloc, _manifest());

    expect(find.text('התקנת תוסף: תוסף בדיקה'), findsOneWidget);
    expect(find.text('עדכון תוסף: תוסף בדיקה'), findsNothing);
  });

  testWidgets('עדכון — מוצגת שורת מעבר גרסאות עם חץ', (tester) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(version: '2.0.0'),
      previousVersion: '1.0.0',
    );

    expect(find.text('עדכון גרסה 1.0.0  ←  2.0.0'), findsOneWidget);
  });

  testWidgets('התקנה ראשונה — מוצגת גרסה בסאבטייטל', (tester) async {
    await _openDialog(tester, bloc, _manifest(version: '2.0.0'));

    expect(find.text('גרסה 2.0.0'), findsOneWidget);
  });

  testWidgets('עדכון — כפתור פעולה מציג "עדכן"', (tester) async {
    await _openDialog(tester, bloc, _manifest(), previousVersion: '0.9.0');

    await tester.ensureVisible(find.text('עדכן'));
    expect(find.text('עדכן'), findsOneWidget);
    expect(find.text('התקן'), findsNothing);
  });

  testWidgets('התקנה ראשונה — כפתור פעולה מציג "התקן"', (tester) async {
    await _openDialog(tester, bloc, _manifest());

    await tester.ensureVisible(find.text('התקן'));
    expect(find.text('התקן'), findsOneWidget);
    expect(find.text('עדכן'), findsNothing);
  });

  // ── הרשאת run_on_startup ──

  testWidgets('תוסף שמבקש app.run_on_startup — מוצג באנר בולט עם אזהרה', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: [pluginRunOnStartupPermission]),
    );

    expect(
      find.text('התוסף מבקש לפעול ברקע עם עליית האפליקציה'),
      findsOneWidget,
    );
    expect(find.byIcon(FluentIcons.warning_24_filled), findsWidgets);
  });

  testWidgets('תוסף שלא מבקש app.run_on_startup — אין באנר בולט', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: ['app.info.read']),
    );

    expect(
      find.text('התוסף מבקש לפעול ברקע עם עליית האפליקציה'),
      findsNothing,
    );
  });

  testWidgets('הרשאת app.run_on_startup — Switch מתחיל כבוי ברירת מחדל', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: [pluginRunOnStartupPermission]),
      screenHeight: 1400,
    );

    final rowFinder = find.ancestor(
      of: find.text('טעינה אוטומטית עם עליית האפליקציה'),
      matching: find.byType(ListTile),
    );
    expect(rowFinder, findsOneWidget);
    final sw = tester.widget<CustomSwitch>(
      find.descendant(of: rowFinder, matching: find.byType(CustomSwitch)),
    );
    expect(sw.value, isFalse);
  });

  testWidgets('הרשאה רגילה — Switch מתחיל דלוק ברירת מחדל', (tester) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: ['app.info.read']),
    );

    final rowFinder = find.ancestor(
      of: find.text('מידע אפליקציה'),
      matching: find.byType(ListTile),
    );
    expect(rowFinder, findsOneWidget);
    final sw = tester.widget<CustomSwitch>(
      find.descendant(of: rowFinder, matching: find.byType(CustomSwitch)),
    );
    expect(sw.value, isTrue);
  });

  // ── הרשאת network.access במצב מנותק ──

  testWidgets('במצב מקוון — הרשאת גישה לאינטרנט מתחילה דלוקה', (tester) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: [pluginNetworkAccessPermission]),
    );

    final rowFinder = find.ancestor(
      of: find.text('גישה לאינטרנט'),
      matching: find.byType(ListTile),
    );
    expect(rowFinder, findsOneWidget);
    final sw = tester.widget<CustomSwitch>(
      find.descendant(of: rowFinder, matching: find.byType(CustomSwitch)),
    );
    expect(sw.value, isTrue);
  });

  testWidgets('במצב מנותק — הרשאת גישה לאינטרנט מתחילה כבויה ברירת מחדל', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: [pluginNetworkAccessPermission]),
      isOfflineMode: true,
    );

    final rowFinder = find.ancestor(
      of: find.text('גישה לאינטרנט'),
      matching: find.byType(ListTile),
    );
    expect(rowFinder, findsOneWidget);
    final sw = tester.widget<CustomSwitch>(
      find.descendant(of: rowFinder, matching: find.byType(CustomSwitch)),
    );
    expect(sw.value, isFalse);
  });

  testWidgets(
    'במצב מנותק — לחיצה על התקן שולחת ConfirmPluginInstall עם network.access=false',
    (tester) async {
      await _openDialog(
        tester,
        bloc,
        _manifest(permissions: [pluginNetworkAccessPermission]),
        isOfflineMode: true,
      );

      await tester.ensureVisible(find.text('התקן'));
      await tester.tap(find.text('התקן'));
      await tester.pumpAndSettle();

      final confirmEvents = bloc.capturedEvents
          .whereType<ConfirmPluginInstall>();
      expect(confirmEvents, isNotEmpty);
      expect(
        confirmEvents.first.grantedPermissions[pluginNetworkAccessPermission],
        isFalse,
        reason: 'network.access חייב להיות false ברירת מחדל בהתקנה במצב מנותק',
      );
    },
  );

  testWidgets(
    'תוסף שמבקש להופיע לפני כלים מובנים — מוצג switch ייעודי במסך ההתקנה',
    (tester) async {
      await _openDialog(
        tester,
        bloc,
        _manifest(allowOrderBeforeBuiltIns: true),
      );

      expect(
        find.text('אפשר לתוסף להופיע לפני הכלים המובנים'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'תוסף שלא מבקש להופיע לפני כלים מובנים — ה-switch הייעודי לא מוצג',
    (tester) async {
      await _openDialog(tester, bloc, _manifest());

      expect(
        find.text('אפשר לתוסף להופיע לפני הכלים המובנים'),
        findsNothing,
      );
    },
  );

  testWidgets('הקדמה לפני כלים מובנים מתחילה דלוקה כברירת מחדל בהתקנה ראשונה', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(allowOrderBeforeBuiltIns: true),
    );

    final rowFinder = find.ancestor(
      of: find.text('אפשר לתוסף להופיע לפני הכלים המובנים'),
      matching: find.byType(ListTile),
    );
    expect(rowFinder, findsOneWidget);
    final sw = tester.widget<CustomSwitch>(
      find.descendant(of: rowFinder, matching: find.byType(CustomSwitch)),
    );
    expect(sw.value, isTrue);
  });

  testWidgets(
    'בעדכון נשמרת הבחירה הקודמת של המשתמש לגבי הקדמת התוסף לפני כלים מובנים',
    (tester) async {
      await _openDialog(
        tester,
        bloc,
        _manifest(allowOrderBeforeBuiltIns: true),
        previousVersion: '1.0.0',
        previousAllowOrderBeforeBuiltInsGranted: false,
      );

      final rowFinder = find.ancestor(
        of: find.text('אפשר לתוסף להופיע לפני הכלים המובנים'),
        matching: find.byType(ListTile),
      );
      expect(rowFinder, findsOneWidget);
      final sw = tester.widget<CustomSwitch>(
        find.descendant(of: rowFinder, matching: find.byType(CustomSwitch)),
      );
      expect(sw.value, isFalse);
    },
  );

  // ── payload של ConfirmPluginInstall ──────────────────────────────────────
  //
  // בודקים שהאירוע שנשלח לבלוק מכיל את ערכי ההרשאות הנכונים —
  // לא רק שה-UI מציג את מצב ה-Switch הנכון.

  testWidgets(
    'לחיצה על התקן שולחת ConfirmPluginInstall עם app.run_on_startup=false כברירת מחדל',
    (tester) async {
      await _openDialog(
        tester,
        bloc,
        _manifest(permissions: [pluginRunOnStartupPermission]),
        screenHeight: 1400,
      );

      await tester.ensureVisible(find.text('התקן'));
      await tester.tap(find.text('התקן'));
      await tester.pumpAndSettle();

      final confirmEvents = bloc.capturedEvents
          .whereType<ConfirmPluginInstall>();
      expect(confirmEvents, isNotEmpty);
      final permissions = confirmEvents.first.grantedPermissions;
      expect(
        permissions[pluginRunOnStartupPermission],
        isFalse,
        reason: 'app.run_on_startup חייב להיות false ברירת מחדל',
      );
    },
  );

  testWidgets(
    'לחיצה על התקן שולחת ConfirmPluginInstall עם הרשאה רגילה=true כברירת מחדל',
    (tester) async {
      await _openDialog(
        tester,
        bloc,
        _manifest(permissions: ['app.info.read']),
      );

      await tester.ensureVisible(find.text('התקן'));
      await tester.tap(find.text('התקן'));
      await tester.pumpAndSettle();

      final confirmEvents = bloc.capturedEvents
          .whereType<ConfirmPluginInstall>();
      expect(confirmEvents, isNotEmpty);
      expect(
        confirmEvents.first.grantedPermissions['app.info.read'],
        isTrue,
        reason: 'הרשאה רגילה חייבת להיות true ברירת מחדל',
      );
    },
  );

  testWidgets(
    'הפעלת Switch של app.run_on_startup ולחיצה על התקן → payload מכיל true',
    (tester) async {
      await _openDialog(
        tester,
        bloc,
        _manifest(permissions: [pluginRunOnStartupPermission]),
        screenHeight: 1400,
      );

      final rowFinder = find.ancestor(
        of: find.text('טעינה אוטומטית עם עליית האפליקציה'),
        matching: find.byType(ListTile),
      );
      await tester.ensureVisible(rowFinder);
      await tester.tap(rowFinder);
      await tester.pump();

      await tester.ensureVisible(find.text('התקן'));
      await tester.tap(find.text('התקן'));
      await tester.pumpAndSettle();

      final confirmEvents = bloc.capturedEvents
          .whereType<ConfirmPluginInstall>();
      expect(confirmEvents, isNotEmpty);
      expect(
        confirmEvents.first.grantedPermissions[pluginRunOnStartupPermission],
        isTrue,
        reason:
            'לאחר הפעלת ה-Switch, app.run_on_startup חייב להיות true ב-payload',
      );
    },
  );

  testWidgets(
    'מעורב: app.run_on_startup=false, הרשאה רגילה=true בלחיצה ראשונה על התקן',
    (tester) async {
      await _openDialog(
        tester,
        bloc,
        _manifest(permissions: [pluginRunOnStartupPermission, 'app.info.read']),
        screenHeight: 1400,
      );

      await tester.ensureVisible(find.text('התקן'));
      await tester.tap(find.text('התקן'));
      await tester.pumpAndSettle();

      final confirmEvents = bloc.capturedEvents
          .whereType<ConfirmPluginInstall>();
      expect(confirmEvents, isNotEmpty);
      final perms = confirmEvents.first.grantedPermissions;
      expect(
        perms[pluginRunOnStartupPermission],
        isFalse,
        reason: 'app.run_on_startup חייב להיות false',
      );
      expect(
        perms['app.info.read'],
        isTrue,
        reason: 'app.info.read חייב להיות true',
      );
    },
  );

  testWidgets(
    'כיבוי האפשרות להופיע לפני כלים מובנים נשלח ב-ConfirmPluginInstall',
    (tester) async {
      await _openDialog(
        tester,
        bloc,
        _manifest(allowOrderBeforeBuiltIns: true),
        screenHeight: 1400,
      );

      final rowFinder = find.ancestor(
        of: find.text('אפשר לתוסף להופיע לפני הכלים המובנים'),
        matching: find.byType(ListTile),
      );
      await tester.ensureVisible(rowFinder);
      await tester.tap(rowFinder);
      await tester.pump();

      await tester.ensureVisible(find.text('התקן'));
      await tester.tap(find.text('התקן'));
      await tester.pumpAndSettle();

      final confirmEvents = bloc.capturedEvents
          .whereType<ConfirmPluginInstall>();
      expect(confirmEvents, isNotEmpty);
      expect(confirmEvents.first.allowOrderBeforeBuiltInsGranted, isFalse);
    },
  );
}
