import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tools/biographies/biographies_screen.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';
import 'package:otzaria/tools/biographies/widgets/biography_card.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';

import '../test_helpers/stub_settings_bloc.dart';

class _FakeRepository extends BiographiesRepository {
  @override
  Future<BiographiesBundle> loadBundle() async => const BiographiesBundle(
    eras: [
      BiographyEra('tannaim', 'תנאים'),
      BiographyEra('rishonim', 'ראשונים'),
    ],
    entries: [
      Biography(
        id: 'a',
        name: 'רבי עקיבא',
        era: 'tannaim',
        summary: 'מגדולי התנאים.',
        students: [RelatedPerson(name: 'רבי מאיר', ref: 'm')],
      ),
      Biography(
        id: 'm',
        name: 'רבי מאיר',
        era: 'tannaim',
        summary: 'תלמיד רבי עקיבא.',
        teachers: [RelatedPerson(name: 'רבי עקיבא', ref: 'a')],
      ),
      Biography(id: 'r', name: 'רש"י', era: 'rishonim', summary: 'פרשן.'),
    ],
  );
}

/// רשימת ערכים שסופרת קריאות לפי אינדקס: כל כרטיס שנבנה קורא את הערך שלו.
class _CountingEntries extends ListBase<Biography> {
  _CountingEntries(this._inner);

  final List<Biography> _inner;
  int reads = 0;

  @override
  int get length => _inner.length;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  Biography operator [](int index) {
    reads++;
    return _inner[index];
  }

  @override
  void operator []=(int index, Biography value) =>
      throw UnsupportedError('read only');
}

class _LargeRepository extends BiographiesRepository {
  _LargeRepository(this.entries);

  final _CountingEntries entries;

  @override
  Future<BiographiesBundle> loadBundle() async => BiographiesBundle(
    eras: const [BiographyEra('rishonim', 'ראשונים')],
    entries: entries,
  );
}

List<String> _shownIds(WidgetTester tester) => tester
    .widgetList<BiographyCard>(find.byType(BiographyCard))
    .map((card) => card.biography.id)
    .toList();

Finder _card(String id) => find.byWidgetPredicate(
  (w) => w is BiographyCard && w.biography.id == id,
);

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    BiographiesRepository? repository,
  }) async {
    final bloc = StubSettingsBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: bloc,
          child: Scaffold(
            body: BiographiesScreen(
              repository: repository ?? _FakeRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a link opens the entry without touching the search', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'רבי');
    await tester.pumpAndSettle();
    expect(_shownIds(tester), unorderedEquals(['a', 'm']));

    // Expand רבי עקיבא and follow the link to his student.
    await tester.tap(
      find.descendant(of: _card('a'), matching: find.text('הצג עוד')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: _card('a'), matching: find.text('רבי מאיר')),
    );
    await tester.pumpAndSettle();

    expect(_fieldText(tester), 'רבי');
    expect(_shownIds(tester), ['m']);
    expect(find.text('חזרה לרשימה'), findsOneWidget);

    // From the student back to his teacher, then two steps back.
    await tester.tap(
      find.descendant(of: _card('m'), matching: find.text('רבי עקיבא')),
    );
    await tester.pumpAndSettle();
    expect(_shownIds(tester), ['a']);
    expect(find.text('חזרה אל רבי מאיר'), findsOneWidget);

    await tester.tap(find.text('חזרה אל רבי מאיר'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('חזרה לרשימה'));
    await tester.pumpAndSettle();

    expect(_fieldText(tester), 'רבי');
    expect(_shownIds(tester), unorderedEquals(['a', 'm']));
  });

  testWidgets('no results under a search and an era offers to reset', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('ראשונים'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'רבי');
    await tester.pumpAndSettle();

    expect(_shownIds(tester), isEmpty);
    expect(
      find.text('אין ערכים שמתאימים לחיפוש "רבי" בתקופת "ראשונים".'),
      findsOneWidget,
    );

    await tester.tap(find.text('חיפוש בכל התקופות'));
    await tester.pumpAndSettle();
    expect(_shownIds(tester), unorderedEquals(['a', 'm']));
    expect(_fieldText(tester), 'רבי');

    await tester.enterText(find.byType(TextField), 'זזז');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ניקוי החיפוש'));
    await tester.pumpAndSettle();
    expect(_fieldText(tester), isEmpty);
    expect(_shownIds(tester), ['a', 'm', 'r']);
  });

  testWidgets('גרירת פס הגלילה לסוף רשימה ארוכה בונה רק את כרטיסי היעד', (
    tester,
  ) async {
    final entries = _CountingEntries([
      for (var i = 0; i < 3000; i++)
        Biography(
          id: 'b$i',
          name: 'רב $i',
          era: 'rishonim',
          summary: 'ערך מספר $i.',
        ),
    ]);
    await pumpScreen(tester, repository: _LargeRepository(entries));
    entries.reads = 0;

    await tester.drag(
      find.byKey(ScrollablePositionedListScrollbar.thumbKey),
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();

    expect(_shownIds(tester), contains('b2999'));
    // ListView בונה בקפיצה כזו כל כרטיס שבדרך: אלפי קריאות.
    expect(entries.reads, lessThan(200));
  });
}
