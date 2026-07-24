import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/panels/tools_management_panel.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';

// ─── Test doubles ─────────────────────────────────────────────────────────────

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  final List<SettingsEvent> dispatched = [];
  _FakeSettingsBloc({
    Set<String> hidden = const <String>{},
    Set<String> pinnedToNav = const <String>{},
  }) : super(
         SettingsState.initial().copyWith(
           hiddenBuiltInToolIds: hidden,
           builtInToolsPinnedToNavRail: pinnedToNav,
         ),
       ) {
    on<SettingsEvent>((event, emit) {
      dispatched.add(event);
      if (event is UpdateHiddenBuiltInToolIds) {
        emit(state.copyWith(hiddenBuiltInToolIds: event.hiddenBuiltInToolIds));
      } else if (event is UpdateBuiltInToolsPinnedToNavRail) {
        emit(
          state.copyWith(
            builtInToolsPinnedToNavRail: event.builtInToolsPinnedToNavRail,
          ),
        );
      }
    });
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakePluginSystemBloc extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  final List<PluginSystemEvent> dispatched = [];
  _FakePluginSystemBloc(List<InstalledPlugin> plugins)
    : super(PluginSystemLoaded(plugins)) {
    on<PluginSystemEvent>((event, emit) {
      dispatched.add(event);
    });
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PluginManifest _manifest({
  String id = 'p',
  List<String> permissions = const [],
  bool networkEnabled = false,
}) {
  return PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': id,
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'permissions': permissions,
    'network': {'enabled': networkEnabled},
    'contributes': {
      'toolTab': {'title': id},
    },
  });
}

InstalledPlugin _plugin({
  required String id,
  String name = 'plugin',
  bool enabled = true,
  bool hidden = false,
  bool pinnedToNavRail = false,
  bool networkAccessGranted = false,
  bool runOnStartupGranted = false,
  List<String> permissions = const [],
  bool networkEnabled = false,
}) {
  return InstalledPlugin(
    pluginId: id,
    name: name,
    version: '1.0.0',
    installPath: '/x/$id',
    entrypointPath: 'index.html',
    enabled: enabled,
    pinned: true,
    pinnedToNavRail: pinnedToNavRail,
    showInTools: !hidden,
    networkAccessGranted: networkAccessGranted,
    runOnStartupGranted: runOnStartupGranted,
    manifest: _manifest(
      id: id,
      permissions: permissions,
      networkEnabled: networkEnabled,
    ),
    installedAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

Widget _wrap({
  required SettingsBloc settingsBloc,
  required PluginSystemBloc pluginBloc,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<PluginSystemBloc>.value(value: pluginBloc),
          ],
          child: const SingleChildScrollView(
            child: ToolsManagementPanel(),
          ),
        ),
      ),
    ),
  );
}

/// פותח/סוגר את אזור "כלים מובנים" דרך שורת הסיכום בכרטיס הלבן.
Future<void> _expandBuiltIn(WidgetTester tester) async {
  await tester.tap(find.text('רשימת הכלים'));
  await tester.pumpAndSettle();
}

/// נכנס למצב בחירה מרובה של תוספים על-ידי לחיצה על "בחירה".
Future<void> _enterSelectionMode(WidgetTester tester) async {
  await tester.tap(find.text('בחירה'));
  await tester.pumpAndSettle();
}

/// בוחר תוסף על-פי שמו (מניח שמצב בחירה כבר פעיל).
Future<void> _selectPlugin(WidgetTester tester, String name) async {
  await tester.tap(find.textContaining(name));
  await tester.pumpAndSettle();
}

/// מאתר לחצן (לפי tooltip) בתוך שורת הכלי שמכילה [label].
Finder _rowButton(String label, String tooltip) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byType(ListTile),
  ),
  matching: find.byTooltip(tooltip),
);

