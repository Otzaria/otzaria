import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/tikkun_korim/bloc/tikkun_korim_bloc.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_korim_screen.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';

import '../../../test_helpers/stub_settings_bloc.dart';
import '../support/tikkun_fakes.dart';

const _linesPerPage = 40;

/// עמודי שיטה בני 40 שורות — כדי שיהיה עמוד הבא ל-Ctrl+←.
class _PagedEngine extends FakeTikkunEngine {
  @override
  List<TikkunPage> buildPages(ProcessedTorah processed, String methodId) {
    final all = processed.allLines;
    return [
      for (var start = 0; start < all.length; start += _linesPerPage)
        TikkunPage(
          startLineIdx: start,
          endLineIdx: (start + _linesPerPage).clamp(0, all.length),
          lines: all.sublist(
            start,
            (start + _linesPerPage).clamp(0, all.length),
          ),
        ),
    ];
  }
}

void main() {
  final longText = List.filled(600, 'מילה').join(' ');

  Future<TikkunKorimBloc> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = FakeTikkunDataSource();
    final bloc = TikkunKorimBloc(
      repository: TikkunKorimRepository(
        engine: _PagedEngine(),
        data: data,
        textLoader: FakeTikkunTextLoader({'בראשית': longText}),
        computeRunner: syncComputeRunner,
      ),
      data: data,
      settingsStore: FakeTikkunSettingsStore(),
      upcomingParasha: (_, {required inIsrael}) => 'בראשית',
      widthModelOf: (_) => fakeWidths,
      measureRoofs: (_) async {},
    )..add(const TikkunStarted());
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>(create: (_) => StubSettingsBloc()),
              BlocProvider<TikkunKorimBloc>.value(value: bloc),
            ],
            child: TikkunKorimView(data: data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  /// מיקום הגלילה האנכית של טור הקריאה.
  ScrollPosition column(WidgetTester tester) => tester
      .stateList<ScrollableState>(
        find.descendant(
          of: find.byType(ReaderPage),
          matching: find.byType(Scrollable),
        ),
      )
      .firstWhere((s) => s.position.axis == Axis.vertical)
      .position;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
    // טיימר סנכרון הבוררים (150ms) לא יישאר תלוי בסוף הבדיקה.
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('arrow keys scroll the tikkun reading column (issue #2348)', () {
    testWidgets('↓ גולל את הטור, ↑ מחזיר', (tester) async {
      await pumpScreen(tester);
      expect(column(tester).pixels, 0);

      await press(tester, LogicalKeyboardKey.arrowDown);
      final afterDown = column(tester).pixels;
      expect(afterDown, greaterThan(0));

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(column(tester).pixels, lessThan(afterDown));
    });

    testWidgets('PageDown גולל יותר מ-↓, ו-PageUp חוזר', (tester) async {
      await pumpScreen(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      final line = column(tester).pixels;

      await press(tester, LogicalKeyboardKey.pageDown);
      final page = column(tester).pixels - line;
      expect(page, greaterThan(line));
      // פחות מחלון שלם — השורה האחרונה נשארת גלויה בראש.
      expect(page, lessThan(column(tester).viewportDimension));

      await press(tester, LogicalKeyboardKey.pageUp);
      expect(column(tester).pixels, closeTo(line, 1));
    });

    testWidgets('Ctrl+← עדיין מדפדף לעמוד הבא, בלי לגלול', (tester) async {
      final bloc = await pumpScreen(tester);
      expect(bloc.state.nav.currentColumnIndex, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));

      expect(bloc.state.nav.currentColumnIndex, 1);
      expect(column(tester).pixels, 0);

      // הטור של העמוד החדש נבנה מחדש — ↓ עדיין גולל אותו.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(column(tester).pixels, greaterThan(0));
    });

    testWidgets('אחרי Tab לסרגל ↓ אינו גולל; לחיצה בטור מחזירה את המקשים', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('tikkun_korim_shortcuts'),
      );

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(column(tester).pixels, 0);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('tikkun_korim_shortcuts'),
      );

      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(column(tester).pixels, greaterThan(0));
    });
  });
}
