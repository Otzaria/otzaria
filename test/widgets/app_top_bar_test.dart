import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

void main() {
  group('AppTopBar', () {
    testWidgets(
      'does not update height notifier synchronously when visibility notifier instance changes',
      (tester) async {
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(settingsBloc.close);

        final totalHeightNotifier = ValueNotifier<double>(0);
        addTearDown(totalHeightNotifier.dispose);

        final firstVisibilityNotifier = ValueNotifier<bool>(true);
        addTearDown(firstVisibilityNotifier.dispose);

        await tester.pumpWidget(
          _TestApp(
            settingsBloc: settingsBloc,
            totalHeightNotifier: totalHeightNotifier,
            visibilityNotifier: firstVisibilityNotifier,
          ),
        );
        await tester.pump();

        final secondVisibilityNotifier = ValueNotifier<bool>(false);
        addTearDown(secondVisibilityNotifier.dispose);

        await tester.pumpWidget(
          _TestApp(
            settingsBloc: settingsBloc,
            totalHeightNotifier: totalHeightNotifier,
            visibilityNotifier: secondVisibilityNotifier,
          ),
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'center ממורכז גאומטרית בסרגל גם כשהצדדים לא סימטריים',
      (tester) async {
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(settingsBloc.close);

        const centerKey = Key('center');
        await tester.pumpWidget(
          _buildBar(
            settingsBloc: settingsBloc,
            leadingItems: const [
              AppTopBarItem(widget: SizedBox(width: 200, height: 40)),
            ],
            center: const SizedBox(key: centerKey, width: 100, height: 8),
            trailingItems: const [
              AppTopBarItem(widget: SizedBox(width: 40, height: 40)),
            ],
          ),
        );

        final barWidth = tester.getSize(find.byType(AppTopBar)).width;
        expect(
          tester.getCenter(find.byKey(centerKey)).dx,
          moreOrLessEquals(barWidth / 2, epsilon: 1.0),
        );
      },
    );

    testWidgets(
      'במסך מלא מוזרק לחצן יציאה כפריט בסרגל',
      (tester) async {
        final settingsBloc = _TestSettingsBloc(
          SettingsState.initial().copyWith(isFullscreen: true),
        );
        addTearDown(settingsBloc.close);

        await tester.pumpWidget(
          _buildBar(
            settingsBloc: settingsBloc,
            center: const SizedBox(width: 100, height: 8),
          ),
        );

        expect(find.byTooltip('צא ממסך מלא'), findsOneWidget);
      },
    );

    testWidgets(
      'ללא מסך מלא לא מוצג לחצן יציאה',
      (tester) async {
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(settingsBloc.close);

        await tester.pumpWidget(
          _buildBar(
            settingsBloc: settingsBloc,
            center: const SizedBox(width: 100, height: 8),
          ),
        );

        expect(find.byTooltip('צא ממסך מלא'), findsNothing);
      },
    );

    testWidgets(
      'center רחב לא גולש ולא חוסם לחיצות על trailing',
      (tester) async {
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(settingsBloc.close);

        var tapped = false;
        const trailingKey = Key('trailing-button');
        await tester.pumpWidget(
          _buildBar(
            settingsBloc: settingsBloc,
            center: const SizedBox(width: 2000, height: 8),
            trailingItems: [
              AppTopBarItem(
                widget: GestureDetector(
                  key: trailingKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tapped = true,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            ],
          ),
        );

        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(trailingKey));
        expect(tapped, isTrue);
      },
    );
  });

  group('ToolbarGhostButton — צבע מושבת', () {
    testWidgets('onPressed=null פותר את צבע החזית ל-disabledColor',
        (tester) async {
      late final Color disabledColor;
      late final Color enabledColor;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            final theme = Theme.of(context);
            disabledColor = theme.disabledColor;
            enabledColor = theme.colorScheme.onSurfaceVariant;
            return const ToolbarGhostButton(text: 'ט', onPressed: null);
          }),
        ),
      ));

      final ghostTheme = tester.widget<TextButtonTheme>(
        find
            .ancestor(
              of: find.byType(TextButton),
              matching: find.byType(TextButtonTheme),
            )
            .first,
      );
      final fg = ghostTheme.data.style!.foregroundColor!;
      expect(fg.resolve({WidgetState.disabled}), disabledColor);
      expect(fg.resolve(<WidgetState>{}), enabledColor);
    });
  });
}

Widget _buildBar({
  required SettingsBloc settingsBloc,
  List<AppTopBarItem> leadingItems = const [],
  Widget? center,
  List<AppTopBarItem> trailingItems = const [],
}) {
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider<SettingsBloc>.value(
        value: settingsBloc,
        child: Column(
          children: [
            AppTopBar(
              leadingItems: leadingItems,
              center: center,
              trailingItems: trailingItems,
            ),
          ],
        ),
      ),
    ),
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.settingsBloc,
    required this.totalHeightNotifier,
    required this.visibilityNotifier,
  });

  final SettingsBloc settingsBloc;
  final ValueNotifier<double> totalHeightNotifier;
  final ValueNotifier<bool> visibilityNotifier;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: Column(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: totalHeightNotifier,
                builder: (context, height, _) {
                  return Text(
                    'height: $height',
                    textDirection: TextDirection.rtl,
                  );
                },
              ),
              AppTopBar(
                totalHeightNotifier: totalHeightNotifier,
                secondaryRowVisible: visibilityNotifier,
                center: const SizedBox.shrink(),
                secondaryRow: const SizedBox(
                  height: 24,
                  child: Text(
                    'שורה שניה',
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
