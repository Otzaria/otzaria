import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

void main() {
  // כפתור ה-"..." נבנה כ-BarButton שקורא את compactMenuMode מה-SettingsBloc.
  late _TestSettingsBloc settingsBloc;

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    settingsBloc = _TestSettingsBloc();
  });

  tearDown(() async {
    await settingsBloc.close();
  });

  Widget withSettings(Widget app) =>
      BlocProvider<SettingsBloc>.value(value: settingsBloc, child: app);

  testWidgets(
    'כשיש alwaysInMenu לא מציגים את כל הכפתורים אם עדיין צריך overflow',
    (tester) async {
      Widget buildAction(IconData icon, String tooltip) {
        return IconButton(
          onPressed: () {},
          icon: Icon(icon),
          tooltip: tooltip,
        );
      }

      final actions = [
        ActionButtonData(
          actionId: ToolbarActionId.plugin,
          widget: buildAction(OtzariaIcons.book_24_regular, 'ספר'),
          icon: OtzariaIcons.book_24_regular,
          tooltip: 'ספר',
          onPressed: () {},
        ),
        ActionButtonData(
          actionId: ToolbarActionId.search,
          widget: buildAction(OtzariaIcons.search_24_regular, 'חיפוש'),
          icon: OtzariaIcons.search_24_regular,
          tooltip: 'חיפוש',
          onPressed: () {},
        ),
        ActionButtonData(
          actionId: ToolbarActionId.viewMode,
          widget: buildAction(FluentIcons.settings_24_regular, 'הגדרות'),
          icon: FluentIcons.settings_24_regular,
          tooltip: 'הגדרות',
          onPressed: () {},
        ),
      ];

      final alwaysInMenu = [
        ActionButtonData(
          actionId: ToolbarActionId.openCommentatorsTab,
          widget: buildAction(FluentIcons.more_horizontal_24_regular, 'נוסף'),
          icon: FluentIcons.more_horizontal_24_regular,
          tooltip: 'נוסף',
          onPressed: () {},
        ),
      ];

      await tester.pumpWidget(
        withSettings(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                appBar: AppBar(
                  actions: [
                    ResponsiveActionBar(
                      actions: actions,
                      alwaysInMenu: alwaysInMenu,
                      maxVisibleButtons: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(FluentIcons.more_vertical_24_regular), findsOneWidget);
      expect(find.byIcon(OtzariaIcons.book_24_regular), findsNothing);
      expect(find.byIcon(OtzariaIcons.search_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.settings_24_regular), findsOneWidget);
    },
  );

  group('menuHeaderActions — שורת ניווט בראש תפריט ה-"..."', () {
    const overflowIcon = FluentIcons.more_vertical_24_regular;

    final navIcons = <String, IconData>{
      'הדף/פרק הקודם': FluentIcons.arrow_previous_24_filled,
      'הקטע הקודם': FluentIcons.chevron_left_24_regular,
      'הקטע הבא': FluentIcons.chevron_right_24_regular,
      'הדף/פרק הבא': FluentIcons.arrow_next_24_filled,
    };

    ActionButtonData action(
      IconData icon,
      String tooltip, {
      VoidCallback? onPressed,
      bool enabled = true,
    }) {
      return ActionButtonData(
        actionId: ToolbarActionId.plugin,
        widget: IconButton(
          onPressed: () {},
          icon: Icon(icon),
          tooltip: tooltip,
        ),
        icon: icon,
        tooltip: tooltip,
        onPressed: enabled ? (onPressed ?? () {}) : null,
      );
    }

    List<ActionButtonData> navActions({void Function(String)? onPressed}) {
      return [
        for (final entry in navIcons.entries)
          action(
            entry.value,
            entry.key,
            onPressed: onPressed == null ? null : () => onPressed(entry.key),
          ),
      ];
    }

    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    );

    Future<void> pumpBar(
      WidgetTester tester, {
      List<ActionButtonData> actions = const [],
      List<ActionButtonData> alwaysInMenu = const [],
      List<ActionButtonData>? menuHeaderActions,
      List<ActionButtonData>? originalOrder,
      int maxVisibleButtons = 0,
      Size surfaceSize = const Size(800, 600),
    }) async {
      tester.view.physicalSize = surfaceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // אותה הגדרת locale כמו ב-app.dart: ה-RTL חייב לחול גם על ה-Overlay
      // שבו נפתח התפריט, לא רק על עץ המסך.
      await tester.pumpWidget(
        withSettings(
          MaterialApp(
            theme: theme,
            localizationsDelegates: const [
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('he', 'IL')],
            locale: const Locale('he', 'IL'),
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  ResponsiveActionBar(
                    actions: actions,
                    alwaysInMenu: originalOrder == null ? alwaysInMenu : null,
                    originalOrder: originalOrder,
                    menuHeaderActions: menuHeaderActions,
                    maxVisibleButtons: maxVisibleButtons,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(overflowIcon));
      await tester.pumpAndSettle();
    }

    /// הצבע שהאייקון נצבע בו בפועל — אחרי סגנון הכפתור ואחרי opacity שירש
    /// מ-IconTheme (הערך שהועבר כ-color לא משקף את שניהם).
    Color? glyphColor(WidgetTester tester, String tooltip) {
      final glyph = tester.widget<RichText>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(RichText),
        ),
      );
      return glyph.text.style?.color;
    }

    IconData? glyphIcon(WidgetTester tester, String tooltip) {
      final glyph = tester.widget<Icon>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(Icon),
        ),
      );
      return glyph.icon;
    }

    testWidgets('כל פעולות הניווט מוצגות ככפתורי אייקון עם tooltip', (
      tester,
    ) async {
      await pumpBar(tester, menuHeaderActions: navActions(onPressed: (_) {}));
      await openMenu(tester);

      for (final entry in navIcons.entries) {
        expect(find.byTooltip(entry.key), findsOneWidget);
        expect(
          find.descendant(
            of: find.byTooltip(entry.key),
            matching: find.byType(Icon),
          ),
          findsOneWidget,
        );
        // לא שורת טקסט לכל פעולה — זו הבעיה שהשורה באה לפתור
        expect(find.text(entry.key), findsNothing);
      }
    });

    testWidgets('ארבעת הכפתורים באותה שורה — גובה של שורה אחת', (tester) async {
      await pumpBar(tester, menuHeaderActions: navActions(onPressed: (_) {}));
      await openMenu(tester);

      final rects = navIcons.keys
          .map((tooltip) => tester.getRect(find.byTooltip(tooltip)))
          .toList();

      for (final rect in rects) {
        expect(rect.top, closeTo(rects.first.top, 0.5));
        expect(rect.height, closeTo(rects.first.height, 0.5));
        expect(rect.height, lessThanOrEqualTo(48));
      }
    });

    testWidgets('סדר הכפתורים ב-RTL זהה לסדר בסרגל הרגיל', (tester) async {
      await pumpBar(tester, menuHeaderActions: navActions(onPressed: (_) {}));
      await openMenu(tester);

      // "הדף/פרק הקודם" ימני ביותר, "הדף/פרק הבא" שמאלי ביותר
      final centers = navIcons.keys
          .map((tooltip) => tester.getCenter(find.byTooltip(tooltip)).dx)
          .toList();
      for (var i = 1; i < centers.length; i++) {
        expect(centers[i], lessThan(centers[i - 1]));
      }
    });

    testWidgets('חצי הניווט נשארים כמו בסרגל הרגיל — היפוך יחיד ב-RTL', (
      tester,
    ) async {
      await pumpBar(tester, menuHeaderActions: navActions(onPressed: (_) {}));
      await openMenu(tester);

      // לאייקוני Fluent יש matchTextDirection:true — Icon כבר מהפך אותם ב-RTL.
      // החלפה נוספת ל-IconData הנגדי מהפכת פעמיים ומחזירה לכיוון LTR.
      for (final entry in navIcons.entries) {
        expect(glyphIcon(tester, entry.key), entry.value);
        expect(entry.value.matchTextDirection, isTrue);
      }
    });

    testWidgets('השורה מופיעה מעל שאר פריטי התפריט', (tester) async {
      await pumpBar(
        tester,
        alwaysInMenu: [action(FluentIcons.print_24_regular, 'הדפסה')],
        menuHeaderActions: navActions(onPressed: (_) {}),
      );
      await openMenu(tester);

      expect(
        tester.getCenter(find.byTooltip('הקטע הבא')).dy,
        lessThan(tester.getCenter(find.text('הדפסה')).dy),
      );
    });

    testWidgets('מפריד בין השורה לשאר הפריטים', (tester) async {
      await pumpBar(
        tester,
        alwaysInMenu: [action(FluentIcons.print_24_regular, 'הדפסה')],
        menuHeaderActions: navActions(onPressed: (_) {}),
      );
      await openMenu(tester);

      expect(find.byType(PopupMenuDivider), findsOneWidget);
      final dividerY = tester.getCenter(find.byType(PopupMenuDivider)).dy;
      expect(
        tester.getCenter(find.byTooltip('הקטע הבא')).dy,
        lessThan(dividerY),
      );
      expect(tester.getCenter(find.text('הדפסה')).dy, greaterThan(dividerY));
    });

    testWidgets('בלי פריטים נוספים אין מפריד מיותר', (tester) async {
      await pumpBar(tester, menuHeaderActions: navActions(onPressed: (_) {}));
      await openMenu(tester);

      expect(find.byType(PopupMenuDivider), findsNothing);
    });

    testWidgets('התפריט נשאר פתוח בלחיצה — כדי לעבור כמה קטעים', (
      tester,
    ) async {
      final pressed = <String>[];
      await pumpBar(
        tester,
        menuHeaderActions: navActions(onPressed: pressed.add),
      );
      await openMenu(tester);

      await tester.tap(find.byTooltip('הקטע הבא'));
      await tester.pumpAndSettle();

      expect(pressed, ['הקטע הבא']);
      expect(find.byTooltip('הקטע הבא'), findsOneWidget);
    });

    testWidgets('לחיצות חוזרות מפעילות את הפעולה בכל פעם', (tester) async {
      final pressed = <String>[];
      await pumpBar(
        tester,
        menuHeaderActions: navActions(onPressed: pressed.add),
      );
      await openMenu(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('הקטע הבא'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('הדף/פרק הקודם'));
      await tester.pumpAndSettle();

      expect(pressed, [
        'הקטע הבא',
        'הקטע הבא',
        'הקטע הבא',
        'הדף/פרק הקודם',
      ]);
      expect(find.byTooltip('הקטע הבא'), findsOneWidget);
    });

    testWidgets('לחיצה על פריט תפריט רגיל כן סוגרת את התפריט', (tester) async {
      var printed = 0;
      await pumpBar(
        tester,
        alwaysInMenu: [
          action(
            FluentIcons.print_24_regular,
            'הדפסה',
            onPressed: () => printed++,
          ),
        ],
        menuHeaderActions: navActions(onPressed: (_) {}),
      );
      await openMenu(tester);

      await tester.tap(find.text('הדפסה'));
      await tester.pumpAndSettle();

      expect(printed, 1);
      expect(find.byTooltip('הקטע הבא'), findsNothing);
    });

    testWidgets('לחיצה על הרווח שבין הכפתורים לא סוגרת את התפריט', (
      tester,
    ) async {
      final pressed = <String>[];
      await pumpBar(
        tester,
        alwaysInMenu: [
          action(FluentIcons.print_24_regular, 'הדפסה ארוכה במיוחד לרוחב'),
        ],
        menuHeaderActions: navActions(onPressed: pressed.add),
      );
      await openMenu(tester);

      final first = tester.getRect(find.byTooltip('הקטע הבא'));
      final second = tester.getRect(find.byTooltip('הקטע הקודם'));
      final gapCenter = Offset(
        (first.right + second.left) / 2,
        first.center.dy,
      );

      await tester.tapAt(gapCenter);
      await tester.pumpAndSettle();

      expect(pressed, isEmpty);
      expect(find.byTooltip('הקטע הבא'), findsOneWidget);
    });

    testWidgets('הכפתורים מרווחים על רוחב התפריט', (tester) async {
      await pumpBar(
        tester,
        alwaysInMenu: [
          action(FluentIcons.print_24_regular, 'הדפסה ארוכה במיוחד לרוחב'),
        ],
        menuHeaderActions: navActions(onPressed: (_) {}),
      );
      await openMenu(tester);

      final menuWidth = tester.getRect(find.byType(PopupMenuDivider)).width;
      final rects = navIcons.keys
          .map((tooltip) => tester.getRect(find.byTooltip(tooltip)))
          .toList();
      final spread = (rects.first.center.dx - rects.last.center.dx).abs();

      // לא צמודים במרכז — פרוסים על רוב רוחב התפריט, עם רווח בין כפתורים
      expect(spread, greaterThan(menuWidth * 0.5));
      for (var i = 1; i < rects.length; i++) {
        final gap = (rects[i - 1].left - rects[i].right).abs();
        expect(gap, greaterThan(0));
      }
    });

    testWidgets('האייקון לא מעומעם ובאותו צבע כמו טקסט של פריט רגיל', (
      tester,
    ) async {
      await pumpBar(
        tester,
        alwaysInMenu: [action(FluentIcons.print_24_regular, 'הדפסה')],
        menuHeaderActions: navActions(onPressed: (_) {}),
      );
      await openMenu(tester);

      // הצבע שנצבע בפועל — כולל opacity של IconTheme, שפריט תפריט מושבת מחיל
      expect(glyphColor(tester, 'הקטע הבא'), theme.colorScheme.onSurface);
      expect(
        glyphColor(tester, 'הקטע הבא'),
        isNot(theme.colorScheme.onSurfaceVariant),
      );

      // ואותו צבע כמו טקסט פריט תפריט רגיל
      final itemText = tester.widget<Text>(find.text('הדפסה'));
      final itemColor =
          itemText.style?.color ??
          DefaultTextStyle.of(tester.element(find.text('הדפסה'))).style.color;
      expect(itemColor, theme.colorScheme.onSurface);
    });

    testWidgets('פעולה מושבתת מוצגת מעומעמת ולא מגיבה ללחיצה', (tester) async {
      final pressed = <String>[];
      await pumpBar(
        tester,
        menuHeaderActions: [
          action(FluentIcons.chevron_left_24_regular, 'הקטע הקודם'),
          action(
            FluentIcons.chevron_right_24_regular,
            'הקטע הבא',
            enabled: false,
          ),
        ],
      );
      await openMenu(tester);

      expect(
        glyphColor(tester, 'הקטע הבא'),
        isNot(glyphColor(tester, 'הקטע הקודם')),
      );
      expect(glyphColor(tester, 'הקטע הקודם'), theme.colorScheme.onSurface);

      await tester.tap(find.byTooltip('הקטע הבא'));
      await tester.pumpAndSettle();

      expect(pressed, isEmpty);
      expect(find.byTooltip('הקטע הבא'), findsOneWidget);
    });

    testWidgets('כל כפתור הוא צומת סמנטי נפרד, מאופשר ולחיץ', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBar(
        tester,
        alwaysInMenu: [action(FluentIcons.print_24_regular, 'הדפסה')],
        menuHeaderActions: navActions(onPressed: (_) {}),
      );
      await openMenu(tester);

      final seen = <int>{};
      for (final tooltip in navIcons.keys) {
        final node = tester.getSemantics(find.byTooltip(tooltip));
        final data = node.getSemanticsData();
        expect('${data.label}${data.tooltip}', contains(tooltip));
        expect(
          data.flagsCollection.isButton,
          isTrue,
          reason: 'הכפתור $tooltip לא מוכרז ככפתור',
        );
        expect(
          data.flagsCollection.isEnabled,
          Tristate.isTrue,
          reason: 'הכפתור $tooltip הוכרז כמושבת',
        );
        expect(
          data.hasAction(SemanticsAction.tap),
          isTrue,
          reason: 'הכפתור $tooltip אינו לחיץ מקורא מסך',
        );
        // צומת נפרד לכל כפתור — לא מוזגו לפריט תפריט אחד
        expect(seen.add(node.id), isTrue);
      }
      handle.dispose();
    });

    testWidgets('גובה השורה שנרנדר תואם לגובה שהתפריט מסתמך עליו', (
      tester,
    ) async {
      await pumpBar(
        tester,
        alwaysInMenu: [action(FluentIcons.print_24_regular, 'הדפסה')],
        menuHeaderActions: navActions(onPressed: (_) {}),
      );
      await openMenu(tester);

      // showAnchoredAppMenu מחשב את גובה התפריט מסכום item.height — פער בין
      // הגובה המדווח למרונדר שובר את בחירת כיוון הפתיחה
      final rowFinder = find.byType(AppMenuRowEntry<ActionButtonData>);
      final entry = tester.widget<AppMenuRowEntry<ActionButtonData>>(rowFinder);
      expect(tester.getSize(rowFinder).height, entry.height);
    });

    testWidgets('אין גלישה במסך צר או בהגדלת טקסט', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        withSettings(
          MaterialApp(
            theme: theme,
            localizationsDelegates: const [
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('he', 'IL')],
            locale: const Locale('he', 'IL'),
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: 2,
              maxScaleFactor: 2,
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  ResponsiveActionBar(
                    actions: const [],
                    alwaysInMenu: [
                      action(FluentIcons.print_24_regular, 'הדפסה'),
                    ],
                    menuHeaderActions: navActions(onPressed: (_) {}),
                    maxVisibleButtons: 0,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await openMenu(tester);

      expect(tester.takeException(), isNull);
      for (final tooltip in navIcons.keys) {
        expect(find.byTooltip(tooltip), findsOneWidget);
      }
    });

    testWidgets('כפתור ה-"..." מוצג גם כשהשורה היא התוכן היחיד', (
      tester,
    ) async {
      await pumpBar(tester, menuHeaderActions: navActions(onPressed: (_) {}));

      expect(find.byIcon(overflowIcon), findsOneWidget);
    });

    testWidgets('בלי פעולות בכלל לא מוצג כפתור "..."', (tester) async {
      await pumpBar(tester, menuHeaderActions: const []);

      expect(find.byIcon(overflowIcon), findsNothing);
    });

    testWidgets('השורה מוצגת גם במצב הישן (originalOrder)', (tester) async {
      final visible = [action(OtzariaIcons.search_24_regular, 'חיפוש')];
      await pumpBar(
        tester,
        actions: visible,
        originalOrder: visible,
        menuHeaderActions: navActions(onPressed: (_) {}),
        maxVisibleButtons: 1,
      );
      await openMenu(tester);

      expect(find.byTooltip('הקטע הבא'), findsOneWidget);
      expect(find.byType(PopupMenuDivider), findsNothing);
    });

    testWidgets('כפתורי הסרגל הגלויים לא מושפעים מהשורה שבתפריט', (
      tester,
    ) async {
      await pumpBar(
        tester,
        actions: [
          action(OtzariaIcons.search_24_regular, 'חיפוש'),
          action(FluentIcons.settings_24_regular, 'הגדרות'),
        ],
        menuHeaderActions: navActions(onPressed: (_) {}),
        maxVisibleButtons: 2,
      );

      expect(find.byIcon(OtzariaIcons.search_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.settings_24_regular), findsOneWidget);
      // אייקוני הניווט מופיעים רק אחרי פתיחת התפריט
      expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);
    });
  });
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      (_values[key] as bool?) ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      (_values[key] as double?) ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      (_values[key] as int?) ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      (_values[key] as String?) ?? defaultValue;

  @override
  Set<Object?> getKeys() => _values.keys.toSet();

  @override
  T? getValue<T>(String key, {T? defaultValue}) =>
      (_values[key] as T?) ?? defaultValue;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}
