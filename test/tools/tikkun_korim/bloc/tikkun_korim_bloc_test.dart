import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/tools/tikkun_korim/bloc/tikkun_korim_bloc.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';

import '../support/tikkun_fakes.dart';

void main() {
  late FakeTikkunEngine engine;
  late FakeTikkunDataSource data;
  late FakeTikkunTextLoader loader;
  late FakeTikkunSettingsStore store;

  TikkunKorimRepository buildRepository() => TikkunKorimRepository(
    engine: engine,
    data: data,
    textLoader: loader,
    computeRunner: syncComputeRunner,
  );

  TikkunKorimBloc buildBloc() => TikkunKorimBloc(
    repository: buildRepository(),
    data: data,
    settingsStore: store,
    upcomingParasha: (_) => 'נח',
    widthModelOf: (_) => fakeWidths,
    prepareFonts: () async {},
  );

  setUp(() {
    engine = FakeTikkunEngine();
    data = FakeTikkunDataSource();
    loader = FakeTikkunTextLoader();
    store = FakeTikkunSettingsStore();
  });

  group('טעינה ראשונה', () {
    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'במצב "פרשת השבוע" נפתח בפרשה שהלוח מחזיר',
      build: buildBloc,
      act: (bloc) => bloc.add(const TikkunStarted()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.nav.parashaName, 'נח');
        expect(bloc.state.nav.bookId, 'bereshit');
        expect(bloc.state.pages, isNotEmpty);
        expect(bloc.state.isLoading, isFalse);
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'במצב "מיקום אחרון" נשמר מצב הניווט השמור',
      build: () {
        store = FakeTikkunSettingsStore(
          settings: const TikkunSettings(startupMode: 'lastPosition'),
          navState: const TikkunNavState(
            bookId: 'shemot',
            parashaName: 'וארא',
          ),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(const TikkunStarted()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.nav.parashaName, 'וארא');
        expect(bloc.state.nav.bookId, 'shemot');
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'כשל בעיבוד מסתיים במצב שגיאה בלי עמודים',
      build: () {
        engine.throwOnProcessTorah = StateError('נפילה');
        return buildBloc();
      },
      act: (bloc) => bloc.add(const TikkunStarted()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.error, isNotNull);
        expect(bloc.state.pages, isEmpty);
        expect(bloc.state.isLoading, isFalse);
      },
    );
  });

  group('ניווט בין טורים', () {
    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'עמוד הבא מקדם, ומעבר לסוף אינו חורג',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        for (var i = 0; i < 50; i++) {
          bloc.add(const TikkunNextColumn());
        }
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(
          bloc.state.nav.currentColumnIndex,
          bloc.state.columnCount - 1,
        );
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'דילוג לעמוד מחוץ לטווח נצמד לגבול',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunColumnSelected(-5));
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) => expect(bloc.state.nav.currentColumnIndex, 0),
    );
  });

  group('מדורים', () {
    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'מעבר להפטרות טוען עמוד יחיד עם כותרת',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunSectionChanged(TikkunSection.haftarot));
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.nav.section, TikkunSection.haftarot);
        expect(bloc.state.pages.length, 1);
        expect(bloc.state.headerTitle, 'הפטרת בראשית');
        expect(bloc.state.headerSubtitle, contains('הפטרה:'));
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'הפטרה שאין בה מנהג ספרדי מציגה הודעה בלי עמודים',
      build: () {
        store = FakeTikkunSettingsStore(
          settings: const TikkunSettings(nusach: 'sephard'),
        );
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunSectionChanged(TikkunSection.haftarot));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunHaftarahChanged('h2'));
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        expect(bloc.state.pages, isEmpty);
        expect(
          bloc.state.headerSubtitle,
          ToolsMessages.tikkunNoHaftarahForNusach,
        );
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'אותה הפטרה בנוסח אשכנז נטענת כרגיל',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunSectionChanged(TikkunSection.haftarot));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunHaftarahChanged('h2'));
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        expect(bloc.state.pages, isNotEmpty);
        expect(bloc.state.headerSubtitle, contains('הפטרה:'));
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'בנוסח ספרדי בלי נתון ייעודי הכותרת מציינת "כמנהג אשכנז"',
      build: () {
        store = FakeTikkunSettingsStore(
          settings: const TikkunSettings(
            nusach: 'sephard',
            nusachLand: 'diaspora',
          ),
        );
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunSectionChanged(TikkunSection.haftarot));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunHaftarahChanged('h3'));
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        expect(bloc.state.headerSubtitle, contains('כמנהג אשכנז'));
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'הפטרה עם נתון ספרדי ייעודי אינה מסומנת "כמנהג אשכנז"',
      build: () {
        store = FakeTikkunSettingsStore(
          settings: const TikkunSettings(nusach: 'sephard'),
        );
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunSectionChanged(TikkunSection.haftarot));
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.headerSubtitle, isNot(contains('כמנהג אשכנז')));
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'מעבר לנביאים בוחר את הספר הראשון ובונה מיפוי פרקים',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunSectionChanged(TikkunSection.neviim));
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.nav.tanachBookId, 'shoftim');
        expect(bloc.state.chapterToLineIdx, isNotEmpty);
        expect(loader.requested, contains('שופטים'));
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'קריאות למועדים מסוננות לפי המנהג',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunSectionChanged(TikkunSection.torahReadings));
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.readingsForCurrentLand().map((r) => r.id), ['r1']);
        expect(bloc.state.headerTitle, 'ראש חודש');
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'קריאה שתויגה בנוסח מוצגת רק בנוסח התואם',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(
          TikkunSettingsUpdated(
            const TikkunSettings().copyWith(nusach: 'sephard'),
          ),
        );
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.readingsForCurrentLand().map((r) => r.id), ['r1', 'r3']);
      },
    );
  });

  group('הגדרות', () {
    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'שינוי הגדרה נשמר',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(
          TikkunSettingsUpdated(
            const TikkunSettings().copyWith(lineSpacing: 2.0),
          ),
        );
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.settings.lineSpacing, 2.0);
        expect(store.settings.lineSpacing, 2.0);
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'שינוי נוסח בזמן הפטרה טוען מחדש בנוסח החדש',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunSectionChanged(TikkunSection.haftarot));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(
          TikkunSettingsUpdated(
            bloc.state.settings.copyWith(nusach: 'sephard'),
          ),
        );
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.settings.nusach, 'sephard');
        expect(bloc.state.pages, isNotEmpty);
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'שינוי טעמי הדברות טוען מחדש ומגיע למנוע',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(
          TikkunSettingsUpdated(
            bloc.state.settings.copyWith(
              decalogueTaam: TikkunDecalogueTaam.elyon,
            ),
          ),
        );
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.settings.decalogueTaam, TikkunDecalogueTaam.elyon);
        expect(engine.lastDecalogueTaam, TikkunDecalogueTaam.elyon);
        expect(bloc.state.pages, isNotEmpty);
      },
    );

    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'הצצה מחליפה את הטור המוסתר בפועל',
      build: () {
        store = FakeTikkunSettingsStore(
          settings: const TikkunSettings(hideNikud: true),
        );
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunPeekToggled());
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.effectiveHideStam, isTrue);
        expect(bloc.state.effectiveHideNikud, isFalse);
      },
    );
  });

  group('סנכרון לפי גלילה', () {
    blocTest<TikkunKorimBloc, TikkunKorimState>(
      'שורה גלויה בפרשה אחרת מעדכנת את בורר הפרשה',
      build: () {
        store = FakeTikkunSettingsStore(
          settings: const TikkunSettings(startupMode: 'lastPosition'),
          navState: const TikkunNavState(methodId: 'single_page'),
        );
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const TikkunStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const TikkunVisibleLineChanged(1));
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) => expect(bloc.state.nav.parashaName, 'נח'),
    );
  });
}
