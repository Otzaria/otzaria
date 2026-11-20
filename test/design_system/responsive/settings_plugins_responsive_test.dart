// Responsive: מסך ההגדרות (כל הלשוניות, כשכל הכרטיסים הנפתחים פתוחים), ניהול
// התוספים וחלוניות התוספים. כל מסך נבדק מול מטריצת החלונות ומול מצבי קצה
// (הגדלת טקסט 1.5 ו-2.0 ברוחב 320 ו-600, צפיפות מצומצמת, כהה): בלי overflow,
// בלי גלילה אופקית, והפעולות החיוניות נגישות.
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/bloc/attached_libraries_bloc.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library_navigation_history.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/bloc/plugin_updates_cubit.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/external_catalog/view/external_catalog_settings_helper.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/services/plugin_update_check_service.dart';
import 'package:otzaria/plugins/utils/plugin_toolbar_actions.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/view/plugin_confirmation_dialog.dart';
import 'package:otzaria/plugins/view/plugin_install_screen.dart';
import 'package:otzaria/plugins/view/plugin_settings_screen.dart';
import 'package:otzaria/settings/dialogs/books_list_dialog.dart';
import 'package:otzaria/settings/dialogs/color_picker_dialog.dart';
import 'package:otzaria/settings/dialogs/offline_donation_dialog.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';
import 'package:otzaria/settings/shortcuts/dynamic_shortcut_dialog.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_tab_scroll_view.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/widgets/misc/expanding_chevron.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;

import '../../test_helpers/memory_cache_provider.dart';
import 'responsive_harness.dart';

// ── תלויות מדומות ────────────────────────────────────────────────────────────

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {
  @override
  final navigationHistory = LibraryNavigationHistory();
}

