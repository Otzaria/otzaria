import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/biographies/biographies_screen.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';
import 'package:otzaria/tools/biographies/widgets/biography_card.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

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
  Future<void> pumpScreen(WidgetTester tester) async {
    final bloc = _FakeSettingsBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: bloc,
          child: Scaffold(
            body: BiographiesScreen(repository: _FakeRepository()),
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
}
