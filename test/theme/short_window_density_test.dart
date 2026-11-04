// q12 Q8: בחלון נמוך (טלפון לרוחב) הכרום בצפיפות הקומפקטית.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/theme/app_seed_colors.dart';

class _Probe extends StatefulWidget {
  const _Probe({required this.onBuild});
  final void Function(AppDensity density) onBuild;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) {
    widget.onBuild(AppDensity.of(context));
    return const SizedBox();
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    Size size, {
    bool compactSetting = false,
    required void Function(AppDensity density) onBuild,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final cs = AppThemeData.createColorScheme(
      AppSeedColors.defaultLight,
      Brightness.light,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(cs, compactMenuMode: compactSetting),
        home: ShortWindowDensity(child: _Probe(onBuild: onBuild)),
      ),
    );
  }

  testWidgets('640×360: קומפקטי; 360×640: רגיל; ה-State נשמר בסיבוב', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    late AppDensity density;
    await pump(tester, const Size(640, 360), onBuild: (d) => density = d);
    expect(density.isCompact, isTrue);
    expect(density.topBarHeight, 44);
    final state = tester.state(find.byType(_Probe));

    await pump(tester, const Size(360, 640), onBuild: (d) => density = d);
    expect(density.isCompact, isFalse);
    expect(tester.state(find.byType(_Probe)), same(state));
  });

  testWidgets('הגדרה קומפקטית נשארת קומפקטית בכל גובה', (tester) async {
    addTearDown(tester.view.reset);
    late AppDensity density;
    await pump(
      tester,
      const Size(1280, 800),
      compactSetting: true,
      onBuild: (d) => density = d,
    );
    expect(density.isCompact, isTrue);
  });
}
