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
}
