import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

import '../../test_helpers/stub_settings_bloc.dart';

DictionaryLookupRepository _repository() {
  return DictionaryLookupRepository(
    loadAramaicEntries: () async => const [
      AramaicDictionaryEntry(aramaic: 'איתא', hebrew: 'יש'),
      AramaicDictionaryEntry(aramaic: 'גברא', hebrew: 'איש'),
      AramaicDictionaryEntry(aramaic: 'מַאי חָזֵית', hebrew: 'מה ראית'),
      AramaicDictionaryEntry(
        aramaic: 'איתא',
        hebrew: 'קיים',
        dictionary: 'מילון שיח ישראל',
      ),
      AramaicDictionaryEntry(
        aramaic: "ב''ד",
        hebrew: 'בית דין',
        dictionary: 'מילון שיח ישראל',
      ),
      AramaicDictionaryEntry(
        aramaic: 'אִילָנָא',
        hebrew: '{אִילָנָא} עץ',
        dictionary: 'מפירוש אונקלוס על התורה',
      ),
    ],
  );
}

Widget _wrap(Widget child, SettingsBloc bloc) => MaterialApp(
  home: BlocProvider<SettingsBloc>.value(
    value: bloc,
    child: Scaffold(body: child),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(WidgetTester tester) async {
    final bloc = StubSettingsBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      _wrap(AramaicDictionaryScreen(repository: _repository()), bloc),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ברירת המחדל היא כיוון ארמי-עברי', (tester) async {
    await pumpScreen(tester);

    expect(find.text('חפש מילה בארמית...'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'איתא');
    await tester.pumpAndSettle();
    expect(find.textContaining('יש'), findsWidgets);
  });

  testWidgets('החלפת כיוון שומרת את מילת החיפוש ומריצה חיפוש מחדש', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'איתא');
    await tester.pumpAndSettle();

    await tester.tap(find.text('עברית לארמית'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'איתא');
    expect(find.text('חפש מילה בעברית...'), findsOneWidget);
    // בכיוון עברי-ארמי "איתא" אינה מילה עברית — אין תוצאות, אך הטקסט נשמר.
    expect(find.text('לא נמצאו תוצאות'), findsOneWidget);
  });

  testWidgets('חיפוש בלי ניקוד מוצא ערך מנוקד', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'מאי חזית');
    await tester.pumpAndSettle();
    expect(find.textContaining('מה ראית'), findsWidgets);
  });

  testWidgets('גרשיים בשאילתה אינם מונעים מציאת מפתח עם גרשיים אחרים', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'ב"ד');
    await tester.pumpAndSettle();

    expect(find.textContaining('בית דין'), findsOneWidget);
  });

  testWidgets('חיפוש עברי אינו מתאים לביטוי הארמי שבסוגריים מסולסלים', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('עברית לארמית'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'אילנא');
    await tester.pumpAndSettle();
    expect(find.text('לא נמצאו תוצאות'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'עץ');
    await tester.pumpAndSettle();
    expect(find.byType(AramaicResultCard), findsOneWidget);
  });

  testWidgets('מפתח שקיים בכמה מילונים מוצג בכרטיס אחד עם כל הפירושים', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'איתא');
    await tester.pumpAndSettle();

    expect(find.byType(AramaicResultCard), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('יש')).dy,
      lessThan(tester.getTopLeft(find.text('קיים')).dy),
    );
    expect(find.text('מילון שיח ישראל'), findsNothing);
  });

  testWidgets('חיפוש הפוך מפירוש: מחליף כיוון ומחפש את המונח הראשון', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'גברא');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('חפש בעברית'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'איש');
    expect(find.text('חפש מילה בעברית...'), findsOneWidget);
    expect(find.byType(AramaicResultCard), findsOneWidget);
  });

  testWidgets('בחיפוש עברי אפשר לחפש את המילה הארמית של התוצאה', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('עברית לארמית'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'איש');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('חפש "גברא" בארמית'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'גברא');
    expect(find.text('חפש מילה בארמית...'), findsOneWidget);
  });

  testWidgets('מספר התוצאות מוצג', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'איתא');
    await tester.pumpAndSettle();

    expect(find.text('ערך אחד'), findsOneWidget);
  });
}
