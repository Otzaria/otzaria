import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/view/reading_tabs_side_panel.dart';
import 'package:otzaria/navigation/view/vertical_reading_tab_strip.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';

import 'helpers/memory_settings_cache.dart';

const _output = String.fromEnvironment(
  'SCREENSHOT_OUTPUT',
  defaultValue: 'build/qa4092',
);
const _canvas = Size(1200, 780);
const _readerKey = ValueKey('sample-reader');
final _captureKey = GlobalKey();
final _captures = <Map<String, Object?>>[];

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    // The headless app runner permits system fallback; aliases make UI fonts stable.
    for (final family in [
      'Ubuntu',
      'Arial',
      'Roboto',
      'Rubik',
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'))).load();
    }
    await (FontLoader('FrankRuhlCLM')
          ..addFont(rootBundle.load('fonts/FrankRuehlCLM-Medium.ttf'))
          ..addFont(rootBundle.load('fonts/FrankRuehlCLM-Bold.ttf')))
        .load();
    for (final style in ['Regular', 'Filled']) {
      await (FontLoader(
            'packages/fluentui_system_icons/FluentSystemIcons-$style',
          )..addFont(
            rootBundle.load(
              'packages/fluentui_system_icons/fonts/FluentSystemIcons-$style.ttf',
            ),
          ))
          .load();
    }
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('capture production panel: ${brightness.name}', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      debugDisableShadows = false;
      tester.view.devicePixelRatio = 1;
      await tester.binding.setSurfaceSize(_canvas);
      final settings = await _pumpPreview(tester, brightness);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final collapsedRect = tester.getRect(find.byKey(_readerKey));

      try {
        if (brightness == Brightness.light) {
          await _capture(tester, '01-collapsed.png', 'collapsed', brightness);
        }
        final strip = tester.getRect(find.byType(VerticalReadingTabStrip));
        await mouse.addPointer(
          location: strip.topRight + const Offset(-24, 20),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(tester.getRect(find.byKey(_readerKey)), collapsedRect);
        expect(settings.events, isEmpty);
        expect(
          tester.getSize(find.byType(VerticalReadingTabStrip)).width,
          260,
        );
        await _capture(
          tester,
          brightness == Brightness.light
              ? '02-hover-floating.png'
              : '04-hover-floating-dark.png',
          'hover-floating',
          brightness,
        );

        if (brightness == Brightness.light) {
          final pin = tester.getCenter(
            find.byTooltip('הרחב את עמודת הכרטיסיות'),
          );
          await mouse.moveTo(pin);
          await mouse.down(pin);
          await mouse.up();
          await tester.pumpAndSettle();
          await mouse.moveTo(const Offset(40, 720));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pumpAndSettle();
          expect(settings.state.readingTabsColumnCollapsed, isFalse);
          expect(tester.getRect(find.byKey(_readerKey)).width, 940);
          await _capture(tester, '03-pinned.png', 'pinned', brightness);
        }
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        tester.view.resetDevicePixelRatio();
        await tester.binding.setSurfaceSize(null);
        debugDisableShadows = true;
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  tearDownAll(() async {
    final metadata = {
      'issue': 'https://github.com/Otzaria/otzaria/issues/4092',
      'captureType':
          'Flutter headless app runner with widget-test API; RenderRepaintBoundary capture',
      'runCommand':
          'FLUTTER_SUPPRESS_ANALYTICS=true flutter --suppress-analytics --no-version-check run --no-pub --no-track-widget-creation -d flutter-tester -t test/_capture_4092_test.dart --dart-define=SCREENSHOT_OUTPUT=$_output',
      'flutterVersion': '3.47.7',
      'dartVersion': '3.13.5',
      'productionWidget':
          'ReadingTabsSidePanel and its real vertical tab strip',
      'fullApplicationScreenshot': false,
      'hostPlatform': Platform.operatingSystem,
      'themePlatform': 'windows',
      'readerContent': 'Neutral sample document; no personal data',
      'theme': 'AppThemeData light/dark with each default AppSeedColors seed',
      'fonts': {
        'ui':
            'Bundled Rubik loaded as Roboto and host default font-family aliases; normal Linux font fallback enabled for unspecified families',
        'reader': 'Bundled FrankRuhlCLM',
        'icons': 'Actual FluentSystemIcons Regular and Filled assets',
      },
      'verified': [
        'Reader Rect is exactly equal before and after hover in both themes',
        'Hover emits no settings event',
        'Persistent expansion is activated through the actual header button',
      ],
      'captures': _captures,
    };
    await Directory(_output).create(recursive: true);
    await File('$_output/capture-metadata.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  });
}

Future<_PreviewSettingsBloc> _pumpPreview(
  WidgetTester tester,
  Brightness brightness,
) async {
  final tabs = _PreviewTabsBloc(
    TabsState(
      currentTabIndex: 0,
      tabs: [
        for (final title in [
          'מסמך לדוגמה',
          'מקורות ועיונים',
          'מפתח מושגים',
          'פרק ראשון',
          'הערות לקריאה',
          'תוכן העניינים',
          'סיכום הפרק',
          'מראי מקומות',
          'פרק שני',
          'השוואת נוסחים',
          'שאלות לעיון',
          'הרחבות וביאורים',
          'תוספת א',
          'תוספת ב',
          'לקט מקורות',
          'פרק שלישי',
          'רשימת נושאים',
          'נספח לדוגמה',
        ])
          _PreviewTab(title),
      ],
    ),
  );
  final settings = _PreviewSettingsBloc(
    SettingsState.initial().copyWith(
      readingTabsPlacement: SettingsRepository.readingTabsPlacementSide,
      readingTabsColumnCollapsed: true,
      readingTabsColumnWidth: 260,
    ),
  );
  final history = _PreviewHistoryBloc();
  final workspaces = _PreviewWorkspaceBloc();
  addTearDown(() async {
    await tabs.close();
    await settings.close();
    await history.close();
    await workspaces.close();
  });
  final scheme = AppThemeData.createColorScheme(
    brightness == Brightness.light
        ? AppSeedColors.defaultLight
        : AppSeedColors.defaultDark,
    brightness,
  );
  final theme = brightness == Brightness.light
      ? AppThemeData.light(scheme, compactMenuMode: false)
      : AppThemeData.dark(scheme, compactMenuMode: false);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TabsBloc>.value(value: tabs),
        BlocProvider<SettingsBloc>.value(value: settings),
        BlocProvider<HistoryBloc>.value(value: history),
        BlocProvider<WorkspaceBloc>.value(value: workspaces),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: RepaintBoundary(
            key: _captureKey,
            child: Scaffold(
              body: Column(
                children: [
                  Builder(
                    builder: (context) => ColoredBox(
                      color: AppSurfaces.topBarBackground(context),
                      child: const SizedBox(
                        height: 44,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18),
                          child: Row(
                            children: [
                              Icon(FluentIcons.book_open_24_regular, size: 21),
                              SizedBox(width: 10),
                              Text('אוצריא', style: TextStyle(fontSize: 18)),
                              Spacer(),
                              Text(
                                'תצוגת הדגמה · עמודת כרטיסיות',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Expanded(
                    child: ReadingTabsSidePanel(
                      show: true,
                      child: _SampleReader(key: _readerKey),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

Future<void> _capture(
  WidgetTester tester,
  String file,
  String state,
  Brightness brightness,
) async {
  final rect = tester.getRect(find.byKey(_readerKey));
  final boundary =
      _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await Directory(_output).create(recursive: true);
    await File('$_output/$file').writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
  _captures.add({
    'file': file,
    'state': state,
    'brightness': brightness.name,
    'size': [_canvas.width, _canvas.height],
    'readerRect': [rect.left, rect.top, rect.width, rect.height],
  });
}

class _SampleReader extends StatelessWidget {
  const _SampleReader({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: AppSurfaces.readerBackground(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 17),
            child: Row(
              children: [
                Icon(
                  FluentIcons.text_align_justify_24_regular,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                const Text('מסמך לדוגמה', style: TextStyle(fontSize: 16)),
                const Spacer(),
                Text(
                  'פרק ראשון',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 20),
                const Icon(FluentIcons.search_24_regular, size: 19),
                const SizedBox(width: 18),
                const Icon(FluentIcons.more_horizontal_24_regular, size: 20),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(64, 42, 64, 24),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontFamily: 'FrankRuhlCLM',
                  color: cs.onSurface,
                  fontSize: 24,
                  height: 1.65,
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'מסמך לדוגמה',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      'פרק ראשון',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 21),
                    ),
                    SizedBox(height: 30),
                    Text(
                      'א. פתיחה',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'זהו מסמך לדוגמה שנועד להציג את אזור הקריאה. הטקסט מסודר '
                      'בפסקאות ברורות, עם שוליים רחבים וכותרות קצרות. אפשר לקרוא '
                      'ברצף, לעבור בין הפרקים ולשוב אל המקום שבו הופסק העיון.',
                    ),
                    SizedBox(height: 24),
                    Text(
                      'ב. עיון וקריאה',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'לצד המסמך פתוחים מקורות נוספים, הערות ומפתח מושגים. '
                      'כל כרטיסייה מייצגת מסמך אחר בסביבת העבודה. תוכן הדוגמה '
                      'אינו כולל מידע אישי או מסמכים של משתמשים.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Row(
              children: [
                Text(
                  'תוכן לדוגמה',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  'עמוד 1 מתוך 6',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewTab extends OpenedTab {
  _PreviewTab(super.title);
  @override
  OpenedTab clone() => _PreviewTab(title);
  @override
  Map<String, dynamic> toJson() => {'type': 'preview', 'title': title};
}

class _PreviewTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _PreviewTabsBloc(super.initialState);
  @override
  void add(TabsEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewSettingsBloc extends Cubit<SettingsState>
    implements SettingsBloc {
  _PreviewSettingsBloc(super.initialState);
  final events = <SettingsEvent>[];
  @override
  void add(SettingsEvent event) {
    events.add(event);
    if (event is UpdateReadingTabsColumnCollapsed) {
      emit(state.copyWith(readingTabsColumnCollapsed: event.collapsed));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _PreviewHistoryBloc() : super(HistoryInitial());
  @override
  void add(HistoryEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewWorkspaceBloc extends Cubit<WorkspaceState>
    implements WorkspaceBloc {
  _PreviewWorkspaceBloc() : super(WorkspaceState.initial());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
