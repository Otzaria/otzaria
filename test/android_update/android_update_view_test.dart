import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/android_update/bloc/android_update_bloc.dart';
import 'package:otzaria/android_update/bloc/android_update_event.dart';
import 'package:otzaria/android_update/bloc/android_update_state.dart';
import 'package:otzaria/android_update/models/android_update.dart';
import 'package:otzaria/android_update/view/android_update_host.dart';
import 'package:otzaria/android_update/view/android_update_view.dart';
import 'package:otzaria/core/foreground_work.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

import 'support.dart';

void main() {
  late FakeAndroidUpdateRepository repository;
  late AndroidUpdateBloc bloc;

  // Bloc subscribes to events in its creation zone. Construct it inside each
  // testWidgets callback so pump() can flush its asynchronous continuations.
  void initializeFixture() {
    repository = FakeAndroidUpdateRepository();
    bloc = AndroidUpdateBloc(
      repository: repository,
      networkAllowed: () => true,
      checkDue: () => false,
      recordSuccessfulCheck: () async {},
      foregroundWork: ForegroundWork(isAndroid: false),
    );
    addTearDown(bloc.close);
  }

  Widget app({
    Widget? child,
    SettingsLanguage language = SettingsLanguage.hebrew,
    double scale = 1,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: Directionality(
        textDirection: language.textDirection,
        child: SettingsTextScope(
          language: language,
          child: AndroidUpdateScope(
            bloc: bloc,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child ?? AndroidUpdatePanel(bloc: bloc),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'narrow RTL panel supports large text and an explicit install action',
    (tester) async {
      initializeFixture();
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(scale: 2));
      expect(find.text('בדוק עדכונים'), findsOneWidget);
      bloc.add(const AndroidUpdateCheck());
      await tester.pumpAndSettle();
      expect(find.text('הורד עדכון'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('הורד עדכון'));
      await tester.pumpAndSettle();
      expect(find.text('התקן עדכון'), findsOneWidget);
      expect(repository.calls, isNot(contains('install')));
      expect(bloc.state.phase, AndroidUpdatePhase.ready);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('התקן עדכון'));
      await tester.tap(find.text('התקן עדכון'));
      await tester.pumpAndSettle();
      expect(bloc.state.phase, AndroidUpdatePhase.confirmation);
      expect(
        find.text('אשר את העדכון בחלון Android. אם סגרת אותו, אפשר לנסות שוב.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permission denial explains recovery and keeps the verified APK',
    (tester) async {
      initializeFixture();
      repository.restored = fakePrepared;
      repository.permission = false;
      repository.permissionAnswer = false;
      await tester.pumpWidget(app());
      bloc.add(const AndroidUpdateInitialize());
      await tester.pumpAndSettle();
      await tester.tap(find.text('התקן עדכון'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'לא ניתנה הרשאה להתקנה. אפשר לנסות שוב ולאשר אותה במסך Android.',
        ),
        findsOneWidget,
      );
      expect(find.text('התקן עדכון'), findsOneWidget);
      expect(repository.calls, isNot(contains('install')));
      repository.permissionAnswer = true;
      await tester.tap(find.text('התקן עדכון'));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('install'));
      expect(bloc.state.phase, AndroidUpdatePhase.confirmation);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings entry opens a dialog with the selected language and direction',
    (tester) async {
      initializeFixture();
      await tester.pumpWidget(
        app(
          language: SettingsLanguage.english,
          child: const AndroidUpdateSettingsTile(),
        ),
      );
      await tester.tap(find.text('Check and update'));
      await tester.pumpAndSettle();
      final panel = find.byType(AndroidUpdatePanel);
      expect(panel, findsOneWidget);
      expect(
        SettingsTextScope.languageOf(tester.element(panel)),
        SettingsLanguage.english,
      );
      expect(Directionality.of(tester.element(panel)), TextDirection.ltr);
      expect(find.text('Download update'), findsOneWidget);
      expect(repository.calls, ['checkDirect']);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    },
  );

  testWidgets(
    'Play presents the store flow and completion without APK permission',
    (tester) async {
      initializeFixture();
      repository.appEnvironment = playEnvironment;
      repository.native = const AndroidNativeUpdateStatus(stage: 'available');
      await tester.pumpWidget(app());
      bloc.add(const AndroidUpdateInitialize());
      await tester.pumpAndSettle();
      expect(find.text('גרסה חדשה זמינה ב-Google Play.'), findsOneWidget);
      await tester.tap(find.text('הורד עדכון'));
      await tester.pumpAndSettle();
      expect(find.text('אשר את העדכון בחלון Google Play.'), findsOneWidget);
      repository.controller.add(
        const AndroidNativeUpdateStatus(stage: 'ready'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('העדכון מוכן. ההתקנה תפעיל את אוצריא מחדש.'),
        findsOneWidget,
      );
      expect(repository.calls, ['resume', 'startPlay']);
      await tester.tap(find.text('התקן עדכון'));
      await tester.pump();
      expect(repository.calls, ['resume', 'startPlay', 'completePlay']);
      expect(
        find.text('אפשר לאוצריא להתקין עדכונים במסך Android, ואז חזור לכאן.'),
        findsNothing,
      );
      expect(repository.calls, isNot(contains('permission')));
      expect(repository.calls, isNot(contains('download')));
      expect(repository.calls, isNot(contains('install')));
    },
  );

  testWidgets(
    'title bar indicator is shown for an available update and opens shared state',
    (tester) async {
      initializeFixture();
      await tester.pumpWidget(app(child: const AndroidUpdateIndicator()));
      expect(find.text('עדכון'), findsNothing);
      bloc.add(const AndroidUpdateCheck());
      await tester.pumpAndSettle();
      expect(find.text('עדכון'), findsOneWidget);
      await tester.tap(find.text('עדכון'));
      await tester.pumpAndSettle();
      expect(find.text('הורד עדכון'), findsOneWidget);
      expect(repository.calls, ['checkDirect']);
      expect(tester.takeException(), isNull);
    },
  );
}
