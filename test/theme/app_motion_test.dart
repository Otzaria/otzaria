import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_motion.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/expanding_chevron.dart';

Widget _host({required bool disableAnimations, required Widget child}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(textDirection: TextDirection.rtl, child: child),
    );

void main() {
  group('AppMotion.duration', () {
    Future<Duration> resolve(
      WidgetTester tester, {
      bool? disableAnimations,
    }) async {
      late Duration result;
      final probe = Builder(
        builder: (context) {
          result = AppMotion.duration(context, AppTokens.animNormal);
          return const SizedBox();
        },
      );
      await tester.pumpWidget(
        disableAnimations == null
            ? probe
            : _host(disableAnimations: disableAnimations, child: probe),
      );
      return result;
    }

    testWidgets('בלי העדפה: הטוקן כמו שהוא', (tester) async {
      expect(
        await resolve(tester, disableAnimations: false),
        AppTokens.animNormal,
      );
    });

    testWidgets('disableAnimations: אפס', (tester) async {
      expect(await resolve(tester, disableAnimations: true), Duration.zero);
      expect(
        AppMotion.reduced(tester.element(find.byType(SizedBox))),
        isTrue,
      );
    });

    testWidgets('בלי MediaQuery: הטוקן', (tester) async {
      expect(await resolve(tester), AppTokens.animNormal);
    });
  });

  group('רכיב שמשתמש ב-AppMotion', () {
    Future<double> turnsAfterOneFrame(
      WidgetTester tester, {
      required bool disableAnimations,
    }) async {
      await tester.pumpWidget(
        _host(
          disableAnimations: disableAnimations,
          child: const Center(child: ExpandingChevron(isExpanded: false)),
        ),
      );
      await tester.pumpWidget(
        _host(
          disableAnimations: disableAnimations,
          child: const Center(child: ExpandingChevron(isExpanded: true)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      return tester
          .widget<RotationTransition>(find.byType(RotationTransition))
          .turns
          .value;
    }

    testWidgets('disableAnimations: החץ מגיע למצבו הסופי בפריים הראשון', (
      tester,
    ) async {
      expect(await turnsAfterOneFrame(tester, disableAnimations: true), 0.5);
    });

    testWidgets('בלי העדפה: החץ עדיין באמצע הסיבוב', (tester) async {
      final turns = await turnsAfterOneFrame(tester, disableAnimations: false);
      expect(turns, greaterThan(0));
      expect(turns, lessThan(0.5));
      await tester.pumpAndSettle();
    });
  });

  group('AppMotion.scrollPosition (DD-21, q10 Q12)', () {
    Future<ScrollController> list(
      WidgetTester tester, {
      required bool disableAnimations,
    }) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          disableAnimations: disableAnimations,
          child: ListView(
            controller: controller,
            children: [for (var i = 0; i < 50; i++) const SizedBox(height: 50)],
          ),
        ),
      );
      return controller;
    }

    testWidgets('disableAnimations: קופץ ליעד מיד', (tester) async {
      final controller = await list(tester, disableAnimations: true);
      AppMotion.scrollPosition(
        controller.position,
        400,
        AppTokens.animPanelSlide,
      );
      expect(controller.offset, 400);
    });

    testWidgets('בלי העדפה: גולל בהדרגה במשך הטוקן', (tester) async {
      final controller = await list(tester, disableAnimations: false);
      AppMotion.scrollPosition(
        controller.position,
        400,
        AppTokens.animPanelSlide,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.offset, greaterThan(0));
      expect(controller.offset, lessThan(400));
      await tester.pumpAndSettle();
      expect(controller.offset, 400);
    });
  });
}
