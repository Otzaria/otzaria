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
import 'package:otzaria/plugins/models/plugin_startup_contributions.dart';
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
    required Map<String, bool> grantedPermissions,
    InstalledPlugin? expectedPlugin,
    Map<String, bool> expectedPermissions = const {},
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
  PluginStartupContributions? startup,
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
  defaultPinned: true,
  publishedDataTypes: [],
  startup: startup,
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
  Map<String, bool> previousGrantedPermissions = const {},
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
                      previousGrantedPermissions: previousGrantedPermissions,
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

  testWidgets('תוסף דקלרטיבי מציג את אירועי ההפעלה ואת מגבלת שלוש הדקות', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(
        permissions: [pluginRunOnStartupPermission],
        startup: const PluginStartupContributions(
          contextMenuItems: [
            {'id': 'lookup', 'title': 'חיפוש'},
          ],
          activationEvents: ['app.startup'],
        ),
      ),
      screenHeight: 1400,
    );

    expect(
      find.textContaining('לחיצה על פריט בתפריט הטקסט'),
      findsWidgets,
    );
    expect(find.textContaining('3 דקות ללא פעילות'), findsWidgets);
    expect(find.text('הפעלה ברקע לפי אירוע'), findsOneWidget);
  });

  testWidgets('תוסף סטטי בלבד מציג שהרשאת הרקע אינה בשימוש', (tester) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(
        permissions: [pluginRunOnStartupPermission],
        startup: const PluginStartupContributions(
          publishedData: [
            {'type': 'calendar.event', 'key': 'static', 'payload': {}},
          ],
        ),
      ),
      screenHeight: 1400,
    );

    expect(
      find.text('הרשאת הרקע אינה בשימוש בגרסה זו של התוסף'),
      findsOneWidget,
    );
    expect(find.textContaining('אינם מפעילים WebView'), findsOneWidget);
    expect(find.textContaining('התוסף מבקש לפעול ברקע כאשר:'), findsNothing);
  });

  testWidgets('בקשת keepAlive מוצגת בנפרד ומתחילה כבויה', (tester) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(
        permissions: [
          pluginRunOnStartupPermission,
          pluginBackgroundKeepAlivePermission,
        ],
        startup: const PluginStartupContributions(
          activationEvents: ['app.startup'],
          keepAlive: true,
        ),
      ),
      screenHeight: 1700,
    );

    expect(
      find.text('התוסף מבקש שלא יכבו אותו ברקע'),
      findsOneWidget,
    );
    expect(find.textContaining('ללא הגבלת זמן'), findsWidgets);
    final rowFinder = find.ancestor(
      of: find.text('מניעת כיבוי התוסף ברקע'),
      matching: find.byType(ListTile),
    );
    final sw = tester.widget<CustomSwitch>(
      find.descendant(of: rowFinder, matching: find.byType(CustomSwitch)),
    );
    expect(sw.value, isFalse);
  });

  testWidgets('הרשאות כבויות כברירת מחדל מוצגות לפני האחרות', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(
        permissions: [
          'notes.read',
          pluginStartupContributionsPermission,
          pluginRunOnStartupPermission,
          'calendar.read',
        ],
      ),
      screenHeight: 1400,
    );

    final sensitiveY = tester.getTopLeft(find.text('טעינה אוטומטית ברקע')).dy;
    final contributionsY = tester
        .getTopLeft(find.text('הוספת רכיבים לתוכנה'))
        .dy;
    final notesY = tester.getTopLeft(find.text('צפייה בהערות')).dy;
    final calendarY = tester.getTopLeft(find.text('לוח שנה עברי')).dy;
    expect(sensitiveY, lessThan(notesY));
    expect(contributionsY, lessThan(notesY));
    expect(sensitiveY, lessThan(calendarY));
    expect(notesY, lessThan(calendarY), reason: 'סדר המניפסט נשמר בין השאר');
  });

  testWidgets('הרשאת הוספת רכיבים מתחילה כבויה ברירת מחדל', (tester) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: [pluginStartupContributionsPermission]),
      screenHeight: 1400,
    );

    final rowFinder = find.ancestor(
      of: find.text('הוספת רכיבים לתוכנה'),
      matching: find.byType(ListTile),
    );
    final sw = tester.widget<CustomSwitch>(
      find.descendant(of: rowFinder, matching: find.byType(CustomSwitch)),
    );
    expect(sw.value, isFalse);
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
      of: find.text('טעינה אוטומטית ברקע'),
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
      _manifest(permissions: ['notes.read']),
    );

    final rowFinder = find.ancestor(
      of: find.text('צפייה בהערות'),
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

  testWidgets('בקשת הקדמה במניפסט אינה מוצגת לאישור בהתקנה (issue #2460)', (
    tester,
  ) async {
    final manifest = PluginManifest.fromJson({
      ..._manifest().toJson(),
      'contributes': {
        'toolTab': {'title': 'Tab', 'allowOrderBeforeBuiltIns': true},
      },
    });
    await _openDialog(tester, bloc, manifest);

    expect(find.text('מיקום במסך כלים'), findsNothing);
  });

  testWidgets('הגרסה הקודמת נשלחת ב-ConfirmPluginInstall ומסמנת עדכון', (
    tester,
  ) async {
    await _openDialog(tester, bloc, _manifest(), previousVersion: '1.0.0');

    await tester.ensureVisible(find.text('עדכן'));
    await tester.tap(find.text('עדכן'));
    await tester.pumpAndSettle();

    final event = bloc.capturedEvents.whereType<ConfirmPluginInstall>().first;
    expect(event.previousVersion, '1.0.0');
    expect(event.isUpdate, isTrue);
  });

  testWidgets('בהתקנה ראשונה ConfirmPluginInstall אינו מסומן כעדכון', (
    tester,
  ) async {
    await _openDialog(tester, bloc, _manifest());

    await tester.ensureVisible(find.text('התקן'));
    await tester.tap(find.text('התקן'));
    await tester.pumpAndSettle();

    final event = bloc.capturedEvents.whereType<ConfirmPluginInstall>().first;
    expect(event.previousVersion, isNull);
    expect(event.isUpdate, isFalse);
  });

  // ── עדכון: רק הרשאות חדשות/כבויות ──

  testWidgets('עדכון ללא הרשאות חדשות — דיאלוג אישור עדכון בלבד', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: ['app.info.read', 'notes.read']),
      previousVersion: '1.0.0',
      previousGrantedPermissions: const {
        'app.info.read': true,
        'notes.read': true,
      },
    );

    expect(find.text('העדכון אינו מבקש הרשאות חדשות'), findsOneWidget);
    expect(find.text('הרשאות חדשות'), findsNothing);
    expect(find.text('מידע אפליקציה'), findsNothing);
    expect(find.text('צפייה בהערות'), findsNothing);
  });

  testWidgets('עדכון — מוצגת רק ההרשאה החדשה, לא זו שכבר הוענקה', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: ['app.info.read', 'notes.read']),
      previousVersion: '1.0.0',
      previousGrantedPermissions: const {'app.info.read': true},
    );

    expect(find.text('הרשאות חדשות'), findsOneWidget);
    expect(find.text('צפייה בהערות'), findsOneWidget);
    expect(find.text('מידע אפליקציה'), findsNothing);
  });

  testWidgets('עדכון — הרשאה שהמשתמש כיבה מוצגת בכרטיס "הרשאות כבויות"', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: ['app.info.read', 'notes.read']),
      previousVersion: '1.0.0',
      previousGrantedPermissions: const {
        'app.info.read': true,
        'notes.read': false,
      },
      screenHeight: 1400,
    );

    expect(find.text('הרשאות כבויות'), findsOneWidget);
    expect(find.text('הרשאות חדשות'), findsNothing);
    final rowFinder = find.ancestor(
      of: find.text('צפייה בהערות'),
      matching: find.byType(ListTile),
    );
    final sw = tester.widget<CustomSwitch>(
      find.descendant(of: rowFinder, matching: find.byType(CustomSwitch)),
    );
    expect(sw.value, isFalse);
  });

  testWidgets('עדכון — החלטת עבר נשמרת ונשלחת ב-ConfirmPluginInstall', (
    tester,
  ) async {
    await _openDialog(
      tester,
      bloc,
      _manifest(permissions: ['calendar.read', 'notes.read']),
      previousVersion: '1.0.0',
      previousGrantedPermissions: const {'calendar.read': false},
      screenHeight: 1400,
    );

    await tester.ensureVisible(find.text('עדכן'));
    await tester.tap(find.text('עדכן'));
    await tester.pumpAndSettle();

    final perms = bloc.capturedEvents
        .whereType<ConfirmPluginInstall>()
        .first
        .grantedPermissions;
    expect(perms['calendar.read'], isFalse, reason: 'החלטת העבר נשמרת');
    expect(
      perms['notes.read'],
      isTrue,
      reason: 'הרשאה חדשה מוענקת כברירת מחדל',
    );
  });

  testWidgets(
    'עדכון מנותק מציג רשת כחסומה זמנית ושומר את ההרשאה הקודמת',
    (tester) async {
      await _openDialog(
        tester,
        bloc,
        _manifest(permissions: [pluginNetworkAccessPermission]),
        previousVersion: '1.0.0',
        previousGrantedPermissions: const {
          pluginNetworkAccessPermission: true,
        },
        isOfflineMode: true,
      );

      expect(find.text('הרשאות כבויות'), findsOneWidget);
      final rowFinder = find.ancestor(
        of: find.text('גישה לאינטרנט'),
        matching: find.byType(ListTile),
      );
      final sw = tester.widget<CustomSwitch>(
        find.descendant(of: rowFinder, matching: find.byType(CustomSwitch)),
      );
      expect(sw.value, isFalse);
      expect(sw.onChanged, isNull);
      expect(find.textContaining('ההרשאה השמורה תישמר'), findsOneWidget);

      await tester.ensureVisible(find.text('עדכן'));
      await tester.tap(find.text('עדכן'));
      await tester.pumpAndSettle();

      final permissions = bloc.capturedEvents
          .whereType<ConfirmPluginInstall>()
          .first
          .grantedPermissions;
      expect(permissions[pluginNetworkAccessPermission], isTrue);
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
        _manifest(permissions: ['notes.read']),
      );

      await tester.ensureVisible(find.text('התקן'));
      await tester.tap(find.text('התקן'));
      await tester.pumpAndSettle();

      final confirmEvents = bloc.capturedEvents
          .whereType<ConfirmPluginInstall>();
      expect(confirmEvents, isNotEmpty);
      expect(
        confirmEvents.first.grantedPermissions['notes.read'],
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
        of: find.text('טעינה אוטומטית ברקע'),
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
        _manifest(permissions: [pluginRunOnStartupPermission, 'notes.read']),
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
        perms['notes.read'],
        isTrue,
        reason: 'notes.read חייב להיות true',
      );
    },
  );
}
