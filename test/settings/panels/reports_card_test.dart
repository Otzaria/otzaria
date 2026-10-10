import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/dialogs/reports_management_dialog.dart';
import 'package:otzaria/settings/panels/reports_card.dart';
import 'package:otzaria/settings/search/settings_search_registry.dart';

void main() {
  late List<ReportsTab?> opened;
  late ReportCounts counts;

  setUp(() {
    opened = [];
    counts = const ReportCounts(books: 2, app: 1, sent: 20);
  });

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReportsCard(
              loadCounts: () async => counts,
              openManagement: (context, {initialTab}) async {
                opened.add(initialTab);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('summarizes saved and sent reports of every kind', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.text('3 שמורים בתור · 20 נשלחו'), findsOneWidget);
  });

  testWidgets('says so when nothing is saved', (tester) async {
    counts = const ReportCounts(sent: 4);
    await pumpCard(tester);
    expect(find.text('אין דיווחים שמורים בתור · 4 נשלחו'), findsOneWidget);
  });

  testWidgets('"הצג דיווחים" opens the dialog on its default tab', (
    tester,
  ) async {
    await pumpCard(tester);
    await tester.tap(find.byKey(const ValueKey('reports-card-manage')));
    await tester.pumpAndSettle();
    expect(opened, [null]);
  });

  testWidgets('a search result opens the tab it names', (tester) async {
    await pumpCard(tester);
    final registry = SettingsSearchRegistry.instance;

    await registry.scrollAndHighlight(ReportsCard.cardId, section: 'app');
    await registry.scrollAndHighlight(ReportsCard.cardId, section: 'books');
    await registry.scrollAndHighlight(ReportsCard.cardId, section: 'manage');
    expect(opened, [ReportsTab.app, ReportsTab.books, null]);
  });

  testWidgets('a result without a section only highlights the card', (
    tester,
  ) async {
    await pumpCard(tester);
    await tester.runAsync(
      () => SettingsSearchRegistry.instance.scrollAndHighlight(
        ReportsCard.cardId,
      ),
    );
    expect(opened, isEmpty);
  });

  test('pendingOf and pending add up the saved reports', () {
    const counts = ReportCounts(books: 2, app: 1, plugins: 4, sent: 9);
    expect(counts.pending, 7);
    expect(counts.pendingOf(ReportsTab.plugins), 4);
  });
}
