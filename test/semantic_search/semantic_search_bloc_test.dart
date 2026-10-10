import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/bloc/semantic_search_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/settings/panels/semantic_data_panel.dart';

import 'semantic_test_support.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('semantic_bloc_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('ה-bloc משקף את המאגר מהבדיקה ועד ההתקנה', () async {
    final bloc = SemanticSearchBloc(
      repository: buildRepository(
        root: root,
        locator: FakeLocator(releaseV30()),
      ),
    );
    addTearDown(bloc.close);

    bloc.add(const SemanticSearchStarted());
    await waitFor(
      () =>
          bloc.state.availability.phase ==
          SemanticAvailabilityPhase.needsDownload,
    );
    expect(
      bloc.state.availability.phase,
      SemanticAvailabilityPhase.needsDownload,
    );

    bloc.add(const SemanticDownloadRequested());
    await waitFor(
      () => bloc.state.availability.phase == SemanticAvailabilityPhase.ready,
    );
    expect(bloc.state.availability.phase, SemanticAvailabilityPhase.ready);
  });

  test('סגירת הדיאלוג אינה עוצרת הורדה, ופתיחה מחדש מציגה את מצבה', () async {
    installModelFiles(root);
    final gate = Completer<void>();
    final downloads = FakeDownloads()..gate = gate;
    final repository = buildRepository(
      root: root,
      download: downloads.call,
      locator: FakeLocator(releaseV30()),
    );
    final first = SemanticSearchBloc(repository: repository)
      ..add(const SemanticSearchStarted());
    first.add(const SemanticDownloadRequested());
    await waitFor(() => downloads.lastIsCancelled != null);
    await first.close();
    expect(downloads.lastIsCancelled!(), isFalse);

    final reopened = SemanticSearchBloc(repository: repository)
      ..add(const SemanticSearchStarted());
    addTearDown(reopened.close);
    await waitFor(() => reopened.state.availability.progress != null);
    expect(
      reopened.state.availability.phase,
      SemanticAvailabilityPhase.downloading,
    );

    gate.complete();
    await waitFor(
      () =>
          reopened.state.availability.phase == SemanticAvailabilityPhase.ready,
    );
  });

  group('SemanticDataPanel', () {
    Widget app(Widget child) => MaterialApp(
      locale: const Locale('he', 'IL'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('מוסתר כשהפלטפורמה אינה נתמכת', (tester) async {
      final repository = buildRepository(root: root, platformSupported: false);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          app(
            SemanticDataPanel(repository: repository, platformSupported: true),
          ),
        );
        await repository.refresh();
      });
      await tester.pump();

      expect(find.text('נתוני $kSemanticSearchModeName'), findsNothing);
    });

    testWidgets('במכשיר לא נתמך לא נוצרת אפילו בדיקת זמינות', (tester) async {
      final repository = buildRepository(root: root);
      final initialAvailability = repository.availability;
      await tester.pumpWidget(
        app(
          SemanticDataPanel(repository: repository, platformSupported: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BlocProvider<SemanticSearchBloc>), findsNothing);
      expect(repository.availability, same(initialAvailability));
      expect(find.text('נתוני $kSemanticSearchModeName'), findsNothing);
    });

    testWidgets('בלי נתונים מציע הורדה, ובלי הסכמה מפנה להסכמה', (
      tester,
    ) async {
      final consent = FakeConsentStore();
      final repository = buildRepository(root: root, consent: consent);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          app(
            SemanticDataPanel(repository: repository, platformSupported: true),
          ),
        );
        await waitFor(
          () =>
              repository.availability.phase ==
              SemanticAvailabilityPhase.needsDownload,
        );
      });
      await tester.pump();

      expect(find.text('נתוני $kSemanticSearchModeName'), findsOneWidget);
      expect(find.text('הנתונים עוד לא הורדו'), findsOneWidget);
      expect(find.byKey(const ValueKey('semantic-data-download')), findsOne);
      // יש רק דיוק אחד עם release, ולכן הבחירה אינה מוצגת.
      expect(
        find.byKey(const ValueKey('semantic-data-quantization')),
        findsNothing,
      );

      await tester.runAsync(() async {
        consent.set(SearchFeedbackConsent.declined);
        await waitFor(
          () =>
              repository.availability.phase ==
              SemanticAvailabilityPhase.consentRequired,
        );
      });
      await tester.pump();

      expect(
        find.text(
          'כדי להשתמש ב$kSemanticSearchModeName יש להפעיל את "שיפור המנגנון"',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('semantic-data-download')),
        findsNothing,
      );
    });
  });
}
