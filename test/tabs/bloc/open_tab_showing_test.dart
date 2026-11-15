import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<TabsBloc> blocWith(List<OpenedTab> tabs, {int current = 0}) async {
    final bloc = TabsBloc(repository: _FakeTabsRepository());
    bloc.add(ReplaceAllTabs(tabs, current));
    await bloc.stream.firstWhere((s) => s.tabs.length == tabs.length);
    addTearDown(bloc.close);
    return bloc;
  }

  TextBookTab textTab(TextBook book) => TextBookTab(book: book, index: 0);

  PdfBookTab pdfTab(String path) => PdfBookTab(
    book: PdfBook(title: 'ספר', path: path),
    pageNumber: 1,
  );

  group('openTabShowing', () {
    test('ספר טקסט נמצא לפי המזהה, גם כשהכותרת שונה', () async {
      final bloc = await blocWith([
        textTab(TextBook(id: 7, title: 'אחר')),
        textTab(TextBook(id: 1, title: 'בראשית')),
      ]);

      final match = bloc.openTabShowing(TextBook(id: 1, title: 'כותרת אחרת'));

      expect(match?.index, 1);
      expect(match?.pane, isNull);
    });

    test('ספר אישי עם אותו מזהה אינו הספר הרשמי', () async {
      final bloc = await blocWith([textTab(TextBook(id: 1, title: 'בראשית'))]);

      final match = bloc.openTabShowing(
        TextBook(id: 1, title: 'בראשית', source: BookSource.user),
      );

      expect(match, isNull);
    });

    test('מהדורה חלופית פתוחה אינה הנוסח הממוזג', () async {
      final bloc = await blocWith([
        textTab(TextBook(id: 1, title: 'בראשית', versionTitle: 'Vilna')),
      ]);

      expect(bloc.openTabShowing(TextBook(id: 1, title: 'בראשית')), isNull);
    });

    test('ספר PDF נמצא לפי הנתיב', () async {
      final bloc = await blocWith([pdfTab('/lib/a.pdf'), pdfTab('/lib/b.pdf')]);

      final match = bloc.openTabShowing(
        PdfBook(title: 'כותרת', path: '/lib/b.pdf'),
      );

      expect(match?.index, 1);
    });

    test('ספר בחלונית של כרטיסייה משולבת מחזיר גם את החלונית', () async {
      final left = textTab(TextBook(id: 2, title: 'שמות'));
      final combined = CombinedTab(
        rightTab: textTab(TextBook(id: 1, title: 'בראשית')),
        leftTab: left,
      );
      final bloc = await blocWith([pdfTab('/lib/a.pdf'), combined]);

      final match = bloc.openTabShowing(TextBook(id: 2, title: 'שמות'));

      expect(match?.index, 1);
      expect(match?.pane, same(left));
    });
  });

  test('SetCurrentTab עם חלונית מפעיל אותה בכרטיסייה המשולבת', () async {
    final right = pdfTab('/lib/r.pdf');
    final left = pdfTab('/lib/l.pdf');
    final bloc = await blocWith([
      pdfTab('/lib/a.pdf'),
      CombinedTab(rightTab: right, leftTab: left),
    ]);

    bloc.add(SetCurrentTab(1, pane: left));
    await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

    expect(bloc.state.activePane, same(left));
  });

  test('SetCurrentTab מתעלם מחלונית שאינה בכרטיסייה', () async {
    final stray = pdfTab('/lib/x.pdf');
    final bloc = await blocWith([
      CombinedTab(
        rightTab: pdfTab('/lib/r.pdf'),
        leftTab: pdfTab('/lib/l.pdf'),
      ),
      pdfTab('/lib/a.pdf'),
    ], current: 1);

    bloc.add(SetCurrentTab(0, pane: stray));
    await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);

    expect(bloc.state.rawActivePane, isNot(same(stray)));
  });
}

class _FakeTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}
