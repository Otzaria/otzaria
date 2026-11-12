import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_update_frequency.dart';
import 'package:otzaria/settings/panels/semantic_data_panel.dart';

import '../../semantic_search/semantic_test_support.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('semantic_panel_'));
  tearDown(() async {
    for (var attempt = 0; attempt < 5 && root.existsSync(); attempt++) {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  testWidgets('נתונים מוכנים: בחירת תדירות נשמרת, ו"בדוק עדכון" מוצג', (
    tester,
  ) async {
    installModelFiles(root);
    final settings = FakeSettingsStore()..dataEnabled = true;
    final repository = buildRepository(
      root: root,
      settings: settings,
      backend: FakeBackend()..vectors = installedV30,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('he', 'IL'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SemanticDataPanel(
                repository: repository,
                platformSupported: true,
              ),
            ),
          ),
        ),
      );
      await waitFor(
        () => repository.availability.phase == SemanticAvailabilityPhase.ready,
      );
    });
    await tester.pump();

    expect(
      find.byKey(const ValueKey('semantic-data-update-frequency')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('semantic-data-update-now')),
      findsOneWidget,
    );

    await tester.tap(find.text('ידני'));
    await tester.runAsync(
      () => waitFor(
        () => settings.updateFrequency == SemanticUpdateFrequency.manual,
      ),
    );
    await tester.pump();

    expect(settings.updateFrequency, SemanticUpdateFrequency.manual);
  });
}
