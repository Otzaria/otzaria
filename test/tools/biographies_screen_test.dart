@Tags(['manual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/biographies/biographies_screen.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';
import 'package:otzaria/tools/biographies/widgets/biography_card.dart';

import '../test_helpers/stub_settings_bloc.dart';

/// Runs the biographies screen on a real release file. Manual only:
/// `flutter test test/tools/biographies_screen_test.dart --tags manual`
/// `--dart-define=BIO_FILE=<path of biographies-app.json.gz>`
void main() {
  const path = String.fromEnvironment('BIO_FILE');

  Widget host(BiographiesRepository repository) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: BlocProvider<SettingsBloc>(
        create: (_) => StubSettingsBloc(SettingsState.initial()),
        child: Scaffold(body: BiographiesScreen(repository: repository)),
      ),
    ),
  );

  testWidgets('מציג ערכים אמיתיים ומסנן בחיפוש', (tester) async {
    final repository = BiographiesRepository(
      updatedPathProvider: () async => path,
    );

    // Load in the real zone before building the screen: file reads and the
    // decoding isolate never complete when started in the fake-async zone.
    await tester.runAsync(repository.loadAll);
    await tester.pumpWidget(host(repository));
    // The loaded Future belongs to the real zone, so its callbacks need a turn
    // of the real event loop.
    await tester.runAsync(() async {});
    await tester.pump();
    await tester.pump();

    // נטענו כרטיסים.
    expect(find.byType(BiographyCard), findsWidgets);

    // חיפוש מצמצם לתוצאות רלוונטיות בלבד.
    await tester.enterText(find.byType(TextField).first, 'הרמב"ם');
    await tester.pump();
    final first = tester
        .widgetList<BiographyCard>(find.byType(BiographyCard))
        .first
        .biography;
    expect(first.name, 'רבינו משה בן מימון');

    // שאילתה חסרת תוצאות מציגה מצב ריק.
    await tester.enterText(find.byType(TextField).first, 'זזזזזזז');
    await tester.pump();
    expect(find.text('לא נמצאו תוצאות'), findsOneWidget);
  }, skip: path.isEmpty);
}
