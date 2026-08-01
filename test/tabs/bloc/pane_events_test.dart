import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../helpers/memory_settings_cache.dart';

/// אירועי הפיצול: יצירה, פירוק, החלפת צדדים, יחס וסגירת חלונית.
///
/// החוט המשותף לכולם — הטאבים עוברים בזהותם ולא בשכפול, שאם לא כן מיקום
/// הקריאה בכל ספר היה מתאפס בכל שינוי מבנה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab leaf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );

  Future<TabsBloc> blocWith(List<OpenedTab> tabs, {int current = 0}) async {
    final bloc = TabsBloc(repository: _FakeTabsRepository());
    bloc.add(ReplaceAllTabs(tabs, current));
    await bloc.stream.firstWhere((s) => s.tabs.length == tabs.length);
    return bloc;
  }

  /// מרווח לאירוע שאמור להיבלע, כדי לוודא שהמצב באמת לא השתנה.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  List<String> titles(OpenedTab tab) =>
      leafPanes(tab).map((p) => p.title).toList();

  group('EnableSideBySideMode — יצירת הפיצול', () {
    test('שני טאבים מתמזגים לטאב אחד ויוצאים משורת הכרטיסיות', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([a, b]);

      bloc.add(EnableSideBySideMode(rightTab: a, leftTab: b));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final combined = bloc.state.tabs.single;
      expect(combined, isA<CombinedTab>());
      expect(titles(combined), ['א', 'ב']);
      expect(bloc.state.currentTabIndex, 0);

      await bloc.close();
    });

    test('החלוניות הן אותם אובייקטים — הספרים אינם נטענים מחדש', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([a, b]);

      bloc.add(EnableSideBySideMode(rightTab: a, leftTab: b));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final combined = bloc.state.tabs.single as CombinedTab;
      expect(combined.rightTab, same(a));
      expect(combined.leftTab, same(b));

      await bloc.close();
    });

    test('סדר הארגומנטים קובע איזו חלונית ימנית', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([a, b]);

      bloc.add(EnableSideBySideMode(rightTab: b, leftTab: a));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      expect(titles(bloc.state.tabs.single), ['ב', 'א']);

      await bloc.close();
    });

    test('הטאב המפוצל נכנס במקום המוקדם מבין השניים', () async {
      final first = leaf('ראשון');
      final middle = leaf('אמצעי');
      final last = leaf('אחרון');
      final bloc = await blocWith([first, middle, last], current: 2);

      // המיזוג בין הראשון לאחרון — התוצאה יושבת במקום הראשון.
      bloc.add(EnableSideBySideMode(rightTab: last, leftTab: first));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs[0], isA<CombinedTab>());
      expect(bloc.state.tabs[1], same(middle));
      expect(bloc.state.currentTabIndex, 0);

      await bloc.close();
    });

    test('הצמדה של אחד הצדדים עוברת לטאב המפוצל', () async {
      final pinned = leaf('נעוץ')..isPinned = true;
      final plain = leaf('רגיל');
      final bloc = await blocWith([pinned, plain]);

      bloc.add(EnableSideBySideMode(rightTab: pinned, leftTab: plain));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      expect(bloc.state.tabs.single.isPinned, isTrue);

      await bloc.close();
    });

    test('טאב שכבר מפוצל אינו נכנס לפיצול נוסף', () async {
      final combined = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב'));
      final other = leaf('ג');
      final bloc = await blocWith([combined, other]);

      bloc.add(EnableSideBySideMode(rightTab: combined, leftTab: other));
      await settle();

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.tabs[0], same(combined));

      await bloc.close();
    });

    test('אותו טאב בשני הצדדים אינו משנה דבר', () async {
      final only = leaf('יחיד');
      final neighbour = leaf('שכן');
      final bloc = await blocWith([only, neighbour]);

      bloc.add(EnableSideBySideMode(rightTab: only, leftTab: only));
      await settle();

      expect(bloc.state.tabs, [same(only), same(neighbour)]);

      await bloc.close();
    });

    test('טאב שאינו ברשימה אינו יוצר פיצול', () async {
      final open = leaf('פתוח');
      final stranger = leaf('זר');
      final bloc = await blocWith([open]);

      bloc.add(EnableSideBySideMode(rightTab: open, leftTab: stranger));
      await settle();

      expect(bloc.state.tabs, [same(open)]);

      await bloc.close();
    });
  });

  group('DisableSideBySideMode — פירוק הפיצול', () {
    test('שתי החלוניות חוזרות ככרטיסיות באותו מקום', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final before = leaf('לפני');
      final bloc = await blocWith([
        before,
        CombinedTab(rightTab: a, leftTab: b),
      ]);

      bloc.add(const DisableSideBySideMode(1));
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      expect(bloc.state.tabs, [same(before), same(a), same(b)]);
      expect(bloc.state.currentTabIndex, 1);

      await bloc.close();
    });

    test('ההצמדה של הטאב המפוצל עוברת לשתי הכרטיסיות', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([
        CombinedTab(rightTab: a, leftTab: b, isPinned: true),
      ]);

      bloc.add(const DisableSideBySideMode(0));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs.map((t) => t.isPinned), [isTrue, isTrue]);

      await bloc.close();
    });

    test('פירוק טאב שאינו מוצמד אינו מצמיד את החלוניות', () async {
      final bloc = await blocWith([
        CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב')),
      ]);

      bloc.add(const DisableSideBySideMode(0));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs.map((t) => t.isPinned), [isFalse, isFalse]);

      await bloc.close();
    });

    test('אינדקס של טאב שאינו מפוצל אינו משנה את הרשימה', () async {
      final plain = leaf('רגיל');
      final bloc = await blocWith([plain]);

      bloc.add(const DisableSideBySideMode(0));
      await settle();

      expect(bloc.state.tabs, [same(plain)]);

      await bloc.close();
    });

    test('אינדקס מחוץ לתחום אינו מפיל', () async {
      final plain = leaf('רגיל');
      final bloc = await blocWith([plain]);

      bloc.add(const DisableSideBySideMode(7));
      await settle();

      expect(bloc.state.tabs, [same(plain)]);

      await bloc.close();
    });
  });

  group('SwapSideBySideTabs — החלפת צדדים', () {
    test('הצדדים מתחלפים, היחס מתהפך והזהות נשמרת', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([
        CombinedTab(rightTab: a, leftTab: b, splitRatio: 0.7),
      ]);

      bloc.add(const SwapSideBySideTabs());
      await bloc.stream.firstWhere(
        (s) => (s.currentTab as CombinedTab).rightTab == b,
      );

      final swapped = bloc.state.currentTab as CombinedTab;
      expect(swapped.rightTab, same(b));
      expect(swapped.leftTab, same(a));
      expect(swapped.splitRatio, closeTo(0.3, 1e-9));

      await bloc.close();
    });

    test('אינדקס מפורש פועל על טאב שאינו המוצג', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final current = leaf('נוכחי');
      final bloc = await blocWith([
        current,
        CombinedTab(rightTab: a, leftTab: b),
      ], current: 0);

      bloc.add(const SwapSideBySideTabs(tabIndex: 1));
      await bloc.stream.firstWhere(
        (s) => (s.tabs[1] as CombinedTab).rightTab == b,
      );

      expect((bloc.state.tabs[1] as CombinedTab).leftTab, same(a));
      // הטאב המוצג לא זז.
      expect(bloc.state.currentTabIndex, 0);

      await bloc.close();
    });

    test('טאב שאינו מפוצל אינו מושפע', () async {
      final plain = leaf('רגיל');
      final bloc = await blocWith([plain]);

      bloc.add(const SwapSideBySideTabs());
      await settle();

      expect(bloc.state.tabs, [same(plain)]);

      await bloc.close();
    });
  });

  group('UpdateSplitRatio', () {
    test('היחס משתנה במקום, בלי להחליף את אובייקט הטאב', () async {
      final combined = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב'));
      final bloc = await blocWith([combined]);

      bloc.add(const UpdateSplitRatio(0.75));
      await bloc.stream.first;

      expect(combined.splitRatio, 0.75);
      expect(bloc.state.currentTab, same(combined));

      await bloc.close();
    });

    test('טאב שאינו מפוצל בולע את האירוע', () async {
      final plain = leaf('רגיל');
      final bloc = await blocWith([plain]);

      bloc.add(const UpdateSplitRatio(0.75));
      await settle();

      expect(bloc.state.tabs, [same(plain)]);

      await bloc.close();
    });
  });

  group('ClosePane — סגירת חלונית', () {
    test('האחות תופסת את מקום הטאב המפוצל', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([CombinedTab(rightTab: a, leftTab: b)]);

      bloc.add(ClosePane(a));
      await bloc.stream.firstWhere((s) => s.currentTab is! CombinedTab);

      expect(bloc.state.tabs, [same(b)]);

      await bloc.close();
    });

    test('סגירת החלונית השנייה מותירה את הראשונה', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([CombinedTab(rightTab: a, leftTab: b)]);

      bloc.add(ClosePane(b));
      await bloc.stream.firstWhere((s) => s.currentTab is! CombinedTab);

      expect(bloc.state.tabs, [same(a)]);

      await bloc.close();
    });

    test('חלונית בטאב שאינו המוצג נסגרת בלי להזיז את הטאב הפעיל', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final current = leaf('נוכחי');
      final bloc = await blocWith([
        CombinedTab(rightTab: a, leftTab: b),
        current,
      ], current: 1);

      bloc.add(ClosePane(a));
      await bloc.stream.firstWhere((s) => s.tabs[0] is! CombinedTab);

      expect(bloc.state.tabs, [same(b), same(current)]);
      expect(bloc.state.currentTabIndex, 1);

      await bloc.close();
    });

    test('הצמדת הטאב המפוצל עוברת לאחות', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([
        CombinedTab(rightTab: a, leftTab: b, isPinned: true),
      ]);

      bloc.add(ClosePane(a));
      await bloc.stream.firstWhere((s) => s.currentTab is! CombinedTab);

      expect(bloc.state.tabs.single.isPinned, isTrue);

      await bloc.close();
    });

    test('חלונית שאינה בשום טאב מפוצל אינה משנה דבר', () async {
      final plain = leaf('רגיל');
      final stranger = leaf('זר');
      final bloc = await blocWith([plain]);

      bloc.add(ClosePane(stranger));
      await settle();

      expect(bloc.state.tabs, [same(plain)]);

      await bloc.close();
    });

    test('טאב שאינו מפוצל אינו נסגר דרך ClosePane', () async {
      final plain = leaf('רגיל');
      final bloc = await blocWith([plain]);

      bloc.add(ClosePane(plain));
      await settle();

      expect(bloc.state.tabs, [same(plain)]);

      await bloc.close();
    });
  });

  group('SetActivePane', () {
    test('חלונית של הטאב המוצג הופכת לפעילה', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([CombinedTab(rightTab: a, leftTab: b)]);

      bloc.add(SetActivePane(b));
      await bloc.stream.firstWhere((s) => identical(s.activePane, b));

      expect(bloc.state.activePane, same(b));

      await bloc.close();
    });

    test('חלונית מטאב אחר נדחית', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final other = leaf('אחר');
      final bloc = await blocWith([
        CombinedTab(rightTab: a, leftTab: b),
        other,
      ]);

      bloc.add(SetActivePane(other));
      await settle();

      expect(bloc.state.activePane, same(a));

      await bloc.close();
    });

    test('הטאב המפוצל עצמו אינו חלונית פעילה', () async {
      final a = leaf('א');
      final combined = CombinedTab(rightTab: a, leftTab: leaf('ב'));
      final bloc = await blocWith([combined]);

      bloc.add(SetActivePane(combined));
      await settle();

      expect(bloc.state.activePane, same(a));

      await bloc.close();
    });

    test('בטאב שאינו מפוצל החלונית הפעילה היא הטאב עצמו', () async {
      final plain = leaf('רגיל');
      final bloc = await blocWith([plain]);

      expect(bloc.state.activePane, same(plain));

      await bloc.close();
    });

    test('סגירת החלונית הפעילה מעבירה את הסימון לאחות', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([CombinedTab(rightTab: a, leftTab: b)]);

      bloc.add(SetActivePane(b));
      await bloc.stream.firstWhere((s) => identical(s.activePane, b));

      bloc.add(ClosePane(b));
      await bloc.stream.firstWhere((s) => s.currentTab is! CombinedTab);

      expect(bloc.state.activePane, same(a));

      await bloc.close();
    });
  });
}

class _FakeTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs() => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  SideBySideMode? loadSideBySideMode() => null;

  @override
  Future<void> saveTabs(
    List<OpenedTab> tabs,
    int currentTabIndex, [
    SideBySideMode? sideBySideMode,
  ]) async {}

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}
