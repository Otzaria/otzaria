import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/tools/view/tools_launcher_panel.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockPluginSystemBloc
    extends MockBloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {}

class _MockTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {}

ToolCatalogEntry _entry(
  String toolId,
  String label, {
  IconData? icon,
  String? imageIcon,
}) => ToolCatalogEntry(
  toolId: toolId,
  label: label,
  order: 10,
  icon: icon ?? FluentIcons.calendar_24_regular,
  imageIcon: imageIcon,
);

ToolCatalogEntry _pluginEntry(
  String pluginId,
  String label, {
  String? name,
  String sourceType = 'packaged',
  bool allowOrderBeforeBuiltIns = false,
}) => ToolCatalogEntry(
  toolId: pluginId,
  label: label,
  order: 900,
  icon: FluentIcons.puzzle_piece_24_regular,
  plugin: InstalledPlugin(
    pluginId: pluginId,
    name: name ?? label,
    version: '1.0.0',
    installPath: '/plugins/$pluginId',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: false,
    pinnedToNavRail: false,
    showInTools: true,
    allowOrderBeforeBuiltInsGranted: allowOrderBeforeBuiltIns,
    networkAccessGranted: false,
    sourceType: sourceType,
    devRootPath: sourceType == 'development' ? '/dev/$pluginId' : null,
    manifest: PluginManifest(
      schemaVersion: 1,
      id: pluginId,
      name: name ?? label,
      version: '1.0.0',
      description: 'test',
      author: 'tester',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '1.0.0',
      sdkVersion: '1.x',
      permissions: const [],
      networkEnabled: false,
      networkAllowlist: const [],
      toolTabTitle: label,
      toolTabOrder: 900,
      allowOrderBeforeBuiltIns: allowOrderBeforeBuiltIns,
      defaultPinned: false,
      publishedDataTypes: const [],
    ),
    installedAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  ),
);

/// עוטף קובייה בודדת בקופסה מרובעת, כדי שהבדיקות ימדדו את אותן אילוצים
/// שהרשת נותנת (childAspectRatio: 1.0).
Widget _tileHost(ToolTile tile, {double size = 100}) => MaterialApp(
  theme: ThemeData(colorSchemeSeed: Colors.blue),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: Center(
        child: SizedBox(width: size, height: size, child: tile),
      ),
    ),
  ),
);

/// רוחב התוכן בפאנל שבברירת מחדל: `ContextOverlayPanel` ברוחב 440, פחות
/// `contentPadding` של 16 מכל צד.
const double _kDefaultPanelContentWidth = 408;

Widget _launcherHost({
  required SettingsBloc settingsBloc,
  required PluginSystemBloc pluginSystemBloc,
  required TabsBloc tabsBloc,
  required ValueChanged<ToolCatalogEntry> onToolSelected,
  double width = 520,
  double height = 600,
}) => MaterialApp(
  theme: ThemeData(colorSchemeSeed: Colors.blue),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<PluginSystemBloc>.value(value: pluginSystemBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
          ],
          child: ToolsLauncherPanel(
            onToolSelected: onToolSelected,
            onClose: () {},
            showDevTools: false,
          ),
        ),
      ),
    ),
  ),
);

/// מציאת כפתור ⋯ של קובייה לפי התווית שכתובה בה.
Finder _menuButtonOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(ToolTile)),
  matching: find.byIcon(FluentIcons.more_vertical_24_regular),
);

bool _isCardSelected(WidgetTester tester, String label) => tester
    .widget<AppCard>(
      find.ancestor(of: find.text(label), matching: find.byType(AppCard)).first,
    )
    .selected;

int _selectedCardCount(WidgetTester tester) => tester
    .widgetList<AppCard>(find.byType(AppCard))
    .where((card) => card.selected)
    .length;

/// מריץ גוף בדיקה כפלטפורמת שולחן עבודה. האיפוס חייב לקרות בתוך גוף הבדיקה,
/// כי flutter_test מוודא שמשתני ה-debug נוקו לפני שה-tearDown רץ.
Future<void> _asDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// האם פריט התפריט הפתוח פעיל (פעולת הזזה בקצה הקבוצה מעומעמת).
bool _menuItemEnabled(WidgetTester tester, String label) => tester
    .widget<PopupMenuItem<VoidCallback>>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(PopupMenuItem<VoidCallback>),
      ),
    )
    .enabled;

