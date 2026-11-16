import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

import '../../support/golden_fonts.dart';

const _themes = [
  (
    name: 'light',
    seed: AppSeedColors.defaultLight,
    brightness: Brightness.light,
  ),
  (name: 'dark', seed: AppSeedColors.defaultDark, brightness: Brightness.dark),
  (name: 'white', seed: AppSeedColors.white, brightness: Brightness.light),
];

class _SearchPanel extends StatefulWidget {
  const _SearchPanel({
    this.presentation = NavPanelSearchPresentation.persistent,
  });

  final NavPanelSearchPresentation presentation;

  @override
  State<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<_SearchPanel> {
  final _controller = TextEditingController();
  final _host = NavPanelSearchHost();

  @override
  void dispose() {
    _controller.dispose();
    _host.dispose();
    super.dispose();
  }

  Widget _action() => AppIconButton(
    tooltip: 'הרחבה וכיווץ של הכותרות',
    icon: const Icon(FluentIcons.arrow_expand_all_24_regular),
    onPressed: () {},
  );

  @override
  Widget build(BuildContext context) => NavSidePanel(
    isOpen: true,
    autoHandleResponsiveVisibility: false,
    paneWidth: 320,
    onClose: () {},
    mainContent: const Center(child: Text('אזור הקריאה')),
    paneContent: NavPanelSearchScope(
      host: _host,
      child: NavPanelSearchSlot(
        index: 0,
        child: NavPanelCollapsibleSearch(
          presentation: widget.presentation,
          floatingActions: [_action()],
          delegate: NavPanelSearchDelegate(
            controller: _controller,
            hintText: 'איתור כותרת...',
            onClear: () {},
          ),
          child: NavTreeFocusGroup(
            child: ListView.builder(
              itemCount: 80,
              itemBuilder: (context, index) => index == 0
                  ? NavTreeHeader(
                      title: 'ספר בדיקה',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [_action(), const NavPanelSearchToggle()],
                      ),
                    )
                  : NavTreeGroupCard(
                      isGroupStart: index == 1,
                      isGroupEnd: index == 79,
                      child: NavTreeTile.category(
                        title: 'פרק $index — כותרת לדוגמה',
                        level: 0,
                        isSelected: index == 2,
                        onTap: () {},
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required Color seed,
  required Brightness brightness,
  required double width,
  NavPanelSearchPresentation presentation =
      NavPanelSearchPresentation.persistent,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final scheme = AppThemeData.createColorScheme(seed, brightness);
  final theme = brightness == Brightness.light
      ? AppThemeData.light(
          scheme,
          compactMenuMode: false,
          variant: AppThemeVariant.ofSeed(seed),
        )
      : AppThemeData.dark(scheme, compactMenuMode: false);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(1.3)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: Scaffold(body: _SearchPanel(presentation: presentation)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadGoldenFonts);

  for (final theme in _themes) {
    for (final width in [360.0, 1200.0]) {
      testWidgets(
        '${theme.name}, רוחב $width: שדה קבוע ופעולות נגישות ב־RTL ×1.3',
        (tester) async {
          await _pumpPanel(
            tester,
            seed: theme.seed,
            brightness: theme.brightness,
            width: width,
          );

          final field = find.byType(OtzariaSearchField);
          expect(field.hitTestable(), findsOneWidget);
          final fieldRect = tester.getRect(field);
          final listRect = tester.getRect(find.byType(ListView));
          expect(fieldRect.bottom, lessThanOrEqualTo(listRect.top));
          expect(fieldRect.left, greaterThanOrEqualTo(0));
          expect(fieldRect.right, lessThanOrEqualTo(width));
          expect(Directionality.of(tester.element(field)), TextDirection.rtl);
          expect(
            MediaQuery.textScalerOf(tester.element(field)).scale(10),
            closeTo(13, 0.01),
          );
          expect(tester.takeException(), isNull);

          await tester.drag(find.byType(ListView), const Offset(0, -1400));
          await tester.pumpAndSettle();
          expect(tester.getRect(field), fieldRect);
          expect(field.hitTestable(), findsOneWidget);
          expect(find.byType(NavTreeHeader), findsNothing);
          expect(
            find.byTooltip('הרחבה וכיווץ של הכותרות').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(goldenPlatform),
      );
    }
  }
}
