import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/view/pane_drag_handle.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  // PdfBookTab (חלונית הדוגמה של ידית הגרירה) קורא הגדרות בבנייתו.
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

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

        const trailingKey = Key('trailing');
        await tester.pumpWidget(
          _buildBar(
            settingsBloc: settingsBloc,
            center: const SizedBox(width: 100, height: 8),
            trailingItems: const [
              AppTopBarItem(
                widget: SizedBox(key: trailingKey, width: 40, height: 40),
              ),
            ],
          ),
        );

        final exitButton = find.byTooltip('צא ממסך מלא');
        expect(exitButton, findsOneWidget);
        // הלחצן בקצה החיצוני של צד ה-trailing — באותה פינה שבה לחצן
        // הכניסה למסך מלא שבשורת הכותרת.
        expect(
          tester.getCenter(exitButton).dx,
          greaterThan(tester.getCenter(find.byKey(trailingKey)).dx),
        );
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
      'בתוך scope פעיל של חלונית מפוצלת מוזרקת ידית גרירה',
      (tester) async {
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(settingsBloc.close);
        final pane = _pane();

        await tester.pumpWidget(
          _buildBar(
            settingsBloc: settingsBloc,
            center: const SizedBox(width: 100, height: 8),
            wrap: (bar) =>
                PaneDragHandleScope(pane: pane, enabled: true, child: bar),
          ),
        );

        expect(find.byType(PaneDragHandleButton), findsOneWidget);
      },
    );

    testWidgets(
      'scope כבוי (טאב שאינו מפוצל) אינו מזריק ידית',
      (tester) async {
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(settingsBloc.close);
        final pane = _pane();

        await tester.pumpWidget(
          _buildBar(
            settingsBloc: settingsBloc,
            center: const SizedBox(width: 100, height: 8),
            wrap: (bar) =>
                PaneDragHandleScope(pane: pane, enabled: false, child: bar),
          ),
        );

        expect(find.byType(PaneDragHandleButton), findsNothing);
      },
    );

    testWidgets(
      'ללא scope אין ידית גרירה',
      (tester) async {
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(settingsBloc.close);

        await tester.pumpWidget(
          _buildBar(
            settingsBloc: settingsBloc,
            center: const SizedBox(width: 100, height: 8),
          ),
        );

        expect(find.byType(PaneDragHandleButton), findsNothing);
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
}

PdfBookTab _pane() => PdfBookTab(
  book: PdfBook(title: 'ספר', path: '/tmp/ספר.pdf'),
  pageNumber: 1,
);

Widget _buildBar({
  required SettingsBloc settingsBloc,
  List<AppTopBarItem> leadingItems = const [],
  Widget? center,
  List<AppTopBarItem> trailingItems = const [],
  Widget Function(Widget bar)? wrap,
}) {
  final bar = AppTopBar(
    leadingItems: leadingItems,
    center: center,
    trailingItems: trailingItems,
  );
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider<SettingsBloc>.value(
        value: settingsBloc,
        child: Column(children: [wrap == null ? bar : wrap(bar)]),
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
