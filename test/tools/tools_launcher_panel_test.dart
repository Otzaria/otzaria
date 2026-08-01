import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/tools/view/tools_launcher_panel.dart';
import 'package:otzaria/widgets/layout/app_card.dart';

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
    allowOrderBeforeBuiltInsGranted: true,
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
      allowOrderBeforeBuiltIns: false,
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

void main() {
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
      expect(
        filterToolEntries(entries, 'גימ').map((e) => e.toolId),
        ['builtin.gematria'],
      );
    });

    test('חיפוש עם ניקוד/מקף עדיין מתאים', () {
      expect(
        filterToolEntries(entries, 'לוּחַ').map((e) => e.toolId),
        ['builtin.calendar'],
      );
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
    test('שני מקטעים: כלים מובנים ואז תוספים', () {
      final groups = groupToolEntries([
        _entry('builtin.calendar', 'לוח שנה'),
        _pluginEntry('com.example.x', 'תוסף'),
        _entry('builtin.gematria', 'גימטריה'),
      ]);
      expect(groups.map((g) => g.label), [
        kBuiltInToolsGroupLabel,
        kPluginsGroupLabel,
      ]);
      expect(groups.first.entries.map((e) => e.toolId), [
        'builtin.calendar',
        'builtin.gematria',
      ]);
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
        _pluginEntry('p.a', 'א'),
        _entry('builtin.a', 'א'),
      ]);
      expect(groups.first.entries.map((e) => e.toolId), [
        'builtin.z',
        'builtin.a',
      ]);
      expect(groups.last.entries.map((e) => e.toolId), ['p.b', 'p.a']);
    });

    test('רשימה ריקה — אין קבוצות', () {
      expect(groupToolEntries(const []), isEmpty);
    });
  });

  // ניווט המקלדת ממופה לאינדקס ברשימה השטוחה, ולכן היא חייבת להיות בסדר
  // הרינדור — כולל תוסף שהמיון הקדים לכלים המובנים.
  group('orderedToolEntries', () {
    test('מחזיר את הסדר המוצג: מובנים ואז תוספים', () {
      final ordered = orderedToolEntries([
        _pluginEntry('com.example.first', 'תוסף מקדים'),
        _entry('builtin.calendar', 'לוח שנה'),
        _pluginEntry('com.example.x', 'תוסף'),
      ]);
      expect(ordered.map((e) => e.toolId), [
        'builtin.calendar',
        'com.example.first',
        'com.example.x',
      ]);
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
  });

  group('ToolTile', () {
    ToolTile buildTile({
      ToolCatalogEntry? entry,
      bool isOpen = false,
      bool isHighlighted = false,
      VoidCallback? onTap,
    }) => ToolTile(
      entry: entry ?? _entry('builtin.calendar', 'לוח שנה'),
      isOpen: isOpen,
      isHighlighted: isHighlighted,
      onTap: onTap ?? () {},
    );

    testWidgets('מציג את תווית הכלי', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      expect(find.text('לוח שנה'), findsOneWidget);
    });

    testWidgets('בנוי מעל AppCard — אותו כרטיס כמו בספרייה', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      expect(find.byType(AppCard), findsOneWidget);
    });

    testWidgets('האייקון יושב בריבוע 32 והוא בגודל 16', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));

      final iconBox = tester.getSize(
        find.ancestor(
          of: find.byIcon(FluentIcons.calendar_24_regular),
          matching: find.byType(Container),
        ),
      );
      expect(iconBox, const Size(ToolTile.iconBoxSize, ToolTile.iconBoxSize));

      final icon = tester.widget<Icon>(
        find.byIcon(FluentIcons.calendar_24_regular),
      );
      expect(icon.size, ToolTile.iconSize);
    });

    testWidgets('צבעי הריבוע והאייקון נלקחים מ-secondaryContainer', (
      tester,
    ) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      final context = tester.element(find.byType(ToolTile));
      final cs = Theme.of(context).colorScheme;

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(FluentIcons.calendar_24_regular),
          matching: find.byType(Container),
        ),
      );
      expect(
        (container.decoration as BoxDecoration).color,
        cs.secondaryContainer,
      );

      final icon = tester.widget<Icon>(
        find.byIcon(FluentIcons.calendar_24_regular),
      );
      expect(icon.color, cs.onSecondaryContainer);
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
        find.ancestor(
          of: find.byIcon(FluentIcons.calendar_24_regular),
          matching: find.byType(Container),
        ),
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
      expect(imageIcon.size, ToolTile.iconSize);
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

    testWidgets('Tooltip מציג את שם התוסף כשהוא שונה מהתווית', (tester) async {
      await tester.pumpWidget(
        _tileHost(
          buildTile(
            entry: _pluginEntry('com.example.x', 'מפה', name: 'Atlas'),
          ),
        ),
      );
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Atlas');
    });

    testWidgets('Tooltip נופל לתווית כשאין תוסף', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'לוח שנה');
    });

    testWidgets('סימון מקלדת מסמן את הכרטיס כנבחר', (tester) async {
      await tester.pumpWidget(_tileHost(buildTile()));
      expect(tester.widget<AppCard>(find.byType(AppCard)).selected, isFalse);

      await tester.pumpWidget(_tileHost(buildTile(isHighlighted: true)));
      expect(tester.widget<AppCard>(find.byType(AppCard)).selected, isTrue);
    });
  });
}
