import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/gematria/widgets/gematria_result_card.dart';
import 'package:otzaria/tools/tool_query.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_settings_bloc.dart';

void main() {
  late Directory directory;
  late ToolQueryInbox inbox;
  late StubSettingsBloc bloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('gematria-screen-test');
    final torah = Directory('${directory.path}/ספרייה/תנך/תורה')
      ..createSync(recursive: true);
    File('${torah.path}/בראשית.txt').writeAsStringSync('אב');
    await Settings.setValue(SettingsRepository.keyLibraryPath, directory.path);
    await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
    await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');
    inbox = ToolQueryInbox();
    bloc = StubSettingsBloc();
  });

  tearDown(() async {
    await bloc.close();
    inbox.dispose();
    directory.deleteSync(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: bloc,
          child: Scaffold(body: GematriaSearchScreen(queryInbox: inbox)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(
    WidgetTester tester,
    String text, {
    bool link = false,
  }) async {
    if (link) {
      final action =
          ExternalUriRouter.parseUri(
                Uri(
                  scheme: 'otzaria',
                  host: 'open',
                  path: '/gematria',
                  queryParameters: {'q': text},
                ),
              )
              as OpenToolAction;
      inbox.post(action.query!);
    } else {
      await tester.enterText(find.byType(TextField), text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
    }
    await tester.pump();
  }

  Future<void> completeSearch(WidgetTester tester) async {
    // קריאות הקבצים והמשכי ה-Future עוברים בין זמן אמיתי לזמן הבדיקה.
    for (var frame = 0; frame < 10; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  for (final link in [false, true]) {
    final source = link ? 'קישור' : 'הגשה ידנית';
    final queries = link ? ['0', "׳״'", 'abc'] : ['', '0', "׳״'", 'abc'];
    for (final query in queries) {
      testWidgets('$source $query מבטל חיפוש פעיל ומפסיק את הספינר', (
        tester,
      ) async {
        await pumpScreen(tester);
        await submit(tester, '26', link: link);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await submit(tester, query, link: link);
        await completeSearch(tester);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('הזן ערך לחיפוש גימטריה'), findsOneWidget);
      });
    }
  }

  testWidgets('בקשה תקינה אחרי ביטול מסיימת את החיפוש', (tester) async {
    await pumpScreen(tester);
    await submit(tester, '26', link: true);
    await submit(tester, '0', link: true);
    await submit(tester, '3', link: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await completeSearch(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(GematriaResultCard), findsOneWidget);
    expect(
      tester
          .widget<GematriaResultCard>(find.byType(GematriaResultCard))
          .result
          .preview,
      'אב',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '3',
    );
  });

  testWidgets('בקשה תקינה חדשה דוחה את תוצאות הבקשה הקודמת', (tester) async {
    await pumpScreen(tester);
    await submit(tester, '3', link: true);
    await submit(tester, '26', link: true);
    await completeSearch(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(GematriaResultCard), findsNothing);
    expect(find.text('לא נמצאו תוצאות'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '26',
    );
  });

  testWidgets('סגירת המסך בזמן חיפוש מנתקת את מאזין הבקשות', (tester) async {
    await pumpScreen(tester);
    await submit(tester, '26', link: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    inbox.post(const ToolQuery('3'));
    await completeSearch(tester);
    expect(inbox.take()?.text, '3');
    expect(tester.takeException(), isNull);
  });
}
