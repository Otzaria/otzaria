import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/tikkun_korim/bloc/tikkun_korim_bloc.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_korim_screen.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/tikkun_settings_panel.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

import '../support/tikkun_fakes.dart';

/// SettingsBloc מזויף — AppTopBar קורא ממנו את מצב ה-compact.
class _StubSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _StubSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeTikkunEngine engine;
  late FakeTikkunDataSource data;
  late FakeTikkunSettingsStore store;

  setUp(() {
    engine = FakeTikkunEngine();
    data = FakeTikkunDataSource();
    store = FakeTikkunSettingsStore();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(1400, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bloc = TikkunKorimBloc(
      repository: TikkunKorimRepository(
        engine: engine,
        data: data,
        textLoader: FakeTikkunTextLoader(),
        computeRunner: syncComputeRunner,
      ),
      data: data,
      settingsStore: store,
      upcomingParasha: (_) => 'נח',
      widthModelOf: (_) => fakeWidths,
      prepareFonts: () async {},
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
  }

  testWidgets('המסך מציג את בוררי הסרגל ואת עמוד הקריאה', (tester) async {
    await pumpScreen(tester);

    // מדור, שיטה, חומש, פרשה, עליה.
    expect(find.byType(AppDropdownField<String>), findsWidgets);
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.textContaining('עמוד '), findsOneWidget);
    expect(find.byTooltip('הדפסה'), findsOneWidget);
    expect(find.byTooltip('ייצוא ל-PDF'), findsOneWidget);
  });

  testWidgets('במסך רחב הבוררים בשורת הסרגל, במסך צר בשורה שנייה', (
    tester,
  ) async {
    await pumpScreen(tester);
    var bar = tester.widget<AppTopBar>(find.byType(AppTopBar));
    expect(bar.secondaryRow, isNull);
    expect(bar.leadingItems, isNotEmpty);

    await pumpScreen(tester, size: const Size(760, 900));
    bar = tester.widget<AppTopBar>(find.byType(AppTopBar));
    expect(bar.secondaryRow, isNotNull);
    expect(bar.leadingItems, isEmpty);
    // ניווט העמודים נשאר בשורה הראשית כשיש לו מקום שם.
    final pageLabel = tester.getTopLeft(find.textContaining('מתוך')).dy;
    final printButton = tester.getTopLeft(find.byTooltip('הדפסה')).dy;
    expect((pageLabel - printButton).abs(), lessThan(24));
    expect(find.byType(AppDropdownField<String>), findsWidgets);
    expect(find.byTooltip('ייצוא ל-PDF'), findsOneWidget);
  });

  testWidgets('במסך צר מאוד הבוררים נשברים לכמה שורות ונשארים גלויים', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(400, 900));
    final selectors = find.byType(AppDropdownField<String>);
    expect(selectors, findsAtLeastNWidgets(3));
    final tops = <double>{
      for (final e in selectors.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dy,
    };
    expect(tops.length, greaterThan(1));
    for (final e in selectors.evaluate()) {
      expect(
        tester.getRect(find.byWidget(e.widget)).right,
        lessThanOrEqualTo(400),
      );
    }
  });

  testWidgets('כפתור ההגדרות פותח חלונית צפה מעל התוכן', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byType(TikkunSettingsPanel), findsNothing);
    final readerWidthBefore = tester.getSize(find.byType(ReaderPage)).width;

    await tester.tap(find.byTooltip('הגדרות'));
    await tester.pumpAndSettle();

    expect(find.byType(ContextOverlayPanel), findsOneWidget);
    expect(find.byType(TikkunSettingsPanel), findsOneWidget);
    // צפה = לא דוחפת: רוחב אזור הקריאה לא השתנה.
    expect(tester.getSize(find.byType(ReaderPage)).width, readerWidthBefore);
  });

  testWidgets('החלונית נפתחת בצד של כפתור ההגדרות', (tester) async {
    await pumpScreen(tester);
    final buttonX = tester.getCenter(find.byTooltip('הגדרות')).dx;

    await tester.tap(find.byTooltip('הגדרות'));
    await tester.pumpAndSettle();

    final panelX = tester.getCenter(find.byType(TikkunSettingsPanel)).dx;
    final screenCenterX =
        tester.getSize(find.byType(TikkunKorimView)).width / 2;
    expect(buttonX < screenCenterX, panelX < screenCenterX);
  });

  testWidgets('תוויות הסגמנט בחלונית אינן נשברות לשתי שורות', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('הגדרות'));
    await tester.pumpAndSettle();
    final label = tester.widget<Text>(find.text('מיקום אחרון'));
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
  });

  testWidgets('מקש Escape סוגר את חלונית ההגדרות', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('הגדרות'));
    await tester.pumpAndSettle();
    expect(find.byType(TikkunSettingsPanel), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TikkunSettingsPanel), findsNothing);
  });

  testWidgets('עמוד יחיד — אין מחוון עמוד ואין חיצים', (tester) async {
    await pumpScreen(tester);
    final bloc = tester
        .element(find.byType(ReaderPage))
        .read<TikkunKorimBloc>();

    bloc.add(const TikkunMethodChanged('single_page'));
    await tester.pumpAndSettle();

    expect(bloc.state.columnCount, 1);
    expect(find.textContaining('מתוך'), findsNothing);
    expect(find.byTooltip('עמוד הבא'), findsNothing);
    expect(find.byTooltip('עמוד קודם'), findsNothing);
  });

  testWidgets('כפתור "עמוד הבא" מקדם את מחוון העמוד', (tester) async {
    await pumpScreen(tester);
    final bloc = tester
        .element(find.byType(ReaderPage))
        .read<TikkunKorimBloc>();
    final before = bloc.state.nav.currentColumnIndex;

    await tester.tap(find.byTooltip('עמוד הבא'));
    await tester.pumpAndSettle();

    expect(bloc.state.nav.currentColumnIndex, before + 1);
  });

  testWidgets('קיצור המקלדת מדפדף עמוד קדימה ואחורה', (tester) async {
    await pumpScreen(tester);
    final bloc = tester
        .element(find.byType(ReaderPage))
        .read<TikkunKorimBloc>();
    final before = bloc.state.nav.currentColumnIndex;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(bloc.state.nav.currentColumnIndex, before + 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(bloc.state.nav.currentColumnIndex, before);

    // RTL: חץ שמאל מקדם עמוד.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(bloc.state.nav.currentColumnIndex, before + 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('אין הפטרה במנהג — מוצגת ההודעה של ה-BLoC', (tester) async {
    store = FakeTikkunSettingsStore(
      settings: const TikkunSettings(nusach: 'sephard'),
    );
    await pumpScreen(tester);
    final bloc = tester
        .element(find.byType(ReaderPage))
        .read<TikkunKorimBloc>();

    bloc.add(const TikkunSectionChanged(TikkunSection.haftarot));
    await tester.pumpAndSettle();
    bloc.add(const TikkunHaftarahChanged('h2'));
    await tester.pumpAndSettle();

    expect(find.text(ToolsMessages.tikkunNoHaftarahForNusach), findsOneWidget);
    expect(find.text(ToolsMessages.tikkunNoData), findsNothing);
  });

  testWidgets('בורר ההפטרות מסנן יום טוב שני לפי ארץ ישראל/חוץ לארץ', (
    tester,
  ) async {
    Future<List<String>> haftarahLabels() async {
      final bloc = tester
          .element(find.byType(ReaderPage))
          .read<TikkunKorimBloc>();
      bloc.add(const TikkunSectionChanged(TikkunSection.haftarot));
      await tester.pumpAndSettle();
      final field = tester
          .widgetList<AppDropdownField<String>>(
            find.byType(AppDropdownField<String>),
          )
          .firstWhere((f) => f.entries.any((e) => e.value == 'h1'));
      return field.entries.map((e) => e.label).toList();
    }

    await pumpScreen(tester);
    expect(await haftarahLabels(), isNot(contains('יום טוב שני')));

    store = FakeTikkunSettingsStore(
      settings: const TikkunSettings(nusachLand: 'diaspora'),
    );
    await pumpScreen(tester);
    expect(await haftarahLabels(), contains('יום טוב שני'));
  });
}