class _MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class _MockAttachedLibrariesBloc
    extends MockBloc<AttachedLibrariesEvent, AttachedLibrariesState>
    implements AttachedLibrariesBloc {}

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _OpenEngine implements SearchEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePluginSystemBloc extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  _FakePluginSystemBloc(List<InstalledPlugin> plugins)
    : super(PluginSystemLoaded(plugins)) {
    on<PluginSystemEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedUpdatesCubit extends PluginUpdatesCubit {
  _FixedUpdatesCubit(Map<String, PluginUpdateInfo> updates) {
    emit(PluginUpdatesState(updates));
  }
}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

// ── תוספים לדוגמה ────────────────────────────────────────────────────────────

const _longName =
    'תוסף עם שם ארוך מאוד שממשיך ומתארך כדי לבדוק גלישה בשורת התוסף בהגדרות';
const _longDescription =
    'תיאור ארוך של התוסף שחוזר על עצמו כדי לבדוק התנהגות בחלון צר. '
    'כולל כתובת https://example.com/a/very/long/path/that/never/breaks/anywhere '
    'ושם באנגלית: SomeVeryLongEnglishIdentifierThatHasNoBreakOpportunitiesAtAll.';

PluginManifest _manifest({
  required String id,
  required String name,
  String description = '',
  List<String> permissions = const [],
  bool networkEnabled = false,
  bool headless = false,
}) => PluginManifest.fromJson({
  'schemaVersion': 1,
  'id': id,
  'name': name,
  'description': description,
  'version': '1.0.0',
  'author': 'מחבר התוסף',
  'entrypoint': 'index.html',
  'headless': headless,
  'permissions': permissions,
  'network': {'enabled': networkEnabled},
  'contributes': {
    'toolTab': {'title': name},
  },
});

InstalledPlugin _plugin(
  String id,
  String name, {
  String description = '',
  bool enabled = true,
  bool showInTools = true,
  bool pinnedToNavRail = false,
  bool network = false,
  bool startup = false,
  bool headless = false,
  String sourceType = 'packaged',
  List<String> permissions = const [],
}) => InstalledPlugin(
  pluginId: id,
  name: name,
  version: '1.0.0',
  installPath: '/x/$id',
  entrypointPath: 'index.html',
  enabled: enabled,
  pinned: true,
  pinnedToNavRail: pinnedToNavRail,
  showInTools: showInTools,
  networkAccessGranted: network,
  runOnStartupGranted: startup,
  sourceType: sourceType,
  devRootPath: sourceType == 'development' ? 'C:/dev/$id' : null,
  manifest: _manifest(
    id: id,
    name: name,
    description: description,
    permissions: permissions,
    networkEnabled: network,
    headless: headless,
  ),
  installedAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// רשימת תוספים מגוונת: רגיל, שם ארוך, כבוי, מוסתר, פיתוח, בלי ממשק, עם רשת.
List<InstalledPlugin> _pluginList() => [
  _plugin('a.simple', 'תוסף פשוט', description: 'תיאור קצר'),
  _plugin(
    'b.long',
    _longName,
    description: _longDescription,
    pinnedToNavRail: true,
    network: true,
    startup: true,
    permissions: ['notes.read', 'notes.write', 'network.access'],
  ),
  _plugin('c.disabled', 'תוסף כבוי', enabled: false),
  _plugin('d.hidden', 'תוסף מוסתר מהכלים', showInTools: false),
  _plugin('e.dev', 'תוסף פיתוח', sourceType: 'development'),
  _plugin('f.headless', 'תוסף רקע', headless: true),
  for (var i = 0; i < 12; i++) _plugin('g.many$i', 'תוסף מספר $i'),
];

PluginToolbarItem _toolbarItem(String id, String title) =>
    PluginToolbarItem(id: id, title: title);

// ── עטיפות ───────────────────────────────────────────────────────────────────

Widget Function(Widget app) _settingsWrap({
  SettingsState? state,
  List<InstalledPlugin>? plugins,
  Map<String, PluginUpdateInfo> updates = const {},
}) =>
    (app) => RepositoryProvider<SettingsRepository>.value(
      value: _FakeSettingsRepository(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>(
            create: (_) {
              final bloc = _MockSettingsBloc();
              whenListen(
                bloc,
                const Stream<SettingsState>.empty(),
                initialState: (state ?? SettingsState.initial()).copyWith(
                  settingsLanguageCode: SettingsLanguage.hebrew.code,
                ),
              );
              return bloc;
            },
          ),
          BlocProvider<NavigationBloc>(
            create: (_) {
              final bloc = _MockNavigationBloc();
              whenListen(
                bloc,
                const Stream<NavigationState>.empty(),
                initialState: const NavigationState(
                  currentScreen: Screen.settings,
                ),
              );
              return bloc;
            },
          ),
          BlocProvider<LibraryBloc>(
            create: (_) {
              final bloc = _MockLibraryBloc();
              whenListen(
                bloc,
                const Stream<LibraryState>.empty(),
                initialState: const LibraryState(),
              );
              return bloc;
            },
          ),
          BlocProvider<LibraryUpdateBloc>(
            create: (_) {
              final bloc = _MockLibraryUpdateBloc();
              whenListen(
                bloc,
                const Stream<LibraryUpdateState>.empty(),
                initialState: const LibraryUpdateState(),
              );
              return bloc;
            },
          ),
          BlocProvider<AttachedLibrariesBloc>(
            create: (_) {
              final bloc = _MockAttachedLibrariesBloc();
              whenListen(
                bloc,
                const Stream<AttachedLibrariesState>.empty(),
                initialState: const AttachedLibrariesState(),
              );
              return bloc;
            },
          ),
          BlocProvider<IndexingBloc>(
            create: (_) {
              final bloc = _MockIndexingBloc();
              whenListen(
                bloc,
                const Stream<IndexingState>.empty(),
                initialState: IndexingInitial(),
              );
              return bloc;
            },
          ),
          BlocProvider<CustomFoldersBloc>(
            create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
          ),
          BlocProvider<CalendarCubit>(
            create: (_) => _StubCalendarCubit(CalendarState.initial()),
          ),
          BlocProvider<PluginSystemBloc>(
            create: (_) => _FakePluginSystemBloc(plugins ?? const []),
          ),
          BlocProvider<PluginUpdatesCubit>(
            create: (_) => _FixedUpdatesCubit(updates),
          ),
          // upstream: לשונית קיצורים/מערכת מדווחת על כניסה לסיור (#5714).
          BlocProvider<TourCubit>(create: (_) => TourCubit()),
        ],
        child: app,
      ),
    );

// ── מטריצות ──────────────────────────────────────────────────────────────────

/// מצבי הקצה של השלב: הגדלת טקסט 1.5 ו-2.0 ברוחב הצר והבינוני, צפיפות מצומצמת
/// (כהה) ברוחב הצר. נוסף על חלונות השכבה הפעילה.
const List<ResponsiveViewport> _stress = [
  ResponsiveViewport(320, 640, textScale: 1.5, touch: true),
  ResponsiveViewport(320, 640, textScale: 2.0, touch: true),
  ResponsiveViewport(600, 800, textScale: 1.5),
  ResponsiveViewport(600, 800, textScale: 2.0),
  ResponsiveViewport(
    320,
    640,
    brightness: Brightness.dark,
    compact: true,
    textScale: 1.3,
  ),
];

List<ResponsiveViewport> _matrix() => [...viewportsFor(activeTier), ..._stress];

/// פותח כל כרטיס מתקפל (חץ אקורדיון סגור) עד שאין כאלה, כדי שגם התוכן שבתוכם
/// ייבדק.
Future<void> _expandAll(WidgetTester tester) async {
  final closedChevron = find.byWidgetPredicate(
    (w) => w is ExpandingChevron && !w.isExpanded,
  );
  for (var round = 0; round < 40; round++) {
    if (closedChevron.evaluate().isEmpty) return;
    try {
      await tester.ensureVisible(closedChevron.first);
      await tester.pump();
    } on Object {
      return;
    }
    await tester.tap(closedChevron.first, warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

void main() {
  late Directory temp;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    // מצב נייד: הנתיבים בתיקייה זמנית, בלי לגעת בספרייה האמיתית של המחשב.
    temp = Directory.systemTemp.createTempSync('settings_responsive');
    File(p.join(temp.path, AppPaths.portableMarkerFileName)).createSync();
    AppPaths.debugOverrideResolvedExecutable(p.join(temp.path, 'otzaria.exe'));
    AppPaths.debugOverrideDataRootPath(temp.path);
    TantivyDataProvider.instance = TantivyDataProvider.forTesting(
      Future.value(_OpenEngine()),
    );
    // פתיחת מסד התוספים מחוץ ל-FakeAsync של testWidgets, שבו ה-IO הראשון נתקע.
    await PluginSystemDatabase.instance.close();
    await PluginRegistryRepository().getPermission('warmup', 'warmup');
  });

  tearDownAll(() async {
    await PluginSystemDatabase.instance.close();
    AppPaths.debugOverrideResolvedExecutable(null);
    AppPaths.debugOverrideDataRootPath(null);
    temp.deleteSync(recursive: true);
  });

  for (final tab in SettingsTab.values) {
    testResponsive(
      'לשונית הגדרות: ${tab.name}, כל הכרטיסים פתוחים',
      scaffold: false,
      viewports: _matrix(),
      wrapApp: _settingsWrap(plugins: _pluginList()),
      build: (_) => MySettingsScreen(
        controller: SettingsScreenController()..openTab(tab),
      ),
      act: (tester, run) => _expandAll(tester),
    );
  }

  // ── ניהול תוספים: מצב בחירה (סרגל פעולות מחוץ לאזור הגלילה) ───────────────

  testResponsive(
    'ניהול תוספים: מצב בחירה, כל הפעולות נגישות',
    scaffold: false,
    viewports: [
      ..._matrix(),
      const ResponsiveViewport(320, 400, textScale: 2.0, touch: true),
    ],
    wrapApp: _settingsWrap(plugins: _pluginList()),
    build: (_) => MySettingsScreen(
      controller: SettingsScreenController()..openTab(SettingsTab.tools),
    ),
    act: (tester, run) async {
      final enter = find.text('בחירה');
      await tester.ensureVisible(enter);
      await tester.pump();
      await tester.tap(enter);
      await tester.pumpAndSettle();
      final all = find.text('בחר הכל');
      expectVisible(tester, run, all, name: 'בחר הכל');
      if (all.evaluate().isNotEmpty) {
        await tester.tap(all);
        await tester.pumpAndSettle();
      }
    },
    verify: (tester, run) async {
      expectVisible(tester, run, find.byTooltip('ביטול'), name: 'יציאה מבחירה');
      // הסרגל מחוץ לאזור הגלילה: כל פעולה חייבת להיות גלויה מיד.
      await expectReachable(tester, run, find.text('מחק'), name: 'מחק');
      // יש תוסף כבוי ברשימה, ולכן אחרי "בחר הכל" הפעולה היא "הפעל".
      await expectReachable(tester, run, find.text('הפעל'), name: 'הפעל');
    },
  );

  // ── חלוניות התוספים ──────────────────────────────────────────────────────────

  Widget opener(Future<Object?> Function(BuildContext context) open) => Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text('פתח'),
      ),
    ),
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
  }

  ResponsiveAct dialogChecks(List<String> buttons) => (tester, run) async {
    expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
    for (final label in buttons) {
      expectVisible(tester, run, find.text(label), name: 'כפתור "$label"');
    }
  };

  PluginManifest installManifest({
    String name = 'תוסף עם הרשאות רבות',
    int permissionCount = 8,
    bool longDescription = false,
  }) {
    const permissions = [
      'notes.read',
      'notes.write',
      'bookmarks.read',
      'bookmarks.write',
      'network.access',
      'app.run_on_startup',
      'clipboard.read',
      'workspace.read',
      'workspace.manage',
      'tools.read',
    ];
    return PluginManifest.fromJson({
      'id': 'responsive.example',
      'name': name,
      'version': '2.0.0',
      'entrypoint': 'index.html',
      'author': 'צוות הפיתוח של התוסף עם שם ארוך מאוד',
      'description': longDescription
          ? List.filled(12, _longDescription).join('\n')
          : 'כלי עזר לעבודה עם התוכנה.',
      'permissions': permissions.take(permissionCount).toList(),
      'network': {'enabled': true},
    });
  }

  for (final variant
      in <({String name, PluginManifest manifest, String? previous})>[
        (
          name: 'התקנה ראשונה, הרשאות רבות',
          manifest: installManifest(),
          previous: null,
        ),
        (
          name: 'עדכון, שם ותיאור ארוכים',
          manifest: installManifest(
            name: _longName,
            permissionCount: 4,
            longDescription: true,
          ),
          previous: '1.0.0',
        ),
      ]) {
    testResponsive(
      'PluginInstallScreen: ${variant.name}',
      viewports: _matrix(),
      build: (_) => opener(
        (context) => showDialog<void>(
          context: context,
          builder: (_) => PluginInstallScreen(
            manifest: variant.manifest,
            tempDirPath: '',
            previousVersion: variant.previous,
            onConfirm: (_) {},
            onCancel: () {},
          ),
        ),
      ),
      act: (tester, run) => openDialog(tester),
      verify: (tester, run) async {
        expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
        expectVisible(tester, run, find.text('ביטול'), name: 'ביטול');
        expectVisible(
          tester,
          run,
          find.text(variant.previous == null ? 'התקן' : 'עדכן'),
          name: 'אישור',
        );
      },
    );
  }

  for (final plugin in [
    _plugin(
      'dev.long',
      _longName,
      description: _longDescription,
      sourceType: 'development',
      permissions: ['notes.read', 'notes.write', 'network.access'],
    ),
    _plugin('plain', 'תוסף פשוט'),
  ]) {
    testResponsive(
      'PluginSettingsScreen: ${plugin.pluginId}',
      wrapApp: _settingsWrap(plugins: [plugin]),
      viewports: _matrix(),
      build: (_) =>
          opener((context) => showPluginSettingsDialog(context, plugin)),
      act: (tester, run) async {
        await tester.tap(find.text('פתח'));
        // קריאת ההרשאות היא IO אמיתי של מסד התוספים.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        );
        await tester.pumpAndSettle();
      },
      verify: (tester, run) async {
        expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      },
    );
  }

  testResponsive(
    'PluginConfirmationDialog: תוכן ארוך',
    viewports: _matrix(),
    build: (_) => opener((context) {
      final dialog = PluginConfirmationDialog();
      return dialog.show(
        context: context,
        title: _longName,
        content: List.filled(6, _longDescription).join('\n'),
      );
    }),
    act: (tester, run) => openDialog(tester),
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
    },
  );

  // ── דיאלוגי הגדרות ───────────────────────────────────────────────────────────

  testResponsive(
    'בורר צבע הבסיס: כל הצבעים נגישים',
    viewports: _matrix(),
    build: (_) => Center(
      child: ColorPickerTile(
        currentColor: AppSeedColors.white,
        defaultColor: AppSeedColors.defaultLight,
        onChanged: (_) {},
      ),
    ),
    act: (tester, run) async {
      await tester.tap(find.text('שינוי צבע'));
      await tester.pumpAndSettle();
    },
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      expectVisible(tester, run, find.text('סגור'), name: 'סגור');
      for (final option in AppSeedColors.options) {
        await expectReachable(
          tester,
          run,
          find.byTooltip(option.name),
          name: 'עיגול ${option.name}',
        );
      }
    },
  );

  testResponsive(
    'SaferModeSetPasswordDialog: הסרה כשמצב סייפר פעיל',
    viewports: _matrix(),
    build: (_) => opener(
      (context) => showDialog<bool>(
        context: context,
        builder: (_) => SaferModeSetPasswordDialog(
          onSetPassword: (_) async {},
          onClearPassword: () async {},
          isSaferModeEnabled: true,
        ),
      ),
    ),
    act: (tester, run) => openDialog(tester),
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      expectVisible(tester, run, find.byType(TextField).first, name: 'שדה');
    },
  );

  testResponsive(
    'SaferModePasswordDialog: כותרת ארוכה',
    viewports: _matrix(),
    build: (_) => opener(
      (context) => showDialog<bool>(
        context: context,
        builder: (_) => SaferModePasswordDialog(
          onVerify: (_) async => true,
          title: _longName,
          hint: _longDescription,
        ),
      ),
    ),
    act: (tester, run) => openDialog(tester),
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      expectVisible(tester, run, find.byType(TextField).first, name: 'שדה');
    },
  );

  testResponsive(
    'showOfflineDonationDialog',
    viewports: _matrix(),
    build: (_) => opener((context) => showOfflineDonationDialog(context)),
    act: (tester, run) => openDialog(tester),
    verify: dialogChecks(['סגור']),
  );

  testResponsive(
    'showDynamicShortcutDialog',
    viewports: _matrix(),
    build: (_) => opener((context) => showDynamicShortcutDialog(context)),
    act: (tester, run) => openDialog(tester),
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
    },
  );

  testResponsive(
    'showBooksListDialog: ספרים עם שמות ארוכים',
    viewports: _matrix(),
    build: (_) => opener(
      (context) => showBooksListDialog(
        context: context,
        books: [
          for (var i = 0; i < 40; i++)
            TextBook(id: i, title: 'ספר $i $_longName'),
        ],
      ),
    ),
    act: (tester, run) => openDialog(tester),
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      expectVisible(tester, run, find.byType(TextField).first, name: 'חיפוש');
    },
  );

  // ── קטלוג חיצוני: דיאלוג "מסד הקטלוגים חסר" ──────────────────────────────────

  for (final offline in [true, false]) {
    testResponsive(
      'קטלוג חיצוני: מסד חסר, ${offline ? 'מנותק' : 'מחובר'}',
      viewports: _matrix(),
      wrapApp: _settingsWrap(
        state: SettingsState.initial().copyWith(isOfflineMode: offline),
      ),
      build: (_) => opener(
        (context) =>
            ExternalCatalogSettingsHelper.ensureCatalogDatabaseAvailable(
              context,
            ),
      ),
      act: (tester, run) async {
        await tester.tap(find.text('פתח'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      },
      verify: dialogChecks([offline ? 'הבנתי' : 'הורד']),
    );
  }

  // ── סרגל פקדי תוספים בקורא: כל פקד נשאר זמין, ישירות או בתפריט "עוד פעולות" ──

  testResponsive(
    'סרגל פקדי תוספים בקורא: כל פקד גלוי או בתפריט ⋮',
    viewports: _matrix(),
    build: (_) {
      final plugins = buildPluginToolbarActions(
        records: [
          for (var i = 0; i < 6; i++)
            ('responsive.plugin$i', _toolbarItem('i$i', 'פעולת תוסף $i')),
          (
            'responsive.menu',
            const PluginToolbarItem(
              id: 'menu',
              type: 'menu',
              title: 'תפריט תוסף עם שם ארוך מאוד',
              children: [
                PluginToolbarItem(id: 'c1', title: 'ילד ראשון'),
                PluginToolbarItem(id: 'c2', title: 'ילד שני'),
              ],
            ),
          ),
        ],
        context: 'reader-text',
        compact: false,
        locationPayload: () async => const {},
      );
      ActionButtonData builtIn(String tooltip, ToolbarActionId id) =>
          ActionButtonData.simple(
            icon: FluentIcons.zoom_in_24_regular,
            tooltip: tooltip,
            onPressed: () {},
            compact: false,
            actionId: id,
          );
      return Align(
        alignment: Alignment.topCenter,
        child: ResponsiveActionBar(
          actions: [
            builtIn('הגדלה', ToolbarActionId.zoomIn),
            builtIn('הקטנה', ToolbarActionId.zoomOut),
            builtIn('חיפוש בספר', ToolbarActionId.search),
            ...plugins,
          ],
          alwaysInMenu: const [],
        ),
      );
    },
    verify: (tester, run) async {
      const titles = [
        'הגדלה',
        'הקטנה',
        'חיפוש בספר',
        'פעולת תוסף 0',
        'פעולת תוסף 1',
        'פעולת תוסף 2',
        'פעולת תוסף 3',
        'פעולת תוסף 4',
        'פעולת תוסף 5',
        'תפריט תוסף עם שם ארוך מאוד',
      ];
      final hidden = [
        for (final title in titles)
          if (find.byTooltip(title).hitTestable().evaluate().isEmpty) title,
      ];
      if (hidden.isEmpty) return;
      final overflow = find.byTooltip('עוד פעולות');
      expectVisible(tester, run, overflow, name: 'כפתור "עוד פעולות"');
      if (overflow.evaluate().isEmpty) return;
      await tester.tap(overflow);
      await tester.pumpAndSettle();
      for (final title in hidden) {
        await expectReachable(
          tester,
          run,
          find.text(title),
          name: 'פקד "$title" בתפריט ⋮',
        );
      }
    },
  );

  // ── גרירת שורות תוספים לא מתחרה בגלילה באצבע ─────────────────────────────────

  testWidgets(
    'ניהול תוספים במגע: גלילה אנכית באצבע מעל שורה גוללת ולא גוררת',
    (tester) async {
      final run = await pumpResponsive(
        tester,
        const ResponsiveViewport(390, 700, touch: true),
        (_) => MySettingsScreen(
          controller: SettingsScreenController()..openTab(SettingsTab.tools),
        ),
        wrapApp: _settingsWrap(plugins: _pluginList()),
        scaffold: false,
      );
      run.release();
      final scrollable = find
          .descendant(
            of: find.byType(SettingsTabScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final row = find.text('תוסף פשוט');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final before = position.pixels;

      await tester.drag(row, const Offset(0, -150));
      await tester.pumpAndSettle();

      expect(
        position.pixels,
        greaterThan(before + 50),
        reason: 'גרירה מיידית של השורה תפסה את התנועה במקום הגלילה',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  // ── נתיבים ארוכים בשילוב עברית ואנגלית (RTL) ─────────────────────────────────

  for (final tab in [SettingsTab.library, SettingsTab.system]) {
    testResponsive(
      'לשונית הגדרות ${tab.name}: נתיבים ארוכים בעברית ובאנגלית',
      scaffold: false,
      viewports: _matrix(),
      wrapApp: _settingsWrap(
        plugins: const [],
        state: SettingsState.initial().copyWith(
          libraryPath:
              r'C:\Users\משתמש\Documents\Otzaria Library With A Very Long Folder Name\ספרים וקבצים\Sub Folder',
          hebrewBooksPath:
              r'D:\HebrewBooks\הספרים שלי\VeryLongEnglishFolderNameWithoutAnySpacesAtAll',
          backupPath:
              r'E:\Backups\גיבויים של אוצריא\Otzaria Backups 2026\VeryLongEnglishFolderName',
        ),
      ),
      build: (_) => MySettingsScreen(
        controller: SettingsScreenController()..openTab(tab),
      ),
      act: (tester, run) => _expandAll(tester),
    );
  }
}
