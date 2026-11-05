import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/acronyms_dictionary/acronyms_dictionary_screen.dart';
import 'package:otzaria/tools/acronyms_dictionary/widgets/acronym_result_card.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';
import 'package:otzaria/tools/biographies/biographies_screen.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';
import 'package:otzaria/tools/biographies/widgets/biography_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/tool_query.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';

import '../helpers/memory_settings_cache.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeBiographiesRepository extends BiographiesRepository {
  _FakeBiographiesRepository({this.gate});

  final Future<void>? gate;

  @override
  Future<BiographiesBundle> loadBundle() async {
    await gate;
    return const BiographiesBundle(
      entries: [
        Biography(id: '1', name: 'רבי שלמה יצחקי', knownAs: ['רש"י']),
        Biography(id: '2', name: 'רבי משה בן מימון', knownAs: ['רמב"ם']),
      ],
    );
  }
}

final _dictionary = DictionaryLookupRepository(
  loadAcronyms: () async => const {
    'רש"י': ['רבי שלמה יצחקי'],
    'שו"ע': ['שולחן ערוך'],
  },
  loadAramaicEntries: () async => const [
    AramaicDictionaryEntry(aramaic: 'איתא', hebrew: 'יש'),
    AramaicDictionaryEntry(aramaic: 'גברא', hebrew: 'איש'),
  ],
);

