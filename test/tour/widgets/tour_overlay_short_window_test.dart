import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/view/tour_overlay_screen.dart';
import 'package:otzaria/tour/widgets/tour_tooltip_card.dart';

import '../../design_system/contracts/contract_harness.dart';
import '../../helpers/memory_settings_cache.dart';
import '../../support/golden_fonts.dart';

void main() {
  setUpAll(loadGoldenFonts);
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  void testTourWidgets(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<TourCubit> pumpTour(
    WidgetTester tester, {
    required Size size,
    required SettingsLanguage language,
    required bool libraryLoaded,
    double scale = 1.3,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = TourCubit()..start(libraryLoaded: libraryLoaded);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? appTheme(Brightness.light),
        home: SettingsTextScope(
          language: language,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: BlocProvider.value(
              value: cubit,
              child: Scaffold(
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    TourOverlayScreen(
                      onStepChanged: (_) {},
                      targetRectResolver: (_) =>
                          const Rect.fromLTWH(24, 40, 120, 48),
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
    return cubit;
  }

  void expectButtonsInside(WidgetTester tester, Size size) {
    final buttons = find.byWidgetPredicate(
      (widget) => widget is ButtonStyleButton,
    );
    expect(buttons, findsWidgets);
    for (final element in buttons.evaluate()) {
      final finder = find.byWidget(element.widget);
      final rect = tester.getRect(finder);
      expect(rect.top, greaterThanOrEqualTo(20));
      expect(rect.bottom, lessThanOrEqualTo(size.height - 20));
      expect(finder.hitTestable(), findsOneWidget);
    }
  }

  Finder bodyScroll() => find.descendant(
    of: find.byType(TourTooltipCard),
    matching: find.byType(SingleChildScrollView),
  );

  ScrollPosition bodyPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: bodyScroll(), matching: find.byType(Scrollable)),
      )
      .position;

  Future<void> removeTour(WidgetTester tester, TourCubit cubit) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  }

  testTourWidgets(
    'welcome keeps both actions visible in a short supported window',
    (tester) async {
      const size = Size(420, 500);
      final cubit = await pumpTour(
        tester,
        size: size,
        language: SettingsLanguage.english,
        libraryLoaded: false,
      );
      expect(tester.takeException(), isNull);
      expectButtonsInside(tester, size);
      await tester.tap(find.text("Let's Begin"));
      await tester.pumpAndSettle();
      expect(cubit.state.currentStep!.id, 'empty_library');
      await removeTour(tester, cubit);
    },
  );

  testTourWidgets(
    'welcome body scrolls while actions stay fixed across window and language variants',
    (tester) async {
      final themes = [
        appTheme(Brightness.light),
        appTheme(Brightness.dark),
        AppThemeData.light(
          AppThemeData.createColorScheme(AppSeedColors.white, Brightness.light),
          compactMenuMode: false,
        ),
      ];
      for (final theme in themes) {
        for (final size in [
          const Size(420, 400),
          const Size(420, 500),
          const Size(360, 640),
          const Size(800, 800),
        ]) {
          for (final language in SettingsLanguage.values) {
            for (final loaded in [false, true]) {
              for (final scale in [1.0, 1.3]) {
                final cubit = await pumpTour(
                  tester,
                  size: size,
                  language: language,
                  libraryLoaded: loaded,
                  scale: scale,
                  theme: theme,
                );
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '$size ${language.name} loaded=$loaded scale=$scale',
                );
                expectButtonsInside(tester, size);
                final before = tester.getRect(
                  find.byWidgetPredicate((w) => w is ButtonStyleButton).first,
                );
                final position = bodyPosition(tester);
                if (size == const Size(800, 800)) {
                  expect(position.maxScrollExtent, 0);
                }
                if (position.maxScrollExtent > 0) {
                  await tester.drag(bodyScroll(), const Offset(0, -2000));
                  await tester.pumpAndSettle();
                  expect(
                    position.pixels,
                    closeTo(position.maxScrollExtent, 0.5),
                  );
                  expect(
                    tester.getRect(
                      find
                          .byWidgetPredicate((w) => w is ButtonStyleButton)
                          .first,
                    ),
                    before,
                  );
                  expectButtonsInside(tester, size);
                  expect(
                    find.byWidgetPredicate((w) => w is ButtonStyleButton),
                    findsNWidgets(2),
                  );
                  final paragraph = tester.renderObject<RenderParagraph>(
                    find.descendant(
                      of: bodyScroll(),
                      matching: find.byType(RichText),
                    ),
                  );
                  final length = paragraph.text.toPlainText().length;
                  final last = paragraph
                      .getBoxesForSelection(
                        TextSelection(
                          baseOffset: length - 1,
                          extentOffset: length,
                        ),
                      )
                      .last
                      .toRect();
                  final end = paragraph.localToGlobal(last.center);
                  expect(tester.getRect(bodyScroll()).contains(end), isTrue);
                }
                await removeTour(tester, cubit);
              }
            }
          }
        }
      }
    },
  );

  testTourWidgets(
    'all tour steps fit a short window and a new step starts at the top',
    (tester) async {
      const size = Size(420, 400);
      for (final language in SettingsLanguage.values) {
        for (final loaded in [false, true]) {
          final cubit = await pumpTour(
            tester,
            size: size,
            language: language,
            libraryLoaded: loaded,
          );
          final position = bodyPosition(tester);
          expect(position.maxScrollExtent, greaterThan(0));
          await tester.drag(bodyScroll(), const Offset(0, -2000));
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(
            cubit.state.currentStep!.id,
            loaded ? 'navigation' : 'empty_library',
          );
          expect(bodyPosition(tester).pixels, 0);
          for (var i = 1; i < cubit.state.steps.length; i++) {
            cubit.goToStep(i);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: cubit.state.currentStep!.id,
            );
            expectButtonsInside(tester, size);
            expect(bodyPosition(tester).pixels, 0);
          }
          await removeTour(tester, cubit);
        }
      }
    },
  );

  testTourWidgets(
    'Tab and Space still activate skip after scrolling the explanation',
    (tester) async {
      final cubit = await pumpTour(
        tester,
        size: const Size(420, 400),
        language: SettingsLanguage.english,
        libraryLoaded: false,
      );
      await tester.drag(bodyScroll(), const Offset(0, -2000));
      await tester.pumpAndSettle();
      final skip = find.text("Skip — I'll Explore On My Own");
      for (var i = 0; i < 5 && !Focus.of(tester.element(skip)).hasFocus; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(Focus.of(tester.element(skip)).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(cubit.state.isActive, isFalse);
      await removeTour(tester, cubit);
    },
  );

  testTourWidgets(
    'body stays shrink-wrapped when the caller does not bound height',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: SettingsTextScope(
            language: SettingsLanguage.english,
            child: Scaffold(
              body: SingleChildScrollView(
                child: TourTooltipCard(
                  title: 'סיום',
                  body: List.filled(30, 'גוף ההסבר').join('\n'),
                  currentIndex: 0,
                  totalSteps: 3,
                  isLastStep: true,
                  isWelcomeStep: false,
                  onNext: () {},
                  onSkip: () {},
                  onToggleAutoPlay: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TourTooltipCard)).height,
        greaterThan(600),
      );
    },
  );
}
