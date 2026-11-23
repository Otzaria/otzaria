import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_personal_notes_bloc.dart';
import '../unit/mocks/mock_settings_repository.mocks.dart';

PdfHeadings _headings() => PdfHeadings(
  bookTitle: 'משנה ברכות',
  headingsMap: {'משנה ב': 1, 'משנה ז': 10},
);

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<void> show(WidgetTester tester, PdfCommentatorsTab tab) async {
    final settings = SettingsBloc(repository: MockSettingsRepository());
    final notes = StubPersonalNotesBloc();
    addTearDown(settings.close);
    addTearDown(notes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
          ],
          child: Scaffold(body: PdfCommentatorsTabScreen(tab: tab)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('כרטיסיית מפרשי PDF משוחזרת בכותרת שאליה נווט בה '
      '(issue #5798)', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final source = PdfBookTab(
      book: PdfBook(title: 'משנה ברכות', path: '/tmp/mishna.pdf'),
      pageNumber: 1,
    )..pdfHeadings = _headings();
    source.currentTitle.value = 'משנה ב';
    final tab = PdfCommentatorsTab(
      sourceTab: source,
      disposeSourceTabOnDispose: true,
    );
    addTearDown(tab.dispose);
    await show(tester, tab);
    int? shownLine() => tester
        .widget<PdfCommentaryPanel>(find.byType(PdfCommentaryPanel))
        .lineStartOverride;

    await tester.tap(find.byTooltip('הצג ניווט').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavTreeTile, 'משנה ז'));
    await tester.pump();
    expect(shownLine(), 10);

    final bookmark = await bookmarkFromReadingTab(tab);
    expect(bookmark?.ref, contains('משנה ז'), reason: 'history on close');
    expect(bookmark?.index, 1, reason: 'PDF page mapping is unavailable');

    final restored = PdfCommentatorsTab.fromJson(tab.toJson());
    addTearDown(restored.dispose);
    restored.sourceTab.pdfHeadings = _headings();
    await tester.pumpWidget(const SizedBox.shrink());
    await show(tester, restored);

    expect(shownLine(), 10, reason: 'session restore');
    final historyRecord = Bookmark.fromJson(
      bookmark!.copyWith(label: 'שם תצוגה מותאם').toJson(),
    );
    final fromHistory = tabFromBookmark(historyRecord) as PdfCommentatorsTab;
    addTearDown(fromHistory.dispose);
    fromHistory.sourceTab.pdfHeadings = _headings();
    await tester.pumpWidget(const SizedBox.shrink());
    await show(tester, fromHistory);
    expect(shownLine(), 10, reason: 'history restore without page mapping');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
