import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/tikkun_korim/bloc/tikkun_korim_bloc.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_korim_screen.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../support/tikkun_fakes.dart';

class _StubSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _StubSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _linesPerPage = 40;
const _noachLine = 10;

/// עמודי שיטה בני 40 שורות, ופרשת נח באמצע העמוד הראשון (לא בסופו, שם
/// הרשימה נצמדת לתחתית ולא לשורת היעד).
class _PagedEngine extends FakeTikkunEngine {
  @override
  ProcessedTorah processTorah(
    Map<String, String> rawByBookId,
    StamWidthModel widths, {
    TikkunTradition tradition = TikkunTradition.ashkenazSephard,
    TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
    String methodId = '',
  }) {
    final processed = super.processTorah(rawByBookId, widths);
    processed.allLines[1].parashaName = null;
    processed.allLines[_noachLine].parashaName = 'נח';
    return processed;
  }

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

/// טעינת ספר שנעצרת עד שהבדיקה משחררת אותה — לצפייה במצב שבאמצע הטעינה.
class _GatedLoader extends FakeTikkunTextLoader {
  final String gatedBook;
  final gate = Completer<void>();

  _GatedLoader(this.gatedBook, super.texts);

  @override
  Future<String> loadRawText(String hebrewBookName) async {
    if (hebrewBookName == gatedBook) await gate.future;
    return super.loadRawText(hebrewBookName);
  }
}

void main() {
  final longText = List.filled(600, 'מילה').join(' ');

  Future<TikkunKorimBloc> pumpScreen(
    WidgetTester tester, {
    FakeTikkunSettingsStore? store,
    _GatedLoader Function(Map<String, String> texts)? gatedLoader,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = FakeTikkunDataSource();
    final texts = {'בראשית': longText, 'שופטים': longText};
    final bloc = TikkunKorimBloc(
      repository: TikkunKorimRepository(
        engine: _PagedEngine(),
        data: data,
        textLoader: gatedLoader?.call(texts) ?? FakeTikkunTextLoader(texts),
        computeRunner: syncComputeRunner,
      ),
      data: data,
      settingsStore: store ?? FakeTikkunSettingsStore(),
      upcomingParasha: (_, {required inIsrael}) => 'נח',
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
              BlocProvider<SettingsBloc>(create: (_) => _StubSettingsBloc()),
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

  ReaderPage reader(WidgetTester tester) =>
      tester.widget<ReaderPage>(find.byType(ReaderPage));

  List<ItemPosition> visible(WidgetTester tester) {
    final positions = reader(tester).positionsListener!.itemPositions.value
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .toList();
    return positions..sort((a, b) => a.index.compareTo(b.index));
  }

  // מעבר-הדהייה של החבילה בונה רשימה שנייה מעל הראשונה.
  final innerLists = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'PositionedList',
  );

  /// מוודא שבמשך זמן אנימציית הגלילה התצוגה נשארת במקומה, בלי רשימה שנייה.
  Future<void> expectStillFor300ms(WidgetTester tester) async {
    final first = visible(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(innerLists, findsOneWidget, reason: 'frame $i');
      expect(visible(tester), first, reason: 'frame $i');
    }
    await tester.pumpAndSettle();
    // מפעיל את טיימר סנכרון הבוררים שלא יישאר תלוי בסוף הבדיקה.
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('מעבר מתחתית עמוד לעמוד הבא — בראש העמוד, בלי קפיצה', (
    tester,
  ) async {
    final bloc = await pumpScreen(tester);
    expect(bloc.state.nav.currentColumnIndex, 0);
    reader(tester).scrollController!.jumpTo(index: _linesPerPage - 1);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    expect(visible(tester).first.index, greaterThan(15));

    await tester.tap(find.byTooltip('עמוד הבא'));
    await tester.pump();

    expect(bloc.state.nav.currentColumnIndex, 1);
    expect(identical(reader(tester).lines, bloc.state.currentLines), isTrue);
    expect(innerLists, findsOneWidget);
    expect(visible(tester).first.index, 0);
    expect(visible(tester).first.itemLeadingEdge, greaterThanOrEqualTo(0));
    await expectStillFor300ms(tester);
    expect(visible(tester).first.index, 0);
  });

  testWidgets('מעבר לעמוד אחר עם שורת יעד — נפתח ישר בשורה, בלי אנימציה', (
    tester,
  ) async {
    final bloc = await pumpScreen(tester);
    expect(visible(tester).first.index, _noachLine);
    bloc.add(const TikkunColumnSelected(2));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    bloc.add(const TikkunParashaChanged('נח'));
    final firstPage = bloc.state.pages.first.lines;
    // ממתינים לפריים הראשון שמציג את העמוד החדש.
    for (
      var i = 0;
      i < 10 && !identical(reader(tester).lines, firstPage);
      i++
    ) {
      await tester.pump();
      expect(innerLists, findsOneWidget);
    }

    expect(bloc.state.nav.currentColumnIndex, 0);
    expect(visible(tester).first.index, _noachLine);
    await expectStillFor300ms(tester);
    expect(visible(tester).first.index, _noachLine);
    // הרשימה החדשה לא מדווחת על שורה אחרת שהייתה מזיזה את בורר הפרשה.
    expect(bloc.state.nav.parashaName, 'נח');
  });

  testWidgets('באותה רשימה בחירת פרק גוללת אליו וחזרה לפרק הראשון', (
    tester,
  ) async {
    final bloc = await pumpScreen(
      tester,
      store: FakeTikkunSettingsStore(
        settings: const TikkunSettings(startupMode: 'lastPosition'),
        navState: const TikkunNavState(
          section: TikkunSection.neviim,
          tanachBookId: 'shoftim',
        ),
      ),
    );
    final list = tester.state(find.byType(ReaderPage));

    bloc.add(const TikkunChapterSelected(40));
    await tester.pumpAndSettle();
    expect(visible(tester).first.index, 39);

    bloc.add(const TikkunChapterSelected(1));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    expect(visible(tester).first.index, 0);
    expect(tester.state(find.byType(ReaderPage)), same(list));
  });

  group('טעינה איטית של מקום אחר — העמוד הקודם נשאר עד שהחדש מוכן', () {
    /// במשך הטעינה מוצג העמוד הקודם כמות שהוא, ואין דיווח שורה עליו.
    Future<void> expectOldPageWhileLoading(
      WidgetTester tester,
      TikkunKorimBloc bloc,
      FakeTikkunSettingsStore store, {
      required List<TikkunLine> oldLines,
      required int oldLine,
    }) async {
      final nav = bloc.state.nav;
      final saved = store.navState;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          identical(reader(tester).lines, oldLines),
          isTrue,
          reason: 'frame $i',
        );
        expect(visible(tester).first.index, oldLine, reason: 'frame $i');
      }
      // מעבר לטיימר הדיווח (150ms): דיווח על העמוד הישן היה משנה את הניווט.
      await tester.pump(const Duration(milliseconds: 200));
      expect(bloc.state.isLoading, isTrue);
      expect(bloc.state.nav, nav);
      expect(store.navState, saved);
    }

    /// בדיקה שנכשלה באמצע הטעינה משאירה אותה תלויה, וסגירת ה-BLoC הייתה ממתינה לה.
    Future<void> releaseGate(WidgetTester tester, _GatedLoader loader) async {
      if (loader.gate.isCompleted) return;
      loader.gate.complete();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('פתיחת סימניה בעמוד אחר של מדור אחר', (tester) async {
      late _GatedLoader loader;
      final store = FakeTikkunSettingsStore(
        settings: const TikkunSettings(startupMode: 'lastPosition'),
        navState: const TikkunNavState(
          section: TikkunSection.neviim,
          tanachBookId: 'shoftim',
        ),
      );
      final bloc = await pumpScreen(
        tester,
        store: store,
        gatedLoader: (texts) => loader = _GatedLoader('בראשית', texts),
      );
      addTearDown(() => releaseGate(tester, loader));
      reader(tester).scrollController!.jumpTo(index: 25);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      final oldLines = reader(tester).lines;

      // פסוק 51 הוא שורה 50 בתורה: עמוד 1, שורה 10.
      bloc.add(
        const TikkunBookmarkOpened(
          TikkunBookmark(
            id: 'b',
            title: 'b',
            nav: TikkunNavState(
              parashaName: 'נח',
              currentColumnIndex: 1,
              verseKey: 1051,
            ),
          ),
        ),
      );
      await tester.pump();
      await expectOldPageWhileLoading(
        tester,
        bloc,
        store,
        oldLines: oldLines,
        oldLine: 25,
      );

      loader.gate.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      expect(bloc.state.nav.section, TikkunSection.torah);
      expect(bloc.state.nav.currentColumnIndex, 1);
      expect(identical(reader(tester).lines, bloc.state.currentLines), isTrue);
      expect(visible(tester).first.index, 10);
      expect(bloc.state.nav.parashaName, 'נח');
      expect(store.navState.verseKey, 1051);
      expect(store.navState.lineOffset, 0);
    });

    testWidgets('מעבר מדור מעמוד שאינו הראשון', (tester) async {
      late _GatedLoader loader;
      final store = FakeTikkunSettingsStore();
      final bloc = await pumpScreen(
        tester,
        store: store,
        gatedLoader: (texts) => loader = _GatedLoader('שופטים', texts),
      );
      addTearDown(() => releaseGate(tester, loader));
      bloc.add(const TikkunColumnSelected(2));
      await tester.pumpAndSettle();
      reader(tester).scrollController!.jumpTo(index: 15);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      final oldLines = reader(tester).lines;

      bloc.add(const TikkunSectionChanged(TikkunSection.neviim));
      await tester.pump();
      expect(bloc.state.nav.section, TikkunSection.neviim);
      await expectOldPageWhileLoading(
        tester,
        bloc,
        store,
        oldLines: oldLines,
        oldLine: 15,
      );

      loader.gate.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      expect(bloc.state.pages, hasLength(1));
      expect(identical(reader(tester).lines, bloc.state.currentLines), isTrue);
      expect(visible(tester).first.index, 0);
      expect(bloc.state.nav.tanachBookId, 'shoftim');
      expect(store.navState.section, TikkunSection.neviim);
    });
  });

  group('זום ושינוי גודל החלון שומרים את מיקום הקריאה', () {
    const scrolledLine = 25;
    final longStore = FakeTikkunSettingsStore(
      settings: const TikkunSettings(startupMode: 'lastPosition'),
      navState: const TikkunNavState(
        section: TikkunSection.neviim,
        tanachBookId: 'shoftim',
      ),
    );

    /// האם העמוד רחב מהחלון ונגלל לרוחב.
    bool pageIsWide(WidgetTester tester) => tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .any(
          (s) =>
              s.position.axis == Axis.horizontal &&
              s.position.maxScrollExtent > 0,
        );

    Future<State> scrollToLine(WidgetTester tester) async {
      reader(tester).scrollController!.jumpTo(index: scrolledLine);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      expect(visible(tester).first.index, scrolledLine);
      return tester.state(find.byType(ScrollablePositionedList));
    }

    Future<void> setZoom(
      WidgetTester tester,
      TikkunKorimBloc bloc,
      double zoom,
    ) async {
      bloc.add(TikkunSettingsUpdated(bloc.state.settings.copyWith(zoom: zoom)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('זום פנימה והחוצה מעבר לרוחב החלון', (tester) async {
      final bloc = await pumpScreen(tester, store: longStore);
      final list = await scrollToLine(tester);
      expect(pageIsWide(tester), isFalse);

      for (final zoom in [1.25, 1.5, 2.0, 3.0, 0.8, 1.0]) {
        await setZoom(tester, bloc, zoom);
        expect(pageIsWide(tester), zoom > 1, reason: 'zoom $zoom');
        expect(visible(tester).first.index, scrolledLine, reason: 'zoom $zoom');
        expect(
          tester.state(find.byType(ScrollablePositionedList)),
          same(list),
          reason: 'zoom $zoom',
        );
      }
    });

    testWidgets('שינוי גודל החלון מעבר לרוחב העמוד המוגדל', (tester) async {
      final bloc = await pumpScreen(tester, store: longStore);
      await setZoom(tester, bloc, 1.25);
      final list = await scrollToLine(tester);
      expect(pageIsWide(tester), isTrue);

      for (final size in [const Size(3000, 900), const Size(1400, 900)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 200));
        expect(pageIsWide(tester), size.width < 3000, reason: '$size');
        expect(visible(tester).first.index, scrolledLine, reason: '$size');
        expect(
          tester.state(find.byType(ScrollablePositionedList)),
          same(list),
          reason: '$size',
        );
      }
    });
  });
}