void main() {
  testWidgets('פתיחת משגר הכלים בתוך overlay אינה זורקת ParentDataWidget', (
    tester,
  ) async {
    final key = GlobalKey<_ToolsLauncherOverlayHarnessState>();
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final pluginSystemBloc = _TestPluginSystemBloc(PluginSystemInitial());
    final tabsBloc = _TestTabsBloc(TabsState.initial());
    addTearDown(() async {
      await settingsBloc.close();
      await pluginSystemBloc.close();
      await tabsBloc.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<PluginSystemBloc>.value(value: pluginSystemBloc),
          BlocProvider<TabsBloc>.value(value: tabsBloc),
        ],
        child: MaterialApp(
          home: Scaffold(body: _ToolsLauncherOverlayHarness(key: key)),
        ),
      ),
    );

    key.currentState!.open();
    await tester.pump();
    await tester.pump();

    expect(find.text('כלים ותוספים'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('שדה החיפוש בפאנל הכלים מקבל פוקוס גם כשהמסך כבר ממוקד', (
    tester,
  ) async {
    final key = GlobalKey<_ToolsLauncherOverlayHarnessState>();
    final backgroundFocusNode = FocusNode();
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final pluginSystemBloc = _TestPluginSystemBloc(PluginSystemInitial());
    final tabsBloc = _TestTabsBloc(TabsState.initial());
    addTearDown(() async {
      backgroundFocusNode.dispose();
      await settingsBloc.close();
      await pluginSystemBloc.close();
      await tabsBloc.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<PluginSystemBloc>.value(value: pluginSystemBloc),
          BlocProvider<TabsBloc>.value(value: tabsBloc),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: _ToolsLauncherOverlayHarness(
              key: key,
              backgroundFocusNode: backgroundFocusNode,
            ),
          ),
        ),
      ),
    );

    backgroundFocusNode.requestFocus();
    await tester.pump();
    expect(backgroundFocusNode.hasFocus, isTrue);

    key.currentState!.open();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final searchField = tester.widget<TextField>(
      find.descendant(
        of: find.byType(ToolsLauncherPanel),
        matching: find.byType(TextField),
      ),
    );
    expect(searchField.focusNode!.hasFocus, isTrue);
    expect(backgroundFocusNode.hasFocus, isFalse);
  });

  testWidgets('חצים ו-Enter פותחים את הקובייה המסומנת משדה החיפוש', (
    tester,
  ) async {
    final settingsBloc = _MockSettingsBloc();
    final pluginSystemBloc = _MockPluginSystemBloc();
    final tabsBloc = _MockTabsBloc();
    ToolCatalogEntry? selected;

    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    whenListen(
      pluginSystemBloc,
      const Stream<PluginSystemState>.empty(),
      initialState: PluginSystemInitial(),
    );
    whenListen(
      tabsBloc,
      const Stream<TabsState>.empty(),
      initialState: TabsState.initial(),
    );

    await tester.pumpWidget(
      _launcherHost(
        settingsBloc: settingsBloc,
        pluginSystemBloc: pluginSystemBloc,
        tabsBloc: tabsBloc,
        onToolSelected: (entry) => selected = entry,
      ),
    );
    await tester.pump();

    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'ה');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(selected?.toolId, 'builtin.notes');
  });

  group('normalizeToolSearchText', () {
    test('מסיר ניקוד, גרשיים ומקפים', () {
      expect(normalizeToolSearchText('רָאשֵׁי תֵּיבוֹת'), 'ראשי תיבות');
      expect(normalizeToolSearchText('ארמי-עברי'), 'ארמיעברי');
      expect(normalizeToolSearchText('ר"ת'), 'רת');
    });

    test('מכווץ רווחים ומוריד רישיות', () {
      expect(normalizeToolSearchText('  Foo   BAR '), 'foo bar');
    });

    test('מסיר גרש עברי ומקפים ארוכים', () {
      expect(normalizeToolSearchText('צ׳ק—דש–שתיים'), 'צקדששתיים');
    });

    test('מחרוזת רווחים בלבד הופכת לריקה', () {
      expect(normalizeToolSearchText('    '), '');
    });

    test('ספרות ותווים לטיניים נשמרים', () {
      expect(normalizeToolSearchText('Gematria 42'), 'gematria 42');
    });
  });

  group('filterToolEntries', () {
    final entries = [
      _entry('builtin.calendar', 'לוח שנה'),
      _entry('builtin.gematria', 'גימטריה'),
      _entry('builtin.acronyms_dictionary', 'ראשי תיבות'),
    ];

    test('חיפוש ריק מחזיר הכל', () {
      expect(filterToolEntries(entries, '   ').length, 3);
    });

    test('התאמת תת-מחרוזת בתווית', () {
      expect(filterToolEntries(entries, 'גימ').map((e) => e.toolId), [
        'builtin.gematria',
      ]);
    });

    test('חיפוש עם ניקוד/מקף עדיין מתאים', () {
      expect(filterToolEntries(entries, 'לוּחַ').map((e) => e.toolId), [
        'builtin.calendar',
      ]);
    });

    test('ללא התאמה — רשימה ריקה', () {
      expect(filterToolEntries(entries, 'זזזז'), isEmpty);
    });

    // שם התוסף במניפסט יכול להיות שונה מכותרת הלשונית שלו.
    test('מתאים גם לפי שם התוסף ולא רק לפי התווית', () {
      final withPlugin = [_pluginEntry('com.example.x', 'מפה', name: 'Atlas')];
      expect(filterToolEntries(withPlugin, 'atlas').length, 1);
      expect(filterToolEntries(withPlugin, 'מפה').length, 1);
    });

    test('החיפוש אינו תלוי רישיות', () {
      final withPlugin = [_pluginEntry('com.example.x', 'Map', name: 'Atlas')];
      expect(filterToolEntries(withPlugin, 'MAP').length, 1);
    });

    test('שומר על סדר הרשומות המקורי', () {
      final result = filterToolEntries([
        _entry('a', 'אלף'),
        _entry('b', 'שני'),
        _entry('c', 'שלישי'),
      ], 'ש');
      expect(result.map((e) => e.toolId), ['b', 'c']);
    });

    test('רשימת מקור ריקה מחזירה ריק', () {
      expect(filterToolEntries(const [], 'משהו'), isEmpty);
    });
  });

  group('groupToolEntries', () {
    test('שומר את סדר הקטלוג ומחלק רק במעבר בין סוגי רשומות', () {
      final groups = groupToolEntries([
        _pluginEntry(
          'com.example.leading',
          'תוסף מקדים',
          allowOrderBeforeBuiltIns: true,
        ),
        _entry('builtin.calendar', 'לוח שנה'),
        _entry('builtin.gematria', 'גימטריה'),
        _pluginEntry('com.example.x', 'תוסף'),
      ]);
      expect(groups.map((g) => g.label), [
        kPluginsGroupLabel,
        kBuiltInToolsGroupLabel,
        kPluginsGroupLabel,
      ]);
      expect(groups[1].entries.map((e) => e.toolId), [
        'builtin.calendar',
        'builtin.gematria',
      ]);
      expect(groups.first.entries.single.toolId, 'com.example.leading');
      expect(groups.last.entries.single.toolId, 'com.example.x');
    });

    test('מקטע ריק אינו מוחזר', () {
      expect(
        groupToolEntries([_entry('builtin.calendar', 'לוח שנה')]).single.label,
        kBuiltInToolsGroupLabel,
      );
      expect(
        groupToolEntries([_pluginEntry('com.example.x', 'תוסף')]).single.label,
        kPluginsGroupLabel,
      );
    });

    test('הסדר בתוך כל מקטע נשמר כפי שהתקבל', () {
      final groups = groupToolEntries([
        _pluginEntry('p.b', 'ב'),
        _entry('builtin.z', 'ז'),
        _entry('builtin.a', 'א'),
        _pluginEntry('p.a', 'א'),
      ]);
      expect(groups[1].entries.map((e) => e.toolId), [
        'builtin.z',
        'builtin.a',
      ]);
      expect(groups.first.entries.single.toolId, 'p.b');
      expect(groups.last.entries.single.toolId, 'p.a');
    });

    test('רשימה ריקה — אין קבוצות', () {
      expect(groupToolEntries(const []), isEmpty);
    });

    // בלי הפיצול הזה, קבוצה מאוחדת הייתה מייצרת פעולות הזזה פעילות בין תוספים
    // שאסור לסדר ביניהם — ולכן פעולה שאינה עושה דבר.
    test('שתי קבוצות תוספים עוקבות אינן מתמזגות', () {
      final groups = groupToolEntries([
        _pluginEntry(
          'com.example.leading',
          'תוסף מקדים',
          allowOrderBeforeBuiltIns: true,
        ),
        _pluginEntry('com.example.regular', 'תוסף רגיל'),
      ]);
      expect(groups, hasLength(2));
      expect(groups.map((g) => g.label), [
        kPluginsGroupLabel,
        kPluginsGroupLabel,
      ]);
      expect(groups.first.entries.single.toolId, 'com.example.leading');
    });
  });

  // ניווט המקלדת ממופה לאינדקס ברשימה השטוחה, ולכן היא חייבת להיות בסדר
  // הרינדור — כולל תוסף שהמיון הקדים לכלים המובנים.
  group('orderedToolEntries', () {
    test('מחזיר את סדר הרינדור, כולל תוסף שמופיע לפני מובנים', () {
      final ordered = orderedToolEntries([
        _pluginEntry('com.example.first', 'תוסף מקדים'),
        _entry('builtin.calendar', 'לוח שנה'),
        _pluginEntry('com.example.x', 'תוסף'),
      ]);
      expect(ordered.map((e) => e.toolId), [
        'com.example.first',
        'builtin.calendar',
        'com.example.x',
      ]);
    });

    test('תוסף מורשה מוצג לפני מובנים וניווט המקלדת שומר את סדר הרינדור', () {
      final leadingPlugin = _pluginEntry(
        'com.example.leading',
        'תוסף מקדים',
        allowOrderBeforeBuiltIns: true,
      ).plugin!;
      final regularPlugin = _pluginEntry(
        'com.example.regular',
        'תוסף רגיל',
      ).plugin!;
      final catalog = buildToolCatalog(
        hiddenBuiltInToolIds: const {},
        isOfflineMode: false,
        pluginState: PluginSystemLoaded([leadingPlugin, regularPlugin]),
      );
      final rendered = [
        for (final group in groupToolEntries(catalog)) ...group.entries,
      ];

      expect(catalog.first.toolId, leadingPlugin.pluginId);
      expect(groupToolEntries(catalog).first.label, kPluginsGroupLabel);
      expect(
        rendered.map((entry) => entry.toolId),
        catalog.map((entry) => entry.toolId),
      );
      expect(
        orderedToolEntries(catalog).map((entry) => entry.toolId),
        rendered.map((entry) => entry.toolId),
      );
    });

    test('שומר על אורך הרשימה', () {
      final input = [
        _entry('a', 'א'),
        _pluginEntry('p', 'תוסף'),
        _entry('b', 'ב'),
      ];
      expect(orderedToolEntries(input).length, input.length);
    });

    test('רשימה ריקה', () {
      expect(orderedToolEntries(const []), isEmpty);
    });
  });

  group('toolGridColumns', () {
    test('רוחב צר נעצר על מינימום 2 עמודות', () {
      expect(toolGridColumns(0), 2);
      expect(toolGridColumns(kToolTileTargetWidth), 2);
    });

    test('גדל עם הרוחב', () {
      expect(toolGridColumns(kToolTileTargetWidth * 3), 3);
      expect(toolGridColumns(kToolTileTargetWidth * 4), 4);
    });

    test('רוחב גדול נעצר על מקסימום 5 עמודות', () {
      expect(toolGridColumns(kToolTileTargetWidth * 20), 5);
    });

    test('רוחב חלקי מעגל כלפי מטה', () {
      expect(toolGridColumns(kToolTileTargetWidth * 3.9), 3);
    });
  });

  group('nextHighlightIndex', () {
    test('זז בתוך הטווח', () {
      expect(nextHighlightIndex(current: 0, delta: 1, total: 5), 1);
      expect(nextHighlightIndex(current: 3, delta: -2, total: 5), 1);
    });

    test('נעצר בקצה העליון ואינו גולש למחזוריות', () {
      expect(nextHighlightIndex(current: 4, delta: 1, total: 5), 4);
      expect(nextHighlightIndex(current: 4, delta: 3, total: 5), 4);
    });

    test('נעצר באפס', () {
      expect(nextHighlightIndex(current: 0, delta: -1, total: 5), 0);
      expect(nextHighlightIndex(current: 1, delta: -9, total: 5), 0);
    });

    test('רשימה ריקה מחזירה 0 ואינה זורקת', () {
      expect(nextHighlightIndex(current: 3, delta: 1, total: 0), 0);
    });

    test('פריט יחיד נשאר על 0', () {
      expect(nextHighlightIndex(current: 0, delta: 1, total: 1), 0);
    });

    // ממצב "אין סימון" כל חץ מסמן את הראשונה; בלי זה חץ למטה היה מדלג שורה
    // שלמה ומסמן את הקובייה החמישית.
    test('ממצב ללא סימון כל חץ מסמן את הקובייה הראשונה', () {
      expect(nextHighlightIndex(current: -1, delta: 1, total: 7), 0);
      expect(nextHighlightIndex(current: -1, delta: 5, total: 7), 0);
      expect(nextHighlightIndex(current: -1, delta: -5, total: 7), 0);
    });
  });

  group('ToolTile', () {
    ToolTile buildTile({
      ToolCatalogEntry? entry,
      bool isOpen = false,
      bool isHighlighted = false,
      VoidCallback? onTap,
      List<ToolTileAction> actions = const [],
      int movePulse = 0,
    }) => ToolTile(
      entry: entry ?? _entry('builtin.calendar', 'לוח שנה'),
      isOpen: isOpen,
      isHighlighted: isHighlighted,
      onTap: onTap ?? () {},
      actions: actions,
      movePulse: movePulse,
    );

    testWidgets('מציג את תווית הכלי', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      expect(find.text('לוח שנה'), findsOneWidget);
    });

    // אותו כרטיס כמו בקוביות הספרייה — צבע הכרטיס שבערכת הנושא, בלי מסגרת.
    testWidgets('הקובייה על צבע הכרטיס של הספרייה', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      expect(find.byType(AppCard), findsOneWidget);

      final context = tester.element(find.byType(ToolTile));
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, AppSurfaces.card(context));
      expect(material.shape, isNull);
    });

    // סדר גודל של סמל תוכנה: בקובייה רגילה האייקון מגיע לגודלו המרבי.
    testWidgets('האייקון מגיע לגודל המרבי בקובייה רגילה', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));

      final icon = tester.widget<Icon>(
        find.byIcon(FluentIcons.calendar_24_regular),
      );
      expect(icon.size, ToolTile.iconSizeFor(100 - AppTokens.spaceXS * 2));
      expect(icon.size, ToolTile.maxIconSize);
    });

    // בפאנל מצומצם האייקון מתכווץ, אחרת שתי שורות התווית נחתכות.
    testWidgets('קובייה קטנה מקבלת אייקון קטן ללא חריגת פריסה', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile(), size: 70));
      expect(tester.takeException(), isNull);

      final icon = tester.widget<Icon>(
        find.byIcon(FluentIcons.calendar_24_regular),
      );
      expect(icon.size, lessThan(ToolTile.maxIconSize));
      expect(icon.size, greaterThanOrEqualTo(ToolTile.minIconSize));
    });

    // התווית קטנה מברירת המחדל של bodySmall, כדי לפנות מקום לאייקון.
    testWidgets('תווית הקובייה בגודל 11', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      final label = tester.widget<Text>(find.text('לוח שנה'));
      expect(label.style?.fontSize, ToolTile.labelFontSize);
    });

    // האייקון עומד על רקע הכרטיס עצמו — בלי מעטפת מרובעת סביבו.
    testWidgets('האייקון בצבע primary ובלי מעטפת מרובעת', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      final context = tester.element(find.byType(ToolTile));
      final cs = Theme.of(context).colorScheme;

      final icon = tester.widget<Icon>(
        find.byIcon(FluentIcons.calendar_24_regular),
      );
      expect(icon.color, cs.primary);
      expect(
        find.ancestor(
          of: find.byIcon(FluentIcons.calendar_24_regular),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
    });

    testWidgets('האייקון והטקסט ממורכזים אופקית בקובייה', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));

      final tileCenter = tester.getCenter(find.byType(ToolTile));
      final iconCenter = tester.getCenter(
        find.byIcon(FluentIcons.calendar_24_regular),
      );
      final textCenter = tester.getCenter(find.text('לוח שנה'));

      expect(iconCenter.dx, moreOrLessEquals(tileCenter.dx, epsilon: 0.5));
      expect(textCenter.dx, moreOrLessEquals(tileCenter.dx, epsilon: 0.5));
    });

    // גוש האייקון+טקסט ממורכז אנכית כיחידה אחת — לא כל רכיב לחוד.
    testWidgets('גוש התוכן ממורכז אנכית', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));

      final tileCenter = tester.getCenter(find.byType(ToolTile));
      final iconBoxRect = tester.getRect(
        find.byIcon(FluentIcons.calendar_24_regular),
      );
      final textRect = tester.getRect(find.text('לוח שנה'));

      final blockCenter = (iconBoxRect.top + textRect.bottom) / 2;
      expect(iconBoxRect.top, lessThan(tileCenter.dy));
      expect(textRect.bottom, greaterThan(tileCenter.dy));
      expect(blockCenter, moreOrLessEquals(tileCenter.dy, epsilon: 1));
    });

    testWidgets('תווית ארוכה אינה גולשת מהקובייה', (tester) async {
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            entry: _entry('builtin.x', 'כותרת ארוכה מאוד של כלי עם הרבה מילים'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('imageIcon מוצג כ-ImageIcon במקום Icon', (tester) async {
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            entry: _entry(
              'builtin.shamor_zachor',
              'שמור וזכור',
              imageIcon: 'assets/logos/otzar.ico',
            ),
          ),
        ),
      );
      expect(find.byType(ImageIcon), findsOneWidget);
      final imageIcon = tester.widget<ImageIcon>(find.byType(ImageIcon));
      expect(imageIcon.size, ToolTile.iconSizeFor(100 - AppTokens.spaceXS * 2));
    });

    testWidgets('לחיצה מפעילה את onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_tileHost(buildTile(onTap: () => taps++)));
      await tester.tap(find.byType(ToolTile));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('סימן "פתוח" מוצג רק כשהכלי פתוח', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      expect(find.byIcon(FluentIcons.checkmark_circle_16_filled), findsNothing);

      await tester.pumpWidget(_tileHost(buildTile(isOpen: true)));
      expect(
        find.byIcon(FluentIcons.checkmark_circle_16_filled),
        findsOneWidget,
      );
    });

    testWidgets('תג DEV מוצג רק לתוסף בפיתוח', (tester) async {
      await tester.pumpWidget(
        _tileHost(buildTile(entry: _pluginEntry('com.example.x', 'תוסף'))),
      );
      expect(find.text('DEV'), findsNothing);

      await tester.pumpWidget(
        _tileHost(
          buildTile(
            entry: _pluginEntry(
              'com.example.dev',
              'תוסף פיתוח',
              sourceType: 'development',
            ),
          ),
        ),
      );
      expect(find.text('DEV'), findsOneWidget);
    });

    testWidgets('תוסף localhost נחשב גם הוא לפיתוח', (tester) async {
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            entry: _pluginEntry(
              'com.example.local',
              'תוסף מקומי',
              sourceType: 'localhost_dev',
            ),
          ),
        ),
      );
      expect(find.text('DEV'), findsOneWidget);
    });

    // התווית כתובה בקובייה — טולטיפ ריחוף עליה היה כפילות מציקה.
    testWidgets('אין טולטיפ ריחוף על הקובייה', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      expect(find.byType(Tooltip), findsNothing);

      await tester.pumpWidget(
        _tileHost(
          buildTile(entry: _pluginEntry('com.example.x', 'מפה', name: 'Atlas')),
        ),
      );
      expect(find.byType(Tooltip), findsNothing);
    });

    // הטולטיפ היחיד שנשאר בקובייה הוא של כפתור הפעולות, כמו בספרייה.
    testWidgets('הטולטיפ היחיד הוא של כפתור הפעולות', (tester) async {
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            actions: [
              ToolTileAction(
                icon: FluentIcons.eye_off_24_regular,
                label: 'הסתר מהממשק',
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'אפשרויות נוספות',
      );
    });

    testWidgets('סימון מקלדת מסמן את הכרטיס כנבחר', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      expect(tester.widget<AppCard>(find.byType(AppCard)).selected, isFalse);

      await tester.pumpWidget(_tileHost(buildTile(isHighlighted: true)));
      expect(tester.widget<AppCard>(find.byType(AppCard)).selected, isTrue);
    });

    testWidgets('בלי פעולות אין כפתור ⋯', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      expect(
        find.byIcon(FluentIcons.more_vertical_24_regular),
        findsNothing,
      );
    });

    testWidgets('כפתור ⋯ מוצג כשיש פעולות ופותח אותן', (tester) async {
      var hidden = 0;
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            actions: [
              ToolTileAction(
                icon: FluentIcons.eye_off_24_regular,
                label: 'הסתר מהממשק',
                onTap: () => hidden++,
              ),
            ],
          ),
          size: 140,
        ),
      );

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();
      expect(find.text('הסתר מהממשק'), findsOneWidget);

      await tester.tap(find.text('הסתר מהממשק'));
      await tester.pumpAndSettle();
      expect(hidden, 1);
    });

    // לחיצה על ⋯ אינה אמורה לפתוח את הכלי.
    testWidgets('לחיצה על ⋯ אינה מפעילה את onTap של הקובייה', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            onTap: () => taps++,
            actions: [
              ToolTileAction(
                icon: FluentIcons.eye_off_24_regular,
                label: 'הסתר מהממשק',
                onTap: () {},
              ),
            ],
          ),
          size: 140,
        ),
      );

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('פעולה בלי onTap מוצגת מעומעמת ואינה נבחרת', (tester) async {
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            actions: const [
              ToolTileAction(
                icon: FluentIcons.arrow_left_24_regular,
                label: 'הזז אחורה',
                onTap: null,
              ),
            ],
          ),
          size: 140,
        ),
      );

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<VoidCallback>>(
        find.ancestor(
          of: find.text('הזז אחורה'),
          matching: find.byType(PopupMenuItem<VoidCallback>),
        ),
      );
      expect(item.enabled, isFalse);
    });

    // מקום הכפתור נבחר כך שלא יתנגש בסימן "פתוח" שבפינה הנגדית.
    testWidgets('כפתור ⋯ יושב בפינה השמאלית-עליונה של הקובייה', (tester) async {
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            isOpen: true,
            actions: [
              ToolTileAction(
                icon: FluentIcons.eye_off_24_regular,
                label: 'הסתר מהממשק',
                onTap: () {},
              ),
            ],
          ),
          size: 140,
        ),
      );

      final tile = tester.getRect(find.byType(ToolTile));
      final button = tester.getRect(
        find.byIcon(FluentIcons.more_vertical_24_regular),
      );
      final openMark = tester.getRect(
        find.byIcon(FluentIcons.checkmark_circle_16_filled),
      );
      expect(button.center.dx, lessThan(tile.center.dx));
      expect(button.center.dy, lessThan(tile.center.dy));
      expect(
        button.center.dx,
        lessThan(openMark.center.dx),
        reason: 'סימן "פתוח" יושב בפינה הנגדית ואינו מתנגש בכפתור',
      );
      // האייקון קטן משטח הלחיצה — הכפתור נשאר נוח ללחיצה גם כשהנקודות זעירות.
      expect(button.width, lessThan(ToolTile.menuButtonSize));
      expect(
        tester
            .widget<Icon>(find.byIcon(FluentIcons.more_vertical_24_regular))
            .size,
        ToolTile.menuIconSize,
      );
    });

    testWidgets('פעולה עם תת-פעולות נפתחת כתת-תפריט', (tester) async {
      var moved = 0;
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            actions: [
              ToolTileAction(
                icon: FluentIcons.re_order_dots_vertical_24_regular,
                label: 'הזזה',
                onTap: null,
                children: [
                  ToolTileAction(
                    icon: FluentIcons.arrow_left_24_regular,
                    label: 'הזז אחורה',
                    onTap: () => moved++,
                  ),
                ],
              ),
            ],
          ),
          size: 140,
        ),
      );

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();
      expect(find.text('הזזה'), findsOneWidget);
      expect(find.text('הזז אחורה'), findsNothing);

      await tester.tap(find.text('הזזה'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הזז אחורה'));
      await tester.pumpAndSettle();
      expect(moved, 1);
    });

    testWidgets('תת-תפריט שכל פעולותיו מושבתות אינו נפתח', (tester) async {
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            actions: const [
              ToolTileAction(
                icon: FluentIcons.re_order_dots_vertical_24_regular,
                label: 'הזזה',
                onTap: null,
                children: [
                  ToolTileAction(
                    icon: FluentIcons.arrow_left_24_regular,
                    label: 'הזז אחורה',
                    onTap: null,
                  ),
                ],
              ),
            ],
          ),
          size: 140,
        ),
      );

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();
      expect(_menuItemEnabled(tester, 'הזזה'), isFalse);

      // שורת תת-תפריט מושבתת עדיין נפתחת בלחיצה על ה-InkWell הפנימי שלה, ולכן
      // היא מרונדרת כשורה רגילה מעומעמת — בלי תת-פעולות בכלל.
      await tester.tap(find.text('הזזה'));
      await tester.pumpAndSettle();
      expect(find.text('הזז אחורה'), findsNothing);
    });

    testWidgets('פעימת הזזה אינה זורקת ומתייצבת', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      await tester.pumpWidget(_tileHost(buildTile(movePulse: 1)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('לוח שנה'), findsOneWidget);
    });
  });

  group('פאנל הכלים — סימון, גלילה, פעולות וסידור', () {
    late _RecordingSettingsBloc settingsBloc;
    late _RecordingPluginSystemBloc pluginSystemBloc;
    late _TestTabsBloc tabsBloc;
    late List<ToolCatalogEntry> selected;

    /// שני תוספים פעילים, כדי שתהיה גם קבוצת "תוספים" עם שכן להזזה.
    List<InstalledPlugin> plugins() => [
      _pluginEntry('com.example.a', 'תוסף א').plugin!,
      _pluginEntry('com.example.b', 'תוסף ב').plugin!,
    ];

    Future<void> pumpPanel(
      WidgetTester tester, {
      SettingsState? settings,
      PluginSystemState? pluginState,
      double width = 520,
      double height = 600,
    }) async {
      settingsBloc = _RecordingSettingsBloc(
        settings ?? SettingsState.initial(),
      );
      pluginSystemBloc = _RecordingPluginSystemBloc(
        pluginState ?? PluginSystemLoaded(plugins()),
      );
      tabsBloc = _TestTabsBloc(TabsState.initial());
      selected = [];
      addTearDown(() async {
        await settingsBloc.close();
        await pluginSystemBloc.close();
        await tabsBloc.close();
      });

      await tester.pumpWidget(
        _launcherHost(
          settingsBloc: settingsBloc,
          pluginSystemBloc: pluginSystemBloc,
          tabsBloc: tabsBloc,
          onToolSelected: selected.add,
          width: width,
          height: height,
        ),
      );
      await tester.pump();
    }

    Future<void> openMenu(WidgetTester tester, String label) async {
      await tester.tap(_menuButtonOf(label));
      await tester.pumpAndSettle();
    }

    Future<void> tapMenuItem(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    /// פותח את תפריט הקובייה ואת תת-תפריט "הזזה" שבתוכו.
    Future<void> openMoveSubmenu(WidgetTester tester, String label) async {
      await openMenu(tester, label);
      await tester.tap(find.text('הזזה'));
      await tester.pumpAndSettle();
    }

    // ── סימון מקלדת ─────────────────────────────────────────────────────────

    testWidgets('בפתיחה אין קובייה מסומנת — לוח שנה לא נראה נבחר', (
      tester,
    ) async {
      await pumpPanel(tester);
      expect(_selectedCardCount(tester), 0);
      expect(_isCardSelected(tester, 'לוח שנה'), isFalse);
    });

    testWidgets('החץ הראשון מסמן את הקובייה הראשונה', (tester) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(_selectedCardCount(tester), 1);
      expect(_isCardSelected(tester, 'לוח שנה'), isTrue);
    });

    testWidgets('חיפוש מסמן את התוצאה הראשונה', (tester) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'גימ');
      await tester.pump();

      expect(_selectedCardCount(tester), 1);
      expect(_isCardSelected(tester, 'גימטריה'), isTrue);
    });

    testWidgets('ניקוי החיפוש מחזיר למצב ללא סימון', (tester) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'גימ');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(_selectedCardCount(tester), 0);
    });

    testWidgets('Enter בלי סימון פותח את הכלי הראשון', (tester) async {
      await pumpPanel(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(selected.single.toolId, 'builtin.calendar');
    });

    // ── פס הגלילה ───────────────────────────────────────────────────────────

    testWidgets('הרשת שומרת מרווח בימין לפס הגלילה ומתחת לסרגל הצף', (
      tester,
    ) async {
      await pumpPanel(tester);
      final padding = tester.widget<SliverPadding>(
        find.byType(SliverPadding).last,
      );
      expect(
        padding.padding,
        EdgeInsets.only(
          right: kToolGridScrollbarGutter,
          bottom: AppInputTokens.height(false) + AppTokens.spaceMD,
        ),
      );
    });

    // ברוחב הפאנל שבברירת מחדל נכנסות ארבע קוביות בשורה, הקובייה נשארת
    // ריבוע, והאייקון נכנס בה בשלמותו יחד עם שתי שורות התווית.
    testWidgets('ברוחב הפאנל שבברירת מחדל — 4 קוביות בשורה', (tester) async {
      await pumpPanel(tester, width: _kDefaultPanelContentWidth);
      expect(tester.takeException(), isNull);

      for (final grid in tester.widgetList<SliverGrid>(
        find.byType(SliverGrid),
      )) {
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, 4);
        expect(delegate.childAspectRatio, 1.0);
      }

      final tileSize = tester.getSize(find.byType(ToolTile).first);
      expect(tileSize.width, moreOrLessEquals(tileSize.height, epsilon: 0.01));
      final tileHeight = tileSize.height;
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(ToolTile).first,
          matching: find.byIcon(OtzariaIcons.calendar_24_regular),
        ),
      );
      expect(icon.size, ToolTile.maxIconSize);
      expect(
        ToolTile.maxIconSize + AppTokens.spaceXS + ToolTile.labelBlockHeight,
        lessThan(tileHeight - AppTokens.spaceXS * 2),
      );
    });

    testWidgets('רשת ארוכה בונה רק קוביות באזור הנראה', (tester) async {
      const pluginCount = 120;
      await pumpPanel(
        tester,
        pluginState: PluginSystemLoaded([
          for (var i = 0; i < pluginCount; i++)
            _pluginEntry('com.example.p$i', 'תוסף מספר $i').plugin!,
        ]),
      );

      expect(find.byType(ToolTile).evaluate().length, greaterThan(0));
      expect(
        find.byType(ToolTile).evaluate().length,
        lessThan(kBuiltInToolsCatalog.length + pluginCount),
      );
    });

    testWidgets('פס הגלילה מוצמד לימין בשולחן העבודה', (tester) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        final scrollbars = tester.widgetList<Scrollbar>(
          find.byType(Scrollbar),
        );
        expect(scrollbars, isNotEmpty);
        expect(
          scrollbars.every(
            (bar) => bar.scrollbarOrientation == ScrollbarOrientation.right,
          ),
          isTrue,
        );
      });
    });

    // ── תוכן תפריט ⋯ ────────────────────────────────────────────────────────

    testWidgets('לכל קובייה יש כפתור ⋯', (tester) async {
      await pumpPanel(tester);
      expect(
        find.byIcon(FluentIcons.more_vertical_24_regular),
        findsNWidgets(kBuiltInToolsCatalog.length + 2),
      );
    });

    testWidgets('תפריט כלי מובנה: הזזה, הצמדה והסתרה בלבד', (tester) async {
      await pumpPanel(tester);
      await openMenu(tester, 'גימטריה');

      expect(find.text('הזזה'), findsOneWidget);
      expect(find.text('הצמד לסרגל הניווט'), findsOneWidget);
      expect(find.text('הסתר מהממשק'), findsOneWidget);
      expect(find.text('ניהול הרשאות'), findsNothing);
      expect(find.text('מחק תוסף'), findsNothing);
      expect(find.text('השבת'), findsNothing);
      // פעולות ההזזה עצמן חבויות בתת-תפריט ואינן מציפות את התפריט הראשי.
      expect(find.text('הזז אחורה'), findsNothing);
      expect(find.text('הזז לסוף'), findsNothing);
    });

    testWidgets('תת-תפריט "הזזה" מכיל את ארבע פעולות ההזזה', (tester) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'גימטריה');

      expect(find.text('הזז אחורה'), findsOneWidget);
      expect(find.text('הזז קדימה'), findsOneWidget);
      expect(find.text('הזז לתחילה'), findsOneWidget);
      expect(find.text('הזז לסוף'), findsOneWidget);
    });

    testWidgets('תפריט תוסף כולל את כל הפעולות שהיו לפני השינוי', (
      tester,
    ) async {
      await pumpPanel(tester);
      await openMenu(tester, 'תוסף א');

      expect(find.text('ניהול הרשאות'), findsOneWidget);
      expect(find.text('הצמד לסרגל הניווט'), findsOneWidget);
      expect(find.text('הסתר מהממשק'), findsOneWidget);
      expect(find.text('השבת'), findsOneWidget);
      expect(find.text('מחק תוסף'), findsOneWidget);
      expect(find.text('הזזה'), findsOneWidget);
    });

    testWidgets('תוסף שהוצמד לסרגל מציג "הסר מסרגל הניווט"', (tester) async {
      final pinned = _pluginEntry(
        'com.example.pinned',
        'תוסף נעוץ',
      ).plugin!.copyWith(pinnedToNavRail: true);
      await pumpPanel(tester, pluginState: PluginSystemLoaded([pinned]));
      await openMenu(tester, 'תוסף נעוץ');

      expect(find.text('הסר מסרגל הניווט'), findsOneWidget);
      expect(find.text('הצמד לסרגל הניווט'), findsNothing);
    });

    testWidgets('כלי מובנה שהוצמד לסרגל מציג "הסר מסרגל הניווט"', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        settings: SettingsState.initial().copyWith(
          builtInToolsPinnedToNavRail: const {'builtin.gematria'},
        ),
      );
      await openMenu(tester, 'גימטריה');

      expect(find.text('הסר מסרגל הניווט'), findsOneWidget);
    });

    // בראש הקבוצה אין "אחורה" — הלחיצה על פריט מושבת אינה משנה סדר.
    testWidgets('בראש הקבוצה "הזז אחורה" אינו עושה דבר', (tester) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'לוח שנה');
      await tapMenuItem(tester, 'הזז אחורה');

      expect(
        settingsBloc.recorded.whereType<UpdateBuiltInToolsOrder>(),
        isEmpty,
      );
    });

    testWidgets('בסוף הקבוצה "הזז קדימה" אינו עושה דבר', (tester) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'ביוגרפיות');
      await tapMenuItem(tester, 'הזז קדימה');

      expect(
        settingsBloc.recorded.whereType<UpdateBuiltInToolsOrder>(),
        isEmpty,
      );
    });

    // ── פעולות בפועל ────────────────────────────────────────────────────────

    testWidgets('"הזז קדימה" על כלי מובנה שומר סדר חדש', (tester) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'לוח שנה');
      await tapMenuItem(tester, 'הזז קדימה');

      final event = settingsBloc.recorded.whereType<UpdateBuiltInToolsOrder>();
      expect(event, hasLength(1));
      expect(event.single.builtInToolsOrder.take(2), [
        'builtin.shamor_zachor',
        'builtin.calendar',
      ]);
      expect(
        event.single.builtInToolsOrder.length,
        kBuiltInToolsCatalog.length,
        reason: 'הסדר שנשמר חייב להכיל את כל הכלים, אחרת ייווצרו מזהים חסרים',
      );
    });

    testWidgets('"הזז אחורה" על כלי מובנה מקדים אותו לשכנו', (tester) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'הערות אישיות');
      await tapMenuItem(tester, 'הזז אחורה');

      final order = settingsBloc.recorded
          .whereType<UpdateBuiltInToolsOrder>()
          .single
          .builtInToolsOrder;
      expect(order.take(3), [
        'builtin.calendar',
        'builtin.notes',
        'builtin.shamor_zachor',
      ]);
    });

    // הזזה צעד-צעד לא מעשית למרחק גדול; "לתחילה"/"לסוף" קופצות בפעולה אחת.
    testWidgets('"הזז לתחילה" מקדם את הכלי לראש הקבוצה בפעולה אחת', (
      tester,
    ) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'ראשי תיבות');
      await tapMenuItem(tester, 'הזז לתחילה');

      final order = settingsBloc.recorded
          .whereType<UpdateBuiltInToolsOrder>()
          .single
          .builtInToolsOrder;
      expect(order.first, 'builtin.acronyms_dictionary');
      expect(order.length, kBuiltInToolsCatalog.length);
    });

    testWidgets('"הזז לסוף" מעביר את הכלי לסוף הקבוצה בפעולה אחת', (
      tester,
    ) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'לוח שנה');
      await tapMenuItem(tester, 'הזז לסוף');

      final order = settingsBloc.recorded
          .whereType<UpdateBuiltInToolsOrder>()
          .single
          .builtInToolsOrder;
      expect(order.last, 'builtin.calendar');
      expect(order.length, kBuiltInToolsCatalog.length);
    });

    testWidgets('בראש הקבוצה "הזז לתחילה" אינו משנה סדר', (tester) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'לוח שנה');
      await tapMenuItem(tester, 'הזז לתחילה');

      expect(
        settingsBloc.recorded.whereType<UpdateBuiltInToolsOrder>(),
        isEmpty,
      );
    });

    testWidgets('"הזז לסוף" על תוסף נשאר בתוך קבוצת התוספים', (tester) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'תוסף א');
      await tapMenuItem(tester, 'הזז לסוף');

      final event = pluginSystemBloc.recorded
          .whereType<ReorderPluginsRequested>()
          .single;
      expect(event.orderedPluginIds, ['com.example.b', 'com.example.a']);
      expect(
        settingsBloc.recorded.whereType<UpdateBuiltInToolsOrder>(),
        isEmpty,
        reason: 'הזזת תוסף אינה נוגעת בסדר הכלים המובנים',
      );
    });

    testWidgets('"הסתר מהממשק" על כלי מובנה מוסיף אותו למוסתרים', (
      tester,
    ) async {
      await pumpPanel(tester);
      await openMenu(tester, 'גימטריה');
      await tapMenuItem(tester, 'הסתר מהממשק');

      final event = settingsBloc.recorded
          .whereType<UpdateHiddenBuiltInToolIds>()
          .single;
      expect(event.hiddenBuiltInToolIds, contains('builtin.gematria'));
    });

    testWidgets('"הצמד לסרגל הניווט" על כלי מובנה מעדכן את ההגדרה', (
      tester,
    ) async {
      await pumpPanel(tester);
      await openMenu(tester, 'גימטריה');
      await tapMenuItem(tester, 'הצמד לסרגל הניווט');

      final event = settingsBloc.recorded
          .whereType<UpdateBuiltInToolsPinnedToNavRail>()
          .single;
      expect(event.builtInToolsPinnedToNavRail, {'builtin.gematria'});
    });

    testWidgets('"הזז קדימה" על תוסף משגר סידור תוספים', (tester) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'תוסף א');
      await tapMenuItem(tester, 'הזז קדימה');

      final event = pluginSystemBloc.recorded
          .whereType<ReorderPluginsRequested>()
          .single;
      expect(event.orderedPluginIds, ['com.example.b', 'com.example.a']);
    });

    testWidgets('הסתרת תוסף משגרת SetPluginShowInToolsRequested', (
      tester,
    ) async {
      await pumpPanel(tester);
      await openMenu(tester, 'תוסף א');
      await tapMenuItem(tester, 'הסתר מהממשק');

      final event = pluginSystemBloc.recorded
          .whereType<SetPluginShowInToolsRequested>()
          .single;
      expect(event.pluginId, 'com.example.a');
      expect(event.showInTools, isFalse);
    });

    // ── גרירה לסידור ────────────────────────────────────────────────────────

    /// לחיצה, גרירה ועזיבה. [beforeTarget] קובע לאיזה חצי של קוביית היעד
    /// מגיעים — בכיוון RTL החצי הימני מציב לפניה והשמאלי אחריה.
    Future<TestGesture> dragTileTo(
      WidgetTester tester,
      String from,
      String to, {
      required bool beforeTarget,
      bool release = true,
    }) async {
      // עכבר ולא מגע: בשולחן העבודה הגרירה מוגבלת למצביע מדויק, כדי שהחלקה
      // במגע תמשיך לגלול את הרשת.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(from)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      final target = tester.getRect(
        find.ancestor(of: find.text(to), matching: find.byType(ToolTile)),
      );
      final dx = beforeTarget ? target.width / 4 : -target.width / 4;
      await gesture.moveTo(target.center + Offset(dx, 0));
      await tester.pump();
      if (release) {
        await gesture.up();
        await tester.pumpAndSettle();
      }
      return gesture;
    }

    testWidgets('גרירה לחצי הימני של היעד מציבה לפניו', (tester) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        await dragTileTo(tester, 'ראשי תיבות', 'גימטריה', beforeTarget: true);

        final order = settingsBloc.recorded
            .whereType<UpdateBuiltInToolsOrder>()
            .single
            .builtInToolsOrder;
        expect(
          order.indexOf('builtin.acronyms_dictionary'),
          order.indexOf('builtin.gematria') - 1,
        );
      });
    });

    testWidgets('גרירה לחצי השמאלי של היעד מציבה אחריו', (tester) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        await dragTileTo(tester, 'לוח שנה', 'גימטריה', beforeTarget: false);

        final order = settingsBloc.recorded
            .whereType<UpdateBuiltInToolsOrder>()
            .single
            .builtInToolsOrder;
        expect(
          order.indexOf('builtin.calendar'),
          order.indexOf('builtin.gematria') + 1,
        );
        expect(order.first, 'builtin.shamor_zachor');
      });
    });

    // קו ההוספה הוא החיווי שהמשתמש רואה — היכן הקובייה תיפול.
    testWidgets('בגרירה מוצג קו הוספה אחד בצד שאליו תיפול הקובייה', (
      tester,
    ) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        final gesture = await dragTileTo(
          tester,
          'לוח שנה',
          'גימטריה',
          beforeTarget: true,
          release: false,
        );

        expect(find.byKey(kToolDropIndicatorKey), findsOneWidget);
        final line = tester.getRect(find.byKey(kToolDropIndicatorKey));
        final target = tester.getRect(
          find.ancestor(
            of: find.text('גימטריה'),
            matching: find.byType(ToolTile),
          ),
        );
        expect(
          line.center.dx,
          greaterThan(target.center.dx),
          reason: 'ב-RTL "לפני" הוא הקצה הימני של קובייית היעד',
        );

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('בלי גרירה אין קו הוספה', (tester) async {
      await pumpPanel(tester);
      expect(find.byKey(kToolDropIndicatorKey), findsNothing);
    });

    testWidgets('גרירה למרחק גדול מגיעה למקום בפעולה אחת', (tester) async {
      await _asDesktop(() async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpPanel(tester);
        await dragTileTo(
          tester,
          'לוח שנה',
          'ביוגרפיות',
          beforeTarget: false,
        );

        final order = settingsBloc.recorded
            .whereType<UpdateBuiltInToolsOrder>()
            .single
            .builtInToolsOrder;
        expect(order.last, 'builtin.calendar');
      });
    });

    testWidgets('גרירת תוסף על תוסף מסדרת את התוספים', (tester) async {
      await _asDesktop(() async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpPanel(tester, height: 900);
        await dragTileTo(tester, 'תוסף א', 'תוסף ב', beforeTarget: false);

        expect(
          pluginSystemBloc.recorded
              .whereType<ReorderPluginsRequested>()
              .single
              .orderedPluginIds,
          ['com.example.b', 'com.example.a'],
        );
      });
    });

    testWidgets('גרירת כלי מובנה על תוסף אינה מסדרת דבר', (tester) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        await dragTileTo(tester, 'לוח שנה', 'תוסף א', beforeTarget: true);

        expect(
          settingsBloc.recorded.whereType<UpdateBuiltInToolsOrder>(),
          isEmpty,
        );
        expect(
          pluginSystemBloc.recorded.whereType<ReorderPluginsRequested>(),
          isEmpty,
        );
        expect(find.byKey(kToolDropIndicatorKey), findsNothing);
      });
    });

    // ── issue #929: שחרור בשטח הריק וגלילת קצה ──────────────────────────────

    ScrollPosition gridPosition(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    /// גורר קובייה אל השטח הריק שמתחת לרשת, בלי לשחרר.
    Future<TestGesture> dragTileToEmptySpace(
      WidgetTester tester,
      String from,
    ) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(from)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      final grid = tester.getRect(find.byType(CustomScrollView));
      await gesture.moveTo(Offset(grid.center.dx, grid.bottom - 8));
      await tester.pump();
      return gesture;
    }

    testWidgets('שחרור בשטח הריק שמתחת לרשת מעביר תוסף לסוף קבוצתו', (
      tester,
    ) async {
      await _asDesktop(() async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpPanel(tester, height: 900);
        final gesture = await dragTileToEmptySpace(tester, 'תוסף א');

        // קו ההוספה מוצג בקצה ה-end של הקובייה האחרונה בקבוצה — ב-RTL
        // הצד השמאלי, כלומר "אחריה".
        expect(find.byKey(kToolDropIndicatorKey), findsOneWidget);
        final line = tester.getRect(find.byKey(kToolDropIndicatorKey));
        final lastTile = tester.getRect(
          find.ancestor(
            of: find.text('תוסף ב'),
            matching: find.byType(ToolTile),
          ),
        );
        expect(line.center.dx, lessThan(lastTile.center.dx));

        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          pluginSystemBloc.recorded
              .whereType<ReorderPluginsRequested>()
              .single
              .orderedPluginIds,
          ['com.example.b', 'com.example.a'],
        );
      });
    });

    testWidgets('שחרור בשטח הריק עם כלי מובנה מעביר אותו לסוף הכלים', (
      tester,
    ) async {
      await _asDesktop(() async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpPanel(tester, height: 900);
        final gesture = await dragTileToEmptySpace(tester, 'לוח שנה');
        await gesture.up();
        await tester.pumpAndSettle();

        final order = settingsBloc.recorded
            .whereType<UpdateBuiltInToolsOrder>()
            .single
            .builtInToolsOrder;
        expect(order.last, 'builtin.calendar');
        expect(
          pluginSystemBloc.recorded.whereType<ReorderPluginsRequested>(),
          isEmpty,
        );
      });
    });

    testWidgets('שחרור בשטח הריק כשהמקור כבר אחרון אינו משנה דבר', (
      tester,
    ) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        final gesture = await dragTileToEmptySpace(tester, 'תוסף ב');

        expect(find.byKey(kToolDropIndicatorKey), findsNothing);

        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          pluginSystemBloc.recorded.whereType<ReorderPluginsRequested>(),
          isEmpty,
        );
      });
    });

    testWidgets('גרירה אל הקצה התחתון גוללת את הרשת אוטומטית', (tester) async {
      await _asDesktop(() async {
        await pumpPanel(
          tester,
          pluginState: PluginSystemLoaded([
            for (var i = 0; i < 20; i++)
              _pluginEntry('com.example.p$i', 'תוסף מספר $i').plugin!,
          ]),
        );
        final position = gridPosition(tester);
        expect(position.pixels, 0);

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('גימטריה')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 50));
        final grid = tester.getRect(find.byType(CustomScrollView));
        await gesture.moveTo(Offset(grid.center.dx, grid.bottom - 10));
        await tester.pump();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(position.pixels, greaterThan(0));

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('גרירה אל הקצה העליון גוללת את הרשת חזרה למעלה', (
      tester,
    ) async {
      await _asDesktop(() async {
        await pumpPanel(
          tester,
          pluginState: PluginSystemLoaded([
            for (var i = 0; i < 20; i++)
              _pluginEntry('com.example.p$i', 'תוסף מספר $i').plugin!,
          ]),
        );
        final position = gridPosition(tester);
        position.jumpTo(200);
        await tester.pump();

        final grid = tester.getRect(find.byType(CustomScrollView));
        final tiles = find.byType(ToolTile);
        final index = List.generate(tiles.evaluate().length, (i) => i)
            .firstWhere(
              (i) {
                final dy = tester.getRect(tiles.at(i)).center.dy;
                return dy > grid.top + 80 && dy < grid.bottom - 80;
              },
            );
        final gesture = await tester.startGesture(
          tester.getCenter(tiles.at(index)),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.moveTo(Offset(grid.center.dx, grid.top + 10));
        await tester.pump();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(position.pixels, lessThan(200));

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    // הבאג: Draggable רגיל תופס את המחווה כבר בפיקסל אחד בעכבר, ואז לחיצה
    // שהיד רעדה בה לא הגיעה ללחצן — הכלי לא נפתח.
    testWidgets('לחיצה עם רעידת עכבר קטנה עדיין פותחת את הכלי', (tester) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('לוח שנה')),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(2, 1));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(selected.single.toolId, 'builtin.calendar');
      });
    });

    testWidgets('לחיצה עם רעידת עכבר קטנה עדיין פותחת את תפריט ⋯', (
      tester,
    ) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        final gesture = await tester.startGesture(
          tester.getCenter(_menuButtonOf('לוח שנה')),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(2, 1));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('הסתר מהממשק'), findsOneWidget);
      });
    });

    // במגע בשולחן העבודה (מסך מגע ב-Windows) הגלילה חשובה יותר מהגרירה, ולכן
    // הסידור שם נעשה דרך תפריט ⋯.
    testWidgets('החלקה במגע בשולחן העבודה אינה מסדרת ואינה פותחת כלי', (
      tester,
    ) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('לוח שנה')),
        );
        await gesture.moveTo(tester.getCenter(find.text('גימטריה')));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          settingsBloc.recorded.whereType<UpdateBuiltInToolsOrder>(),
          isEmpty,
        );
      });
    });

    testWidgets('אחרי פעולה בתפריט המקלדת חוזרת לפאנל', (tester) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        await openMenu(tester, 'גימטריה');
        await tapMenuItem(tester, 'הצמד לסרגל הניווט');

        // Escape מטופל ב-onKeyEvent של שדה החיפוש; אם הפוקוס נשאר על מסלול
        // התפריט שנסגר — הוא לא יגיע לפאנל.
        final searchField = tester.widget<TextField>(find.byType(TextField));
        expect(searchField.focusNode!.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(_selectedCardCount(tester), 1);
      });
    });

    testWidgets('סימון שיצא מהטווח מתאפס כשהרשימה מתקצרת', (tester) async {
      await pumpPanel(tester);
      for (var i = 0; i < kBuiltInToolsCatalog.length + 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      }
      await tester.pump();
      expect(_selectedCardCount(tester), 1);

      await pumpPanel(
        tester,
        pluginState: PluginSystemLoaded(const []),
        settings: SettingsState.initial().copyWith(
          hiddenBuiltInToolIds: const {'builtin.acronyms_dictionary'},
        ),
      );
      expect(_selectedCardCount(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('גרירה אינה פותחת את הכלי', (tester) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        await dragTileTo(tester, 'לוח שנה', 'גימטריה', beforeTarget: false);
        expect(selected, isEmpty);
      });
    });

    // בחיפוש הקוביות מסוננות, ולכן "השכן" על המסך אינו השכן האמיתי בסדר.
    testWidgets('בחיפוש פעיל הסידור מושבת', (tester) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'ו');
      await tester.pump();

      expect(find.byType(Draggable<ToolCatalogEntry>), findsNothing);
      expect(find.byType(LongPressDraggable<ToolCatalogEntry>), findsNothing);

      await openMenu(tester, 'לוח שנה');
      expect(_menuItemEnabled(tester, 'הזזה'), isFalse);
    });

    // שאילתה של פיסוק בלבד מתנרמלת לריקה ואינה מסננת דבר, ולכן אין סיבה
    // להשבית את הסידור או לסמן קובייה.
    testWidgets('שאילתת פיסוק בלבד אינה מצב חיפוש', (tester) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), '״');
      await tester.pump();

      expect(_selectedCardCount(tester), 0);
      expect(
        find.byType(ToolTile),
        findsNWidgets(kBuiltInToolsCatalog.length + 2),
      );
      await openMenu(tester, 'לוח שנה');
      expect(_menuItemEnabled(tester, 'הזזה'), isTrue);
    });

    testWidgets('חץ למטה ראשון מסמן את הקובייה הראשונה, לא את השורה הבאה', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(_selectedCardCount(tester), 1);
      expect(_isCardSelected(tester, 'לוח שנה'), isTrue);
    });

    testWidgets('הפאנל מצייר את הסדר השמור', (tester) async {
      await pumpPanel(
        tester,
        settings: SettingsState.initial().copyWith(
          builtInToolsOrder: const [
            'builtin.acronyms_dictionary',
            'builtin.calendar',
          ],
        ),
      );

      final labels = tester
          .widgetList<ToolTile>(find.byType(ToolTile))
          .map((tile) => tile.entry.label)
          .toList();
      expect(labels.first, 'ראשי תיבות');
      expect(labels[1], 'לוח שנה');
    });

    testWidgets('תוסף שהוסתר מהממשק לא מופיע בכלים גם כשהוא מוצמד', (
      tester,
    ) async {
      final hiddenPinned = _pluginEntry(
        'com.example.hidden',
        'תוסף נסתר',
      ).plugin!.copyWith(showInTools: false, pinnedToNavRail: true);
      await pumpPanel(
        tester,
        pluginState: PluginSystemLoaded([hiddenPinned]),
      );

      expect(find.text('תוסף נסתר'), findsNothing);
    });

    // ההזזה השנייה מגיעה לפני שה-bloc התיישר; בלי בסיס ממתין היא הייתה
    // מחושבת מהסדר הישן ומוחקת את הראשונה.
    testWidgets('שתי הזזות רצופות נערמות ואינן מבטלות זו את זו', (
      tester,
    ) async {
      await _asDesktop(() async {
        await pumpPanel(tester);
        await dragTileTo(tester, 'לוח שנה', 'גימטריה', beforeTarget: false);
        await dragTileTo(tester, 'שמור וזכור', 'גימטריה', beforeTarget: false);

        final orders = settingsBloc.recorded
            .whereType<UpdateBuiltInToolsOrder>()
            .map((event) => event.builtInToolsOrder)
            .toList();
        expect(orders, hasLength(2));
        expect(
          orders.last.indexOf('builtin.calendar'),
          greaterThan(orders.last.indexOf('builtin.gematria')),
          reason: 'ההזזה הראשונה חייבת לשרוד בסדר שהשנייה שולחת',
        );
        expect(
          orders.last.indexOf('builtin.shamor_zachor'),
          greaterThan(orders.last.indexOf('builtin.gematria')),
        );
      });
    });

    testWidgets('סידור מחדש אינו זורק וממשיך להציג את כל הכלים', (
      tester,
    ) async {
      await pumpPanel(tester);
      await openMoveSubmenu(tester, 'לוח שנה');
      await tapMenuItem(tester, 'הזז קדימה');

      expect(tester.takeException(), isNull);
      expect(
        find.byType(ToolTile),
        findsNWidgets(kBuiltInToolsCatalog.length + 2),
      );
    });
  });

  group('canReorderBetween', () {
    final builtInA = _entry('builtin.calendar', 'לוח שנה');
    final builtInB = _entry('builtin.gematria', 'גימטריה');
    final pluginA = _pluginEntry('com.example.a', 'תוסף א');
    final pluginB = _pluginEntry('com.example.b', 'תוסף ב');
    final leadingPlugin = _pluginEntry(
      'com.example.lead',
      'תוסף מקדים',
      allowOrderBeforeBuiltIns: true,
    );

    test('שני כלים מובנים — מותר', () {
      expect(canReorderBetween(builtInA, builtInB), isTrue);
    });

    test('שני תוספים באותה קבוצה — מותר', () {
      expect(canReorderBetween(pluginA, pluginB), isTrue);
    });

    test('כלי מובנה ותוסף — אסור', () {
      expect(canReorderBetween(builtInA, pluginA), isFalse);
      expect(canReorderBetween(pluginA, builtInA), isFalse);
    });

    test('תוסף מקדים ותוסף רגיל בקבוצות שונות — אסור', () {
      expect(canReorderBetween(leadingPlugin, pluginA), isFalse);
    });

    test('אותה רשומה — אסור', () {
      expect(canReorderBetween(builtInA, builtInA), isFalse);
    });
  });
}

