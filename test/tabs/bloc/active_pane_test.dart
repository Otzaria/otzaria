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

/// "החלונית הפעילה" — מי מקבל פוקוס, מי נחשב הספר הפתוח, ולאן מכוונים ניווט
/// ואירועי תוספים.
///
/// היא נשמרת כזהות אובייקט ולא כמיקום, ולכן היא נוסעת עם החלונית בכל שינוי
/// מבנה: החלפת צדדים, סגירת אחות ופירוק. מיקום היה מצביע על ספר אחר.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab pdf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );

  Future<TabsBloc> blocWith(List<OpenedTab> tabs, {int current = 0}) async {
    final bloc = TabsBloc(repository: _FakeTabsRepository());
    bloc.add(ReplaceAllTabs(tabs, current));
    await bloc.stream.firstWhere((s) => s.tabs.length == tabs.length);
    return bloc;
  }

  group('נירמול', () {
    test('טאב שאינו מפוצל — החלונית הפעילה היא הטאב עצמו', () {
      final tab = pdf('בודד');
      final state = TabsState(tabs: [tab], currentTabIndex: 0);

      expect(state.activePane, same(tab));
    });

    test('בלי סימון מפורש נבחרת החלונית הראשונה', () {
      final first = pdf('א');
      final split = CombinedTab(rightTab: first, leftTab: pdf('ב'));
      final state = TabsState(tabs: [split], currentTabIndex: 0);

      expect(state.activePane, same(first));
    });

    test('חלונית מסומנת נשמרת', () {
      final second = pdf('ב');
      final split = CombinedTab(rightTab: pdf('א'), leftTab: second);
      final state = TabsState(
        tabs: [split],
        currentTabIndex: 0,
        rawActivePane: second,
      );

      expect(state.activePane, same(second));
    });

    test('הטאב המפוצל עצמו אינו חלונית פעילה', () {
      final split = CombinedTab(rightTab: pdf('א'), leftTab: pdf('ב'));
      final state = TabsState(
        tabs: [split],
        currentTabIndex: 0,
        rawActivePane: split,
      );

      expect(state.activePane!.title, 'א');
    });

    test('חלונית שנסגרה נופלת לראשונה ואינה קמה לתחייה', () {
      final closed = pdf('נסגרה');
      final survivor = pdf('נשארה');
      var state = TabsState(
        tabs: [CombinedTab(rightTab: survivor, leftTab: closed)],
        currentTabIndex: 0,
        rawActivePane: closed,
      );
      expect(state.activePane, same(closed));

      // הטאב חזר להיות חלונית אחת.
      state = state.copyWith(tabs: [survivor]);
      expect(state.activePane, same(survivor));

      // פיצול חדש אינו מחזיר את החלונית שנסגרה — נתיב היה "קם לתחייה" כאן.
      state = state.copyWith(
        tabs: [CombinedTab(rightTab: survivor, leftTab: pdf('חדש'))],
      );
      expect(state.activePane, same(survivor));
    });

    test('חלונית מטאב אחר אינה מסמנת ספר בטאב הנוכחי', () {
      final otherPane = pdf('בטאב אחר');
      final otherSplit = CombinedTab(rightTab: pdf('א'), leftTab: otherPane);
      final currentFirst = pdf('נוכחי א');
      final currentSplit = CombinedTab(
        rightTab: currentFirst,
        leftTab: pdf('נוכחי ב'),
      );

      // שני הטאבים באותו מבנה — כאן נתיב היה "תקין במקרה" ומצביע על ספר
      // שהמשתמש לא נגע בו.
      final state = TabsState(
        tabs: [currentSplit, otherSplit],
        currentTabIndex: 0,
        rawActivePane: otherPane,
      );

      expect(state.activePane, same(currentFirst));
    });

    test('בלי טאבים אין חלונית פעילה', () {
      const state = TabsState(tabs: [], currentTabIndex: 0);

      expect(state.activePane, isNull);
    });
  });

  group('SetActivePane', () {
    test('מסמן חלונית קיימת', () async {
      final second = pdf('ב');
      final split = CombinedTab(rightTab: pdf('א'), leftTab: second);
      final bloc = await blocWith([split]);
      expect(bloc.state.activePane!.title, 'א');

      bloc.add(SetActivePane(second));
      await bloc.stream.first;

      expect(bloc.state.activePane, same(second));

      await bloc.close();
    });

    test('חלונית שאינה בטאב המוצג נדחית', () async {
      final foreign = pdf('זר');
      final split = CombinedTab(rightTab: pdf('א'), leftTab: pdf('ב'));
      final bloc = await blocWith([split, foreign]);

      bloc.add(SetActivePane(foreign));
      await pumpEventQueue();

      expect(bloc.state.activePane!.title, 'א');

      await bloc.close();
    });

    test('הטאב המפוצל עצמו נדחה', () async {
      final split = CombinedTab(rightTab: pdf('א'), leftTab: pdf('ב'));
      final bloc = await blocWith([split]);

      bloc.add(SetActivePane(split));
      await pumpEventQueue();

      expect(bloc.state.rawActivePane, isNull);
      expect(bloc.state.activePane!.title, 'א');

      await bloc.close();
    });

    test('סימון חוזר של אותה חלונית אינו מייצר state חדש', () async {
      final second = pdf('ב');
      final split = CombinedTab(rightTab: pdf('א'), leftTab: second);
      final bloc = await blocWith([split]);
      final states = <TabsState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(SetActivePane(second));
      bloc.add(SetActivePane(second));
      await pumpEventQueue();

      expect(states, hasLength(1));

      await sub.cancel();
      await bloc.close();
    });

    test('הסימון אינו נשמר לדיסק', () async {
      final second = pdf('ב');
      final split = CombinedTab(rightTab: pdf('א'), leftTab: second);
      final repository = _FakeTabsRepository();
      final bloc = TabsBloc(repository: repository);
      bloc.add(ReplaceAllTabs([split], 0));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);
      final savesBefore = repository.saveCount;

      bloc.add(SetActivePane(second));
      await pumpEventQueue();

      expect(repository.saveCount, savesBefore, reason: 'מצב זמני, כמו בחירה');

      await bloc.close();
    });
  });

  group('הסימון נוסע עם החלונית', () {
    test('החלפת צדדים אינה מעבירה את הסימון לספר האחר', () async {
      final worked = pdf('עבדתי כאן');
      final split = CombinedTab(rightTab: pdf('א'), leftTab: worked);
      final bloc = await blocWith([split]);

      bloc.add(SetActivePane(worked));
      await bloc.stream.first;

      bloc.add(const SwapSideBySideTabs());
      await bloc.stream.first;

      // הצדדים התחלפו, והחלונית הפעילה היא אותה חלונית.
      expect(bloc.state.activePane, same(worked));
      expect((bloc.state.currentTab as CombinedTab).rightTab, same(worked));

      await bloc.close();
    });

    test('סגירת האחות משאירה את הסימון על החלונית שהתרחבה', () async {
      final worked = pdf('עבדתי כאן');
      final sibling = pdf('אחות');
      final bloc = await blocWith([
        CombinedTab(rightTab: sibling, leftTab: worked),
      ]);

      bloc.add(SetActivePane(worked));
      await bloc.stream.first;

      bloc.add(ClosePane(sibling));
      await bloc.stream.firstWhere((s) => s.currentTab is! CombinedTab);

      expect(bloc.state.activePane, same(worked));
      expect(bloc.state.currentTab, same(worked));

      await bloc.close();
    });

    test('סגירת החלונית הפעילה עוברת לאחות שנשארה', () async {
      final survivor = pdf('נשארת');
      final closing = pdf('נסגרת');
      final split = CombinedTab(rightTab: survivor, leftTab: closing);
      final bloc = await blocWith([split]);

      bloc.add(SetActivePane(closing));
      await bloc.stream.first;

      bloc.add(ClosePane(closing));
      await bloc.stream.firstWhere((s) => s.currentTab is! CombinedTab);

      expect(bloc.state.activePane, same(survivor));

      await bloc.close();
    });

    test('יצירת פיצול מסמנת את החלונית הראשונה שבו', () async {
      final target = pdf('יעד');
      final incoming = pdf('חדש');
      final bloc = await blocWith([target, incoming]);

      bloc.add(CreateCombinedTab(rightTab: incoming, leftTab: target));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      expect(bloc.state.activePane, same(incoming));

      await bloc.close();
    });

    test('מעבר לטאב מפוצל אחר ובחזרה אינו מבלבל בין הספרים', () async {
      final firstTabPane = pdf('טאב 0 ב');
      final first = CombinedTab(
        rightTab: pdf('טאב 0 א'),
        leftTab: firstTabPane,
      );
      final secondTabFirstPane = pdf('טאב 1 א');
      final second = CombinedTab(
        rightTab: secondTabFirstPane,
        leftTab: pdf('טאב 1 ב'),
      );
      final bloc = await blocWith([first, second]);

      bloc.add(SetActivePane(firstTabPane));
      await bloc.stream.first;

      bloc.add(const SetCurrentTab(1));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

      // החלונית המסומנת שייכת לטאב האחר, ולכן נבחרת הראשונה שבטאב המוצג.
      expect(bloc.state.activePane, same(secondTabFirstPane));

      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);

      expect(bloc.state.activePane, same(firstTabPane));

      await bloc.close();
    });

    test('פירוק הטאב מותיר חלונית פעילה תקינה', () async {
      final second = pdf('ב');
      final split = CombinedTab(rightTab: pdf('א'), leftTab: second);
      final bloc = await blocWith([split]);

      bloc.add(SetActivePane(second));
      await bloc.stream.first;

      bloc.add(const ExpandCombinedTab(0));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.activePane, same(bloc.state.currentTab));

      await bloc.close();
    });
  });
}

class _FakeTabsRepository extends TabsRepository {
  int saveCount = 0;

  @override
  List<OpenedTab> loadTabs() => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {
    saveCount++;
  }

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {
    saveCount++;
  }
}
