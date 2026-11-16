import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/golden_fonts.dart';
import '../../test_helpers/stub_settings_bloc.dart';

class _PanelLink extends Link {
  _PanelLink(String type, int index)
    : super(
        heRef: 'הפניה $index',
        index1: index,
        path2: 'ספר $index',
        index2: 1,
        connectionType: type,
      );

  @override
  Future<String> get content async => 'תוכן הקישור נשאר זמין מתחת למסננים.';
  @override
  Future<String> get displayReference async => fallbackDisplayReference;
}

final _links = [
  for (final (index, type) in [
    LinkTypes.source,
    LinkTypes.einMishpat,
    LinkTypes.sifreiMitzvot,
    LinkTypes.mesoratHashas,
    LinkTypes.mishnahInTalmud,
    LinkTypes.quotation,
    LinkTypes.law,
    LinkTypes.liturgy,
    LinkTypes.summary,
    LinkTypes.footnotes,
    LinkTypes.allusion,
    LinkTypes.altToc,
  ].indexed)
    _PanelLink(type, index),
];

const _captureKey = Key('links-panel-capture');

Future<ValueNotifier<Set<String>>> _pumpPanel(
  WidgetTester tester, {
  required double width,
  required double scale,
  String themeName = 'light',
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = StubSettingsBloc(
    SettingsState.initial().copyWith(commentatorsFontFamily: 'FrankRuhlCLM'),
  );
  final selected = ValueNotifier<Set<String>>({});
  addTearDown(settings.close);
  addTearDown(selected.dispose);
  CommentaryService.seedEraCache({
    for (final link in _links) link.path2: CommentaryEra.acharonim,
  });
  addTearDown(CommentaryService.clearEraCache);
  final dark = themeName == 'dark';
  final scheme = AppThemeData.createColorScheme(
    themeName == 'white' ? AppSeedColors.white : AppSeedColors.defaultLight,
    dark ? Brightness.dark : Brightness.light,
  );
  final theme = dark
      ? AppThemeData.dark(scheme, compactMenuMode: false)
      : AppThemeData.light(
          scheme,
          compactMenuMode: false,
          variant: themeName == 'white'
              ? AppThemeVariant.white
              : AppThemeVariant.standard,
        );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: BlocProvider<SettingsBloc>.value(
            value: settings,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  height: 320,
                  child: RepaintBoundary(
                    key: _captureKey,
                    child: Material(
                      color: scheme.surface,
                      child: ValueListenableBuilder<Set<String>>(
                        valueListenable: selected,
                        builder: (context, types, _) => LinksListView(
                          links: _links,
                          chipSourceLinks: _links,
                          openBookTitle: 'שבת',
                          selectedLinkTypes: types,
                          onSelectedLinkTypesChanged: (types) =>
                              selected.value = types,
                          openBookCallback: (_) {},
                          fontSize: 16,
                          displayProfile: TextDisplayProfile.defaults,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return selected;
}

void main() {
  final screenshot = Platform.environment['ISSUE4940_SCREENSHOT'];
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
    await loadGoldenFonts();
    await (FontLoader(
      'FrankRuhlCLM',
    )..addFont(rootBundle.load('fonts/FrankRuehlCLM-Medium.ttf'))).load();
  });

  for (final theme in ['light', 'dark', 'white']) {
    for (final width in [360.0, 1100.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          'מסננים מוגבלים לחלונית ונשמרים בהסתרה: $theme/$width/$scale',
          (tester) async {
            final selected = await _pumpPanel(
              tester,
              width: width,
              scale: scale,
              themeName: theme,
            );
            expect(tester.takeException(), isNull);
            final filters = find.descendant(
              of: find.byType(LinksListView),
              matching: find.byType(SingleChildScrollView),
            );
            expect(
              tester.getSize(filters).height,
              lessThanOrEqualTo(320 * 0.3),
            );
            final before = tester.getSize(find.byType(ExpansionTile).first);
            expect(before.height, greaterThan(0));
            expect(
              find.descendant(
                of: find.byType(AppIconButton),
                matching: find.byTooltip('הסתר מסננים'),
              ),
              findsOneWidget,
            );
            await tester.tap(find.text('מקור'));
            await tester.pumpAndSettle();
            expect(selected.value, {LinkTypes.source});
            await tester.tap(find.byTooltip('הסתר מסננים'));
            await tester.pumpAndSettle();
            expect(find.byType(FilterChipsSelector<String>), findsNothing);
            expect(find.byType(ExpansionTile), findsOneWidget);
            expect(selected.value, {LinkTypes.source});
            await tester.tap(find.byTooltip('הצג מסננים'));
            await tester.pumpAndSettle();
            expect(find.byType(FilterChipsSelector<String>), findsWidgets);
            expect(selected.value, {LinkTypes.source});
            expect(tester.takeException(), isNull);
          },
          variant: TargetPlatformVariant.only(TargetPlatform.windows),
        );
      }
    }
  }

  testWidgets(
    'צילום חלונית הקישורים האמיתית',
    (tester) async {
      await _pumpPanel(tester, width: 360, scale: 1.3);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('docs/screenshots/issue-4940/$screenshot.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    },
    skip: screenshot == null,
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