bool _isSelected(WidgetTester tester, Finder child) => tester
    .widget<BarButton>(
      find.ancestor(of: child, matching: find.byType(BarButton)).first,
    )
    .selected;

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    final bloc = _FakeSettingsBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: bloc,
          child: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ToolQueryInbox', () {
    test('take מחזיר את הבקשה האחרונה פעם אחת בלבד', () {
      final inbox = ToolQueryInbox();
      addTearDown(inbox.dispose);
      inbox
        ..post(const ToolQuery('א'))
        ..post(const ToolQuery('ב'));

      expect(inbox.take()?.text, 'ב');
      expect(inbox.take(), isNull);
    });
  });

  group('בקשה שהופקדה לפני בניית המסך', () {
    testWidgets('ביוגרפיות — מחפש אחרי הטעינה', (tester) async {
      final inbox = ToolQueryInbox()..post(const ToolQuery('רמב"ם'));
      addTearDown(inbox.dispose);

      await pumpScreen(
        tester,
        BiographiesScreen(
          repository: _FakeBiographiesRepository(),
          queryInbox: inbox,
        ),
      );

      expect(_fieldText(tester), 'רמב"ם');
      final cards = tester.widgetList<BiographyCard>(
        find.byType(BiographyCard),
      );
      expect(cards.map((card) => card.biography.id), ['2']);
    });

    testWidgets('ראשי תיבות', (tester) async {
      final inbox = ToolQueryInbox()..post(const ToolQuery('שו"ע'));
      addTearDown(inbox.dispose);

      await pumpScreen(
        tester,
        AcronymsDictionaryScreen(repository: _dictionary, queryInbox: inbox),
      );

      expect(_fieldText(tester), 'שו"ע');
      final cards = tester.widgetList<AcronymResultCard>(
        find.byType(AcronymResultCard),
      );
      expect(cards.map((card) => card.acronym), ['שו"ע']);
    });

    testWidgets('מילון — מארמית לעברית', (tester) async {
      final inbox = ToolQueryInbox()..post(const ToolQuery('גברא'));
      addTearDown(inbox.dispose);

      await pumpScreen(
        tester,
        AramaicDictionaryScreen(repository: _dictionary, queryInbox: inbox),
      );

      expect(find.text('חפש מילה בארמית...'), findsOneWidget);
      final cards = tester.widgetList<AramaicResultCard>(
        find.byType(AramaicResultCard),
      );
      expect(cards.map((card) => card.aramaic), ['גברא']);
    });

    testWidgets('מילון — מעברית לארמית', (tester) async {
      final inbox = ToolQueryInbox()
        ..post(const ToolQuery('איש', hebrewToAramaic: true));
      addTearDown(inbox.dispose);

      await pumpScreen(
        tester,
        AramaicDictionaryScreen(repository: _dictionary, queryInbox: inbox),
      );

      expect(find.text('חפש מילה בעברית...'), findsOneWidget);
      final cards = tester.widgetList<AramaicResultCard>(
        find.byType(AramaicResultCard),
      );
      expect(cards.map((card) => card.aramaic), ['גברא']);
    });

    testWidgets('גימטריה — ממלא את השדה', (tester) async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      // ערך 0 נעצר לפני החיפוש בקבצים, ולכן הבדיקה אינה תלויה בספרייה.
      final inbox = ToolQueryInbox()..post(const ToolQuery('0'));
      addTearDown(inbox.dispose);

      await pumpScreen(tester, GematriaSearchScreen(queryInbox: inbox));

      expect(_fieldText(tester), '0');
      expect(inbox.take(), isNull);
    });
  });

  test('גימטריה — ניקוד וגרשיים מוסרים מטקסט הקישור', () {
    expect(
      GematriaSearchScreenState.linkQueryText(" תשפ״ו שָׁלוֹם ה' רמב\"ם "),
      'תשפו שלום ה רמבם',
    );
  });

  testWidgets('גימטריה — בקשה סוגרת את פאנל ההגדרות', (tester) async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final inbox = ToolQueryInbox();
    addTearDown(inbox.dispose);
    await pumpScreen(tester, GematriaSearchScreen(queryInbox: inbox));

    await tester.tap(find.byTooltip('הגדרות גימטריה'));
    await tester.pumpAndSettle();
    final settingsButton = find.byTooltip('הגדרות גימטריה');
    expect(_isSelected(tester, settingsButton), isTrue);

    inbox.post(const ToolQuery('0'));
    await tester.pumpAndSettle();

    expect(_isSelected(tester, settingsButton), isFalse);
    expect(_fieldText(tester), '0');
  });

  testWidgets('בקשה לכלי שכבר מוצג מחליפה את החיפוש ואת הכיוון', (
    tester,
  ) async {
    final inbox = ToolQueryInbox();
    addTearDown(inbox.dispose);
    await pumpScreen(
      tester,
      AramaicDictionaryScreen(repository: _dictionary, queryInbox: inbox),
    );
    await tester.enterText(find.byType(TextField), 'איתא');
    await tester.pumpAndSettle();

    inbox.post(const ToolQuery('איש', hebrewToAramaic: true));
    await tester.pumpAndSettle();

    expect(_fieldText(tester), 'איש');
    expect(find.text('חפש מילה בעברית...'), findsOneWidget);
    final cards = tester.widgetList<AramaicResultCard>(
      find.byType(AramaicResultCard),
    );
    expect(cards.map((card) => card.aramaic), ['גברא']);
  });

  testWidgets('בקשה שמגיעה בזמן הטעינה ממתינה לסופה', (tester) async {
    final loaded = Completer<void>();
    final inbox = ToolQueryInbox();
    addTearDown(inbox.dispose);
    final bloc = _FakeSettingsBloc();
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: bloc,
          child: Scaffold(
            body: BiographiesScreen(
              repository: _FakeBiographiesRepository(gate: loaded.future),
              queryInbox: inbox,
            ),
          ),
        ),
      ),
    );
    inbox.post(const ToolQuery('רש"י'));
    await tester.pump();
    // הסרגל גלוי גם בטעינה (ToolScaffold); הבקשה עדיין לא הוחלה.
    expect(_fieldText(tester), isEmpty, reason: 'עדיין בטעינה');

    loaded.complete();
    await tester.pump();
    await tester.pump();

    expect(_fieldText(tester), 'רש"י');
    final cards = tester.widgetList<BiographyCard>(find.byType(BiographyCard));
    expect(cards.map((card) => card.biography.id), ['1']);
  });
}