/// מדמה ריחוף עכבר מעל שורת תוסף — כפתורי הטוגל של השורה מוצגים רק בריחוף.
Future<TestGesture> _hoverRow(WidgetTester tester, String name) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(tester.getCenter(find.text(name)));
  await tester.pumpAndSettle();
  return gesture;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  testWidgets(
    'built-in section is collapsed by default and expands on tap',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc(const []),
        ),
      );
      await tester.pumpAndSettle();

      // כותרת האזור מופיעה, אבל התוכן סגור.
      expect(find.text('כלים מובנים'), findsOneWidget);
      expect(find.text('לוח שנה'), findsNothing);

      await _expandBuiltIn(tester);

      // לאחר פתיחה — כל הכלים מהקטלוג מופיעים.
      expect(find.text('לוח שנה'), findsOneWidget);
      expect(find.text('גימטריה'), findsOneWidget);
      expect(find.text('שמור וזכור'), findsOneWidget);
    },
  );

  testWidgets(
    'plugins card is hidden when no plugins are installed',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc(const []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('תוספים מותקנים'), findsNothing);
    },
  );

  testWidgets(
    'plugins section shows header and plugin rows when plugins are installed',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(id: 'p1', name: 'תוסף-A'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // הכותרת והשורה גלויים מיד — אין קיפול באזור התוספים.
      expect(find.text('תוספים מותקנים'), findsOneWidget);
      expect(find.textContaining('תוסף-A'), findsOneWidget);
    },
  );

  testWidgets(
    'built-in tool rows have no checkboxes (button-based actions)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc(const []),
        ),
      );
      await tester.pumpAndSettle();
      await _expandBuiltIn(tester);

      // אין תיבות סימון באזור הכלים המובנים, אבל יש לחצני הסתרה/הצמדה —
      // אחד לכל כלי בקטלוג.
      final toolCount = kBuiltInToolsCatalog.length;
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byTooltip('הסתר מהממשק'), findsNWidgets(toolCount));
      expect(find.byTooltip('הצמד לסרגל הניווט'), findsNWidgets(toolCount));
      // אין סרגל בחירה מרובה (אין "נבחרו").
      expect(find.textContaining('נבחרו'), findsNothing);
    },
  );

  testWidgets(
    'tapping the hide button on a built-in tool dispatches '
    'UpdateHiddenBuiltInToolIds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsBloc = _FakeSettingsBloc();

      await tester.pumpWidget(
        _wrap(
          settingsBloc: settingsBloc,
          pluginBloc: _FakePluginSystemBloc(const []),
        ),
      );
      await tester.pumpAndSettle();
      await _expandBuiltIn(tester);

      await tester.tap(_rowButton('לוח שנה', 'הסתר מהממשק'));
      await tester.pumpAndSettle();

      final updates = settingsBloc.dispatched
          .whereType<UpdateHiddenBuiltInToolIds>()
          .toList();
      expect(updates, hasLength(1));
      expect(updates.single.hiddenBuiltInToolIds, contains('builtin.calendar'));
    },
  );

  testWidgets(
    'tapping the pin button on a built-in tool dispatches '
    'UpdateBuiltInToolsPinnedToNavRail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsBloc = _FakeSettingsBloc();

      await tester.pumpWidget(
        _wrap(
          settingsBloc: settingsBloc,
          pluginBloc: _FakePluginSystemBloc(const []),
        ),
      );
      await tester.pumpAndSettle();
      await _expandBuiltIn(tester);

      await tester.tap(_rowButton('גימטריה', 'הצמד לסרגל הניווט'));
      await tester.pumpAndSettle();

      final updates = settingsBloc.dispatched
          .whereType<UpdateBuiltInToolsPinnedToNavRail>()
          .toList();
      expect(updates, hasLength(1));
      expect(
        updates.single.builtInToolsPinnedToNavRail,
        contains('builtin.gematria'),
      );
    },
  );

  testWidgets(
    'a hidden built-in tool\'s show-button is highlighted; a visible tool\'s '
    'hide-button is not',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsBloc = _FakeSettingsBloc(
        hidden: const {'builtin.calendar'},
      );

      await tester.pumpWidget(
        _wrap(
          settingsBloc: settingsBloc,
          pluginBloc: _FakePluginSystemBloc(const []),
        ),
      );
      await tester.pumpAndSettle();
      await _expandBuiltIn(tester);

      // הכלי עדיין מופיע בטבלה — רק הוא מוסתר מהממשק הראשי.
      expect(find.text('לוח שנה'), findsOneWidget);
      // הלחצן בשורת לוח-שנה מציע "הצג בממשק" (ולא "הסתר"), ומודגש ברקע
      // cs.surfaceContainerHighest — ההדגשה שמורה למצב "מושבת" (מוסתר).
      final hiddenButton = tester.widget<IconButton>(
        find.ancestor(
          of: _rowButton('לוח שנה', 'הצג בממשק'),
          matching: find.byType(IconButton),
        ),
      );
      expect(hiddenButton.isSelected, isFalse);
      expect(hiddenButton.style?.backgroundColor?.resolve({}), isNotNull);

      // כלי אחר שלא הוסתר — הלחצן שלו במצב "מוצג" (isSelected) וללא הדגשה.
      final visibleButton = tester.widget<IconButton>(
        find.ancestor(
          of: _rowButton('גימטריה', 'הסתר מהממשק'),
          matching: find.byType(IconButton),
        ),
      );
      expect(visibleButton.isSelected, isTrue);
      expect(visibleButton.style?.backgroundColor?.resolve({}), isNull);
    },
  );

  testWidgets(
    'selecting a plugin reveals the action bar with plugin actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(id: 'p1', name: 'תוסף-A'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('נבחרו'), findsNothing);

      await _enterSelectionMode(tester);
      await _selectPlugin(tester, 'תוסף-A');

      expect(find.text('1 נבחרו'), findsOneWidget);
      expect(find.text('מחק'), findsOneWidget);
      expect(find.text('השבת'), findsOneWidget);
    },
  );

  testWidgets(
    'idle plugin row shows status badges; hover swaps them for the toggle '
    'icons; selection mode shows the badges again',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(
              id: 'p1',
              name: 'תוסף-A',
              hidden: true,
              pinnedToNavRail: true,
              permissions: const ['network.access'],
              networkAccessGranted: true,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // מצב רגיל (לא ריחוף, לא בחירה) — רק התגיות מוצגות, בלי כפתורי טוגל.
      expect(find.byTooltip('מוסתר'), findsOneWidget);
      expect(find.byTooltip('בסרגל ניווט'), findsOneWidget);
      expect(find.byTooltip('משתמש ברשת'), findsOneWidget);
      expect(_rowButton('תוסף-A', 'הצג בממשק'), findsNothing);

      // ריחוף — התגיות נעלמות, וכפתורי הטוגל (כמו כעת) מופיעים במקומן.
      final gesture = await _hoverRow(tester, 'תוסף-A');
      addTearDown(() => gesture.removePointer());

      expect(find.byTooltip('מוסתר'), findsNothing);
      expect(find.byTooltip('בסרגל ניווט'), findsNothing);
      expect(find.byTooltip('משתמש ברשת'), findsNothing);
      expect(_rowButton('תוסף-A', 'הצג בממשק'), findsOneWidget);

      await gesture.moveTo(const Offset(0, 0));
      await tester.pumpAndSettle();

      await _enterSelectionMode(tester);

      // במצב בחירה — התגיות חוזרות להופיע (אין כפתורי טוגל בשורה עצמה).
      expect(find.byTooltip('מוסתר'), findsOneWidget);
      expect(find.byTooltip('בסרגל ניווט'), findsOneWidget);
      expect(find.byTooltip('משתמש ברשת'), findsOneWidget);
      // התוסף מופעל, אז אין תגית "מושבת".
      expect(find.byTooltip('מושבת'), findsNothing);
    },
  );

  testWidgets(
    'selection mode shows a "מושבת" badge in error colors for a disabled plugin',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(id: 'p1', name: 'תוסף-A', enabled: false),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await _enterSelectionMode(tester);

      final badge = find.byTooltip('מושבת');
      expect(badge, findsOneWidget);
      final container = tester.widget<Container>(
        find.descendant(
          of: badge,
          matching: find.byType(Container),
        ),
      );
      final cs = Theme.of(tester.element(badge)).colorScheme;
      expect((container.decoration as BoxDecoration).color, cs.errorContainer);
    },
  );

  testWidgets(
    'selection mode shows a "מנותק מהרשת" badge in error colors when a '
    'network-dependent plugin has access revoked',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(
              id: 'p1',
              name: 'תוסף-A',
              permissions: const ['network.access'],
              networkAccessGranted: false,
              networkEnabled: true,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await _enterSelectionMode(tester);

      final badge = find.byTooltip('מנותק מהרשת');
      expect(badge, findsOneWidget);
      final container = tester.widget<Container>(
        find.descendant(
          of: badge,
          matching: find.byType(Container),
        ),
      );
      final cs = Theme.of(tester.element(badge)).colorScheme;
      expect((container.decoration as BoxDecoration).color, cs.errorContainer);
    },
  );

  testWidgets(
    '"בחר הכל" מופיע במצב בחירה ובוחר את כל התוספים',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(id: 'p1', name: 'תוסף-A'),
            _plugin(id: 'p2', name: 'תוסף-B'),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await _enterSelectionMode(tester);

      // "בחר הכל" גלוי מיד עם כניסה למצב בחירה, ללא צורך לבחור תוסף קודם.
      expect(find.text('בחר הכל'), findsOneWidget);
      expect(find.text('0 נבחרו'), findsOneWidget);

      // לחיצה — כל התוספים נבחרים, וסרגל הפעולות מופיע.
      await tester.tap(find.text('בחר הכל'));
      await tester.pumpAndSettle();
      expect(find.text('2 נבחרו'), findsOneWidget);

      // לחיצה חוזרת — נשאר עם כל הבחירות (addAll לא מבטל).
      await tester.tap(find.text('בחר הכל'));
      await tester.pumpAndSettle();
      expect(find.text('2 נבחרו'), findsOneWidget);
    },
  );

  testWidgets(
    'pressing "ביטול" exits selection mode and clears the selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(id: 'p1', name: 'תוסף-A'),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await _enterSelectionMode(tester);
      await _selectPlugin(tester, 'תוסף-A');
      expect(find.text('1 נבחרו'), findsOneWidget);

      // לחיצה על "ביטול" — יוצאת ממצב בחירה ומנקה את הבחירה.
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      expect(find.textContaining('נבחרו'), findsNothing);
      // חזרנו למצב רגיל — כפתור "בחירה" מופיע שוב.
      expect(find.text('בחירה'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping enable/disable on selected plugin dispatches relevant event',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pluginBloc = _FakePluginSystemBloc([
        _plugin(id: 'p1', name: 'תוסף-A'),
      ]);

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: pluginBloc,
        ),
      );
      await tester.pumpAndSettle();
      await _enterSelectionMode(tester);
      await _selectPlugin(tester, 'תוסף-A');

      await tester.tap(find.text('השבת'));
      await tester.pumpAndSettle();

      final disableEvents = pluginBloc.dispatched
          .whereType<DisablePluginRequested>()
          .toList();
      expect(disableEvents, hasLength(1));
      expect(disableEvents.single.pluginId, 'p1');
    },
  );

  testWidgets(
    'tapping "הסתר מכלים" on a plugin dispatches SetPluginShowInToolsRequested(false)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pluginBloc = _FakePluginSystemBloc([
        _plugin(id: 'p1', name: 'תוסף-A'),
      ]);

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: pluginBloc,
        ),
      );
      await tester.pumpAndSettle();
      await _enterSelectionMode(tester);
      await _selectPlugin(tester, 'תוסף-A');

      await tester.tap(find.text('הסתר'));
      await tester.pumpAndSettle();

      final events = pluginBloc.dispatched
          .whereType<SetPluginShowInToolsRequested>()
          .toList();
      expect(events, hasLength(1));
      expect(events.single.pluginId, 'p1');
      expect(events.single.showInTools, isFalse);
    },
  );

  testWidgets(
    'a disabled plugin row shows only the enable and delete buttons, '
    'but keeps its icon and version like an enabled row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(
              id: 'p1',
              name: 'תוסף-A',
              enabled: false,
              permissions: const ['network.access', 'app.run_on_startup'],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(_rowButton('תוסף-A', 'הפעל'), findsOneWidget);
      expect(_rowButton('תוסף-A', 'מחק תוסף'), findsOneWidget);
      expect(_rowButton('תוסף-A', 'ניהול הרשאות'), findsNothing);
      expect(_rowButton('תוסף-A', 'הסתר מהממשק'), findsNothing);
      expect(_rowButton('תוסף-A', 'הצמד לסרגל הניווט'), findsNothing);
      expect(_rowButton('תוסף-A', 'אישור גישה לרשת'), findsNothing);
      expect(_rowButton('תוסף-A', 'הפעלת טעינה בעלייה'), findsNothing);

      // האייקון והגרסה נשארים מוצגים — גובה השורה זהה לשורת תוסף פעיל.
      final row = find.ancestor(
        of: find.text('תוסף-A'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(FluentIcons.puzzle_piece_24_regular),
        ),
        findsOneWidget,
      );
      expect(find.text('v1.0.0'), findsOneWidget);

      // כפתור המחיקה אף פעם לא "נבחר" — לכן אף פעם לא מקבל צבע, גם כשהתוסף מושבת.
      final deleteButton = tester.widget<IconButton>(
        find.ancestor(
          of: _rowButton('תוסף-A', 'מחק תוסף'),
          matching: find.byType(IconButton),
        ),
      );
      expect(deleteButton.style?.backgroundColor?.resolve({}), isNull);
    },
  );

  testWidgets(
    'enabled plugin row — network/startup/visibility buttons are highlighted '
    'only while disabled/blocked/hidden',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(
              id: 'p1',
              name: 'תוסף-A',
              hidden: true,
              permissions: const ['network.access', 'app.run_on_startup'],
              networkAccessGranted: false,
              runOnStartupGranted: false,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await _hoverRow(tester, 'תוסף-A');
      addTearDown(() => gesture.removePointer());

      IconButton buttonWithTooltip(String tooltip) => tester.widget<IconButton>(
        find.ancestor(
          of: _rowButton('תוסף-A', tooltip),
          matching: find.byType(IconButton),
        ),
      );

      // מוסתר, ללא גישה לרשת, וללא טעינה בעלייה — כל שלושת הכפתורים מודגשים.
      expect(
        buttonWithTooltip('הצג בממשק').style?.backgroundColor?.resolve({}),
        isNotNull,
      );
      expect(
        buttonWithTooltip(
          'אישור גישה לרשת',
        ).style?.backgroundColor?.resolve({}),
        isNotNull,
      );
      expect(
        buttonWithTooltip(
          'הפעלת טעינה בעלייה',
        ).style?.backgroundColor?.resolve({}),
        isNotNull,
      );
    },
  );

  testWidgets(
    'enabled plugin row — network toggle button dispatches granted:true '
    'and is absent without the permission',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pluginBloc = _FakePluginSystemBloc([
        _plugin(
          id: 'p1',
          name: 'תוסף-A',
          permissions: const ['network.access'],
          networkAccessGranted: false,
        ),
        _plugin(id: 'p2', name: 'תוסף-B'),
      ]);

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: pluginBloc,
        ),
      );
      await tester.pumpAndSettle();

      var gesture = await _hoverRow(tester, 'תוסף-B');
      expect(_rowButton('תוסף-B', 'אישור גישה לרשת'), findsNothing);
      await gesture.removePointer();

      gesture = await _hoverRow(tester, 'תוסף-A');
      addTearDown(() => gesture.removePointer());
      await tester.tap(_rowButton('תוסף-A', 'אישור גישה לרשת'));
      await tester.pumpAndSettle();

      final events = pluginBloc.dispatched
          .whereType<SetPluginPermissionRequested>()
          .where((e) => e.permission == 'network.access')
          .toList();
      expect(events, hasLength(1));
      expect(events.single.pluginId, 'p1');
      expect(events.single.granted, isTrue);
    },
  );

  testWidgets(
    'enabled plugin row — startup toggle button dispatches granted:false '
    'when already granted',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pluginBloc = _FakePluginSystemBloc([
        _plugin(
          id: 'p1',
          name: 'תוסף-A',
          permissions: const ['app.run_on_startup'],
          runOnStartupGranted: true,
        ),
      ]);

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: pluginBloc,
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await _hoverRow(tester, 'תוסף-A');
      addTearDown(() => gesture.removePointer());

      await tester.tap(_rowButton('תוסף-A', 'ביטול טעינה בעלייה'));
      await tester.pumpAndSettle();

      final events = pluginBloc.dispatched
          .whereType<SetPluginPermissionRequested>()
          .where((e) => e.permission == 'app.run_on_startup')
          .toList();
      expect(events, hasLength(1));
      expect(events.single.pluginId, 'p1');
      expect(events.single.granted, isFalse);
    },
  );

  testWidgets(
    'network access button — tapping "גישה לרשת" dispatches granted:true',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pluginBloc = _FakePluginSystemBloc([
        _plugin(
          id: 'p1',
          name: 'תוסף-A',
          permissions: const ['network.access'],
          networkAccessGranted: false,
        ),
      ]);

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: pluginBloc,
        ),
      );
      await tester.pumpAndSettle();
      await _enterSelectionMode(tester);
      await _selectPlugin(tester, 'תוסף-A');

      // הכפתור מציג "גישה לרשת" ולוחץ ישירות — אין תפריט
      await tester.tap(find.text('גישה לרשת'));
      await tester.pumpAndSettle();

      final events = pluginBloc.dispatched
          .whereType<SetPluginPermissionRequested>()
          .where((e) => e.permission == 'network.access')
          .toList();
      expect(events, hasLength(1));
      expect(events.single.granted, isTrue);
    },
  );

  testWidgets(
    'network access button — tapping "דחיה מהרשת" dispatches granted:false',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pluginBloc = _FakePluginSystemBloc([
        _plugin(
          id: 'p1',
          name: 'תוסף-A',
          permissions: const ['network.access'],
          networkAccessGranted: true,
        ),
      ]);

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: pluginBloc,
        ),
      );
      await tester.pumpAndSettle();
      await _enterSelectionMode(tester);
      await _selectPlugin(tester, 'תוסף-A');

      // כשהגישה מוענקת — הכפתור מציג "דחיה מהרשת" ושולח granted:false
      await tester.tap(find.text('דחיה מהרשת'));
      await tester.pumpAndSettle();

      final events = pluginBloc.dispatched
          .whereType<SetPluginPermissionRequested>()
          .where((e) => e.permission == 'network.access')
          .toList();
      expect(events, hasLength(1));
      expect(
        events.single.granted,
        isFalse,
        reason: 'revoke must send granted:false',
      );
    },
  );

  testWidgets(
    'idle plugin row shows a single "עוד פעולות" (⋯) button, not the action '
    'icons; tapping it opens the full actions menu',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(
              id: 'p1',
              name: 'תוסף-A',
              permissions: const ['network.access'],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // מצב רגיל: כפתור ⋯ בלבד, בלי אייקוני הפעולה הישירים.
      expect(_rowButton('תוסף-A', 'עוד פעולות'), findsOneWidget);
      expect(_rowButton('תוסף-A', 'ניהול הרשאות'), findsNothing);
      expect(_rowButton('תוסף-A', 'אישור גישה לרשת'), findsNothing);

      // לחיצה על ⋯ פותחת תפריט עם כל האפשרויות.
      await tester.tap(_rowButton('תוסף-A', 'עוד פעולות'));
      await tester.pumpAndSettle();
      expect(find.text('ניהול הרשאות'), findsOneWidget);
      expect(find.text('אישור גישה לרשת'), findsOneWidget);
      expect(find.text('מחק תוסף'), findsOneWidget);
    },
  );

  testWidgets(
    'right-clicking a plugin row opens the actions menu',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(id: 'p1', name: 'תוסף-A'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(
        tester.getCenter(find.text('תוסף-A')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('ניהול הרשאות'), findsOneWidget);
      expect(find.text('מחק תוסף'), findsOneWidget);
    },
  );

  testWidgets(
    'plugin row height stays constant between idle (badges) and hover (version)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(
              id: 'p1',
              name: 'תוסף-A',
              hidden: true,
              pinnedToNavRail: true,
              permissions: const ['network.access'],
              networkAccessGranted: true,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      Finder rowTile() => find.ancestor(
        of: find.text('תוסף-A'),
        matching: find.byType(ListTile),
      );

      final idleHeight = tester.getSize(rowTile()).height;

      final gesture = await _hoverRow(tester, 'תוסף-A');
      addTearDown(() => gesture.removePointer());
      expect(
        tester.getSize(rowTile()).height,
        idleHeight,
        reason: 'hover must not resize the row',
      );
    },
  );

  testWidgets(
    'dragging a plugin row to another row dispatches ReorderPluginsRequested',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pluginBloc = _FakePluginSystemBloc([
        _plugin(id: 'p1', name: 'תוסף-A'),
        _plugin(id: 'p2', name: 'תוסף-B'),
      ]);

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: pluginBloc,
        ),
      );
      await tester.pumpAndSettle();

      // הגרירה זמינה מכל מקום בכרטיס (לא רק מאייקון ייעודי) — גוררים מהכותרת.
      final srcFinder = find.text('תוסף-A');
      final dstFinder = find.text('תוסף-B');
      final srcCenter = tester.getCenter(srcFinder);
      final dstCenter = tester.getCenter(dstFinder);

      await tester.timedDrag(
        srcFinder,
        Offset(0, dstCenter.dy - srcCenter.dy),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      final events = pluginBloc.dispatched
          .whereType<ReorderPluginsRequested>()
          .toList();
      expect(events, hasLength(1));
      // p1 (index 0) dragged to p2 (index 1) → p1 inserted after p2
      expect(events.single.orderedPluginIds, orderedEquals(['p2', 'p1']));
    },
  );

  testWidgets(
    'hovering a plugin row shows the drag-reorder icon instead of the plugin icon',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(id: 'p1', name: 'תוסף-A'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byIcon(FluentIcons.re_order_dots_vertical_24_regular),
        findsNothing,
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(() => gesture.removePointer());
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.text('תוסף-A')));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(FluentIcons.re_order_dots_vertical_24_regular),
        findsOneWidget,
      );

      await gesture.moveTo(const Offset(0, 0));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(FluentIcons.re_order_dots_vertical_24_regular),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a disabled plugin row is still draggable and shows the drag-reorder hint',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pluginBloc = _FakePluginSystemBloc([
        _plugin(id: 'p1', name: 'תוסף-A', enabled: false),
        _plugin(id: 'p2', name: 'תוסף-B'),
      ]);

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: pluginBloc,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Draggable<String>), findsNWidgets(2));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(() => gesture.removePointer());
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.text('תוסף-A')));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(FluentIcons.re_order_dots_vertical_24_regular),
        findsOneWidget,
      );

      final srcCenter = tester.getCenter(find.text('תוסף-A'));
      final dstCenter = tester.getCenter(find.text('תוסף-B'));
      await tester.timedDrag(
        find.text('תוסף-A'),
        Offset(0, dstCenter.dy - srcCenter.dy),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      final events = pluginBloc.dispatched
          .whereType<ReorderPluginsRequested>()
          .toList();
      expect(events, hasLength(1));
      expect(events.single.orderedPluginIds, orderedEquals(['p2', 'p1']));
    },
  );

  testWidgets(
    'tapping a plugin row (not a specific button) opens its permissions dialog',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(id: 'p1', name: 'תוסף-A'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('תוסף-A'));
      await tester.pumpAndSettle();

      expect(find.text('ניהול הרשאות: תוסף-A'), findsOneWidget);
    },
  );

  testWidgets(
    'a plugin row uses the default (non-suppressed) ListTile hover, like '
    'SettingsActionTile.switchTile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: _FakePluginSystemBloc([
            _plugin(id: 'p1', name: 'תוסף-A'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('תוסף-A'),
          matching: find.byType(ListTile),
        ),
      );
      // אין דיכוי ידני של ה-hover — הצבע מגיע מהתמה כברירת מחדל, בדיוק כמו
      // ב-SettingsActionTile.switchTile (ראו onTap שם, שגם הוא מפעיל את ה-hover).
      expect(tile.hoverColor, isNull);
      expect(tile.onTap, isNotNull);
    },
  );

  testWidgets(
    'startup button — tapping "טעינה רגילה" dispatches granted:false',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pluginBloc = _FakePluginSystemBloc([
        _plugin(
          id: 'p1',
          name: 'תוסף-A',
          permissions: const ['app.run_on_startup'],
          runOnStartupGranted: true,
        ),
      ]);

      await tester.pumpWidget(
        _wrap(
          settingsBloc: _FakeSettingsBloc(),
          pluginBloc: pluginBloc,
        ),
      );
      await tester.pumpAndSettle();
      await _enterSelectionMode(tester);
      await _selectPlugin(tester, 'תוסף-A');

      // כשהטעינה בעלייה מופעלת — הכפתור מציג "טעינה רגילה" ושולח granted:false
      await tester.tap(find.text('טעינה רגילה'));
      await tester.pumpAndSettle();

      final events = pluginBloc.dispatched
          .whereType<SetPluginPermissionRequested>()
          .where((e) => e.permission == 'app.run_on_startup')
          .toList();
      expect(events, hasLength(1));
      expect(events.single.granted, isFalse);
    },
  );

  testWidgets(
    'a pinned built-in tool shows the "הסר מסרגל הניווט" button',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsBloc = _FakeSettingsBloc(
        pinnedToNav: const {'builtin.calendar'},
      );

      await tester.pumpWidget(
        _wrap(
          settingsBloc: settingsBloc,
          pluginBloc: _FakePluginSystemBloc(const []),
        ),
      );
      await tester.pumpAndSettle();
      await _expandBuiltIn(tester);

      expect(find.text('לוח שנה'), findsOneWidget);
      expect(_rowButton('לוח שנה', 'הסר מסרגל הניווט'), findsOneWidget);
    },
  );

  testWidgets(
    'built-in tool row height stays constant across hidden/pinned states',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Future<double> measureCalendarRowHeight(_FakeSettingsBloc bloc) async {
        await tester.pumpWidget(
          _wrap(
            settingsBloc: bloc,
            pluginBloc: _FakePluginSystemBloc(const []),
          ),
        );
        await tester.pumpAndSettle();
        await _expandBuiltIn(tester);
        // flash notifier עשוי לפתוח את הסעיף אוטומטית לפני ה-tap ואז ה-tap סוגר אותו
        if (find.text(kBuiltInToolsCatalog[0].label).evaluate().isEmpty) {
          await _expandBuiltIn(tester);
        }
        // גובה שורת לוח-שנה = מרחק בין top של title שלה ל-top של title של הכלי הבא
        final calendarTop = tester
            .getTopLeft(find.text(kBuiltInToolsCatalog[0].label))
            .dy;
        final nextToolTop = tester
            .getTopLeft(find.text(kBuiltInToolsCatalog[1].label))
            .dy;
        return nextToolTop - calendarTop;
      }

      final noBadges = await measureCalendarRowHeight(_FakeSettingsBloc());
      final hiddenOnly = await measureCalendarRowHeight(
        _FakeSettingsBloc(hidden: const {'builtin.calendar'}),
      );
      final pinnedOnly = await measureCalendarRowHeight(
        _FakeSettingsBloc(pinnedToNav: const {'builtin.calendar'}),
      );
      final both = await measureCalendarRowHeight(
        _FakeSettingsBloc(
          hidden: const {'builtin.calendar'},
          pinnedToNav: const {'builtin.calendar'},
        ),
      );

      expect(
        hiddenOnly,
        noBadges,
        reason: '"מוסתר" badge must not change row height',
      );
      expect(
        pinnedOnly,
        noBadges,
        reason: '"בסרגל ניווט" badge must not change row height',
      );
      expect(
        both,
        noBadges,
        reason: 'both badges together must not change row height',
      );
    },
  );
}
