import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc(super.initialState) {
    on<UpdateCompactMenuMode>(
      (event, emit) =>
          emit(state.copyWith(compactMenuMode: event.compactMenuMode)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ThemeData _theme({required bool compact}) => AppThemeData.light(
  AppThemeData.createColorScheme(
    AppSeedColors.defaultLight,
    Brightness.light,
  ),
  compactMenuMode: compact,
);

void main() {
  group('AppDensity', () {
    test('AppThemeData בונה אותו מההגדרה', () {
      expect(_theme(compact: true).extension<AppDensity>(), AppDensity.compact);
      expect(
        _theme(compact: false).extension<AppDensity>(),
        AppDensity.regular,
      );
    });

    test('ההגדרה עוברת כמו שהיא גם מחוץ לדסקטופ', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(_theme(compact: true).extension<AppDensity>()!.isCompact, isTrue);
    });

    test('מידות לפי מצב', () {
      expect(AppDensity.regular.topBarHeight, 56);
      expect(AppDensity.compact.topBarHeight, 44);
      expect(AppDensity.regular.fieldHeight, AppInputTokens.regularHeight);
      expect(AppDensity.compact.fieldHeight, AppInputTokens.compactHeight);
    });

    test('lerp מתחלף באמצע, copyWith', () {
      expect(
        AppDensity.regular.lerp(AppDensity.compact, 0.4),
        AppDensity.regular,
      );
      expect(
        AppDensity.regular.lerp(AppDensity.compact, 0.5),
        AppDensity.compact,
      );
      expect(AppDensity.regular.lerp(null, 1), AppDensity.regular);
      expect(AppDensity.regular.copyWith(isCompact: true), AppDensity.compact);
    });

    testWidgets('Theme בלי ההרחבה הוא רגיל', (tester) async {
      late AppDensity density;
      await tester.pumpWidget(
        Theme(
          data: ThemeData(),
          child: Builder(
            builder: (context) {
              density = AppDensity.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(density, AppDensity.regular);
    });
  });

  testWidgets('שינוי "צפיפות ממשק" מעדכן סרגל וכפתור מיד, בלי הפעלה מחדש', (
    tester,
  ) async {
    final settings = _FakeSettingsBloc(SettingsState.initial());
    addTearDown(settings.close);
    // אותו חיווט כמו ב-App: ערכת הנושא נבנית מחדש כשההגדרה משתנה.
    await tester.pumpWidget(
      BlocProvider<SettingsBloc>.value(
        value: settings,
        child: BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (p, c) => p.compactMenuMode != c.compactMenuMode,
          builder: (context, state) => MaterialApp(
            theme: _theme(compact: state.compactMenuMode),
            home: const Scaffold(
              body: Column(
                children: [
                  AppTopBar(center: Text('בראשית')),
                  SquareIconButton.toolbar(
                    key: ValueKey('square'),
                    icon: FluentIcons.search_24_regular,
                    onPressed: null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    double barHeight() => tester.getSize(find.byType(AppTopBar)).height;
    double squareSide() =>
        tester.getSize(find.byKey(const ValueKey('square'))).height;

    expect(barHeight(), 56);
    expect(squareSide(), AppInputTokens.regularHeight);

    settings.add(const UpdateCompactMenuMode(true));
    await tester.pumpAndSettle();
    expect(barHeight(), 44);
    expect(squareSide(), AppInputTokens.compactHeight);

    settings.add(const UpdateCompactMenuMode(false));
    await tester.pumpAndSettle();
    expect(barHeight(), 56);
    expect(squareSide(), AppInputTokens.regularHeight);
  });
}