class _ToolsLauncherOverlayHarness extends StatefulWidget {
  const _ToolsLauncherOverlayHarness({super.key, this.backgroundFocusNode});

  /// שדה רקע שממוקד לפני פתיחת הפאנל — מדמה מסך קריאה שמחזיק את הפוקוס.
  final FocusNode? backgroundFocusNode;

  @override
  State<_ToolsLauncherOverlayHarness> createState() =>
      _ToolsLauncherOverlayHarnessState();
}

class _ToolsLauncherOverlayHarnessState
    extends State<_ToolsLauncherOverlayHarness> {
  bool _isOpen = false;

  void open() => setState(() => _isOpen = true);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox.expand(
          child: widget.backgroundFocusNode == null
              ? null
              : TextField(focusNode: widget.backgroundFocusNode),
        ),
        ContextOverlayPanel(
          isOpen: _isOpen,
          onClose: () => setState(() => _isOpen = false),
          alignment: AlignmentDirectional.centerStart,
          deferChildBuildOnOpen: true,
          child: ToolsLauncherPanel(
            showDevTools: false,
            onClose: () => setState(() => _isOpen = false),
            onToolSelected: (_) {},
          ),
        ),
      ],
    );
  }
}

/// בלוק הגדרות שמתעד את האירועים שנשלחו אליו, בלי לשמור לדיסק.
class _RecordingSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _RecordingSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  final List<SettingsEvent> recorded = [];

  @override
  void add(SettingsEvent event) {
    recorded.add(event);
    super.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingPluginSystemBloc
    extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  _RecordingPluginSystemBloc(super.initialState) {
    on<PluginSystemEvent>((event, emit) {});
  }

  final List<PluginSystemEvent> recorded = [];

  @override
  void add(PluginSystemEvent event) {
    recorded.add(event);
    super.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPluginSystemBloc extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  _TestPluginSystemBloc(super.initialState) {
    on<PluginSystemEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  @override
  void add(TabsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
