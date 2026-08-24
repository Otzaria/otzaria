import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

DictionaryLookupRepository _repository() {
  return DictionaryLookupRepository(
    loadAramaicEntries: () async => const [
      AramaicDictionaryEntry(aramaic: 'איתא', hebrew: 'יש'),
      AramaicDictionaryEntry(aramaic: 'גברא', hebrew: 'איש'),
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
    final bloc = _FakeSettingsBloc();
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

    await tester.tap(find.byTooltip('החלף כיוון'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'איתא');
    expect(find.text('חפש מילה בעברית...'), findsOneWidget);
    // בכיוון עברי-ארמי "איתא" אינה מילה עברית — אין תוצאות, אך הטקסט נשמר.
    expect(find.text('לא נמצאו תוצאות'), findsOneWidget);
  });
}
