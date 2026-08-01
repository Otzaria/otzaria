import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:path/path.dart' as p;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TabsBloc side-by-side', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('מיזוג לתצוגה מפוצלת משמר את אותן חלוניות ואינו משחרר אותן', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final rightTab = _createTextTab('ספר ימין', categoryId: 1);
      final leftTab = _createTextTab('ספר שמאל', categoryId: 2);

      bloc.add(AddTab(rightTab));
      bloc.add(AddTab(leftTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      bloc.add(CreateCombinedTab(rightTab: rightTab, leftTab: leftTab));
      await bloc.stream.firstWhere(
        (s) => s.tabs.length == 1 && s.currentTab is CombinedTab,
      );

      final combinedTab = bloc.state.currentTab! as CombinedTab;
      expect(bloc.state.tabs, hasLength(1));

      // אותם אובייקטים נכנסים לטאב המפוצל: המפתח היציב של כל חלונית מעביר
      // את המסך שלה במקום לבנות אותו מחדש, ולכן מצב הקריאה נשמר. שכפול
      // היה מאבד אותו, ו-scrollController משותף בין שני מסכים חיים היה
      // קורס — מה שמונע כאן על ידי כך שהחלונית עוברת ולא משוכפלת.
      expect(combinedTab.rightTab, same(rightTab));
      expect(combinedTab.leftTab, same(leftTab));

      // המתנה מעבר לחלון השחרור הדחוי, שבו הקוד הישן היה הורג את הטאבים.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(rightTab.bloc.isClosed, isFalse);
      expect(leftTab.bloc.isClosed, isFalse);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('פירוק תצוגה מפוצלת מחזיר את אותן חלוניות לרשימה', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final rightTab = _createTextTab('ספר א', categoryId: 1);
      final leftTab = _createTextTab('ספר ב', categoryId: 2);

      bloc.add(AddTab(rightTab));
      bloc.add(AddTab(leftTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      bloc.add(CreateCombinedTab(rightTab: rightTab, leftTab: leftTab));
      await bloc.stream.firstWhere(
        (s) => s.tabs.length == 1 && s.currentTab is CombinedTab,
      );

      bloc.add(const ExpandCombinedTab(0));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs[0], same(rightTab));
      expect(bloc.state.tabs[1], same(leftTab));

      // שחרור הצומת העוטף היה הורג רקורסיבית את שתי החלוניות ששבו לרשימה.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(rightTab.bloc.isClosed, isFalse);
      expect(leftTab.bloc.isClosed, isFalse);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('פירוק מחזיר את החלוניות במקום הטאב המפוצל ולא בסופו', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final before = _createTextTab('לפני', categoryId: 1);
      final right = _createTextTab('ימין', categoryId: 2);
      final left = _createTextTab('שמאל', categoryId: 3);

      bloc.add(AddTab(before));
      bloc.add(AddTab(CombinedTab(rightTab: right, leftTab: left)));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      bloc.add(const ExpandCombinedTab(1));
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      expect(bloc.state.tabs, [same(before), same(right), same(left)]);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('TabsBloc open or focus', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('ממקד טאב טקסט קיים כשאותו ספר פתוח באותה כותרת', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final firstTab = _createTextTab('ספר א', index: 0, categoryId: 1)
        ..currentTitle.value = 'פרק א';
      final secondTab = _createTextTab('ספר ב', index: 0, categoryId: 2);

      bloc.add(AddTab(firstTab));
      bloc.add(AddTab(secondTab));
      // After both AddTabs: tabs=[first,second], currentTabIndex=1
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      final targetTab = _createTextTab('ספר א', index: 12, categoryId: 1);
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר א, פרק א'));
      // Focuses firstTab at index 0 — currentTabIndex changes from 1 to 0
      await bloc.stream.firstWhere(
        (s) => s.tabs.length == 2 && s.currentTabIndex == 0,
      );

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('פותח טאב חדש כשאותו ספר נפתח בכותרת אחרת', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = _createTextTab('ספר א', index: 0, categoryId: 1)
        ..currentTitle.value = 'פרק א';

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = _createTextTab('ספר א', index: 25, categoryId: 1);
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'פרק ב'));
      // No existing tab matches 'פרק ב' — a new tab is added
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTabIndex, 1);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test(
      'navigateToPositionIfReused ממקד טאב קיים של אותו ספר גם בכותרת אחרת',
      () async {
        final bloc = TabsBloc(repository: _FakeTabsRepository());
        final existingTab = _createTextTab('ספר א', index: 0, categoryId: 1)
          ..currentTitle.value = 'פרק א';

        bloc.add(AddTab(existingTab));
        await bloc.stream.firstWhere((s) => s.tabs.length == 1);

        final targetTab = _createTextTab('ספר א', index: 25, categoryId: 1);
        bloc.add(
          OpenOrFocusTab(
            targetTab,
            targetTitle: 'פרק ב',
            navigateToPositionIfReused: true,
          ),
        );
        // עם הדגל, ההתאמה לפי זהות הספר בלבד — הטאב הקיים ממוקד ומנווט,
        // לא נפתח טאב חדש. הטאב כבר פעיל באינדקס 0 ולכן אין emission חדש.
        await pumpEventQueue();

        expect(bloc.state.tabs, hasLength(1));
        expect(bloc.state.currentTabIndex, 0);

        await _closeBlocAndAllowDeferredDispose(bloc);
      },
    );

    test('ממקד טאב PDF קיים לפי כותרת גם אם העמוד שונה', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 10,
      )..currentTitle.value = 'שער ראשון';

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 14,
      );
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר PDF, שער ראשון'));
      // Tab is already active at index 0 — state.currentTabIndex stays 0, no new emission.
      // pumpEventQueue drains all microtasks to guarantee the handler has completed.
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ממקד CombinedTab כשאחת החלוניות תואמת', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final combinedTab = CombinedTab(
        rightTab: _createTextTab('ספר ימין', index: 0, categoryId: 1)
          ..currentTitle.value = 'פרק א',
        leftTab: _createTextTab('ספר שמאל', index: 0, categoryId: 2)
          ..currentTitle.value = 'פרק ג',
      );

      bloc.add(AddTab(combinedTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = _createTextTab('ספר שמאל', index: 99, categoryId: 2);
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר שמאל, פרק ג'));
      // CombinedTab is already active at index 0 — no state change.
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);
      expect(bloc.state.currentTab, same(combinedTab));

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ממקד טאב טקסט קיים גם בלי targetTitle לפי אינדקס', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = _createTextTab('ספר א', index: 12, categoryId: 1);

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = _createTextTab('ספר א', index: 12, categoryId: 1);
      bloc.add(OpenOrFocusTab(targetTab));
      // Tab is already active at index 0 — no state change.
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('לא ממקד ספר טקסט אחר כשיש רק התאמת כותרת ללא מזהה יציב', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = TextBookTab(
        book: TextBook(title: 'ספר זהה', categoryId: 1),
        index: 12,
      )..currentTitle.value = 'פרק א';

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = TextBookTab(
        book: TextBook(title: 'ספר זהה'),
        index: 12,
      );
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר זהה, פרק א'));
      // No stable identity match — a new tab is added
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTabIndex, 1);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('לא ממקד ספר אחר רק כי הוא באותה קטגוריה', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = TextBookTab(
        book: TextBook(
          id: 101,
          title: 'משנה ברכות',
          categoryId: 7,
        ),
        index: 0,
      );

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = TextBookTab(
        book: TextBook(
          id: 102,
          title: 'משנה פאה',
          categoryId: 7,
        ),
        index: 0,
      );
      bloc.add(OpenOrFocusTab(targetTab));
      // Different book IDs — a new tab is added
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTabIndex, 1);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ממקד טאב PDF קיים גם כשהכותרת עוד לא נטענה לפי מספר עמוד', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 10,
      );

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 10,
      );
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר PDF, שער ראשון'));
      // Tab already active at index 0 — no state change.
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ממקד טאב חיפוש קיים לפי dedupeKey גם בלי מזהה ספר יציב', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = TextBookTab(
        book: TextBook(title: 'ספר זהה'),
        index: 12,
        dedupeKey: 'search:text|ספר זהה|ספר זהה, פרק א|12',
      );

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = TextBookTab(
        book: TextBook(title: 'ספר זהה'),
        index: 12,
        dedupeKey: 'search:text|ספר זהה|ספר זהה, פרק א|12',
      );
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר זהה, פרק א'));
      // dedupeKey matches, tab already active at index 0 — no state change.
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('TabsBloc insert position', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test(
      'AddTab בברירת מחדל מוסיף לסוף הרשימה גם כשהטאב הנוכחי באמצע',
      () async {
        final bloc = TabsBloc(repository: _FakeTabsRepository());
        final first = _createTextTab('ספר א', categoryId: 1);
        final second = _createTextTab('ספר ב', categoryId: 2);
        final third = _createTextTab('ספר ג', categoryId: 3);

        bloc.add(AddTab(first));
        bloc.add(AddTab(second));
        bloc.add(AddTab(third));
        await bloc.stream.firstWhere((s) => s.tabs.length == 3);

        // ממקדים את הטאב באמצע (ספר ב) כדי לדמות "פתיחה מהאמצע"
        bloc.add(const SetCurrentTab(1));
        await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

        final libraryTab = _createTextTab('ספר ספרייה', categoryId: 4);
        bloc.add(AddTab(libraryTab));
        await bloc.stream.firstWhere((s) => s.tabs.length == 4);

        // ברירת המחדל היא הוספה לסוף הרשימה, לא סמוך לטאב הנוכחי.
        // זה מונע את הבאג שבו פתיחה מהספרייה אחרי פתיחה מהאמצע נדחפת לאמצע.
        expect(bloc.state.tabs.last.title, 'ספר ספרייה');
        expect(bloc.state.currentTabIndex, 3);

        await _closeBlocAndAllowDeferredDispose(bloc);
      },
    );

    test('AddTab עם insertAdjacent: true מכניס סמוך לטאב הנוכחי', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);
      final third = _createTextTab('ספר ג', categoryId: 3);

      bloc.add(AddTab(first));
      bloc.add(AddTab(second));
      bloc.add(AddTab(third));
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      bloc.add(const SetCurrentTab(1));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

      final commentator = _createTextTab('מפרש', categoryId: 5);
      bloc.add(AddTab(commentator, insertAdjacent: true));
      await bloc.stream.firstWhere((s) => s.tabs.length == 4);

      // cross-reference מתוך ספר פתוח נכנס סמוך לטאב הנוכחי (אינדקס 2)
      // ולא לסוף הרשימה.
      expect(bloc.state.tabs[2].title, 'מפרש');
      expect(bloc.state.currentTabIndex, 2);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test(
      'OpenOrFocusTab מעביר את insertAdjacent ל-AddTab כשהטאב חדש',
      () async {
        final bloc = TabsBloc(repository: _FakeTabsRepository());
        final first = _createTextTab('ספר א', categoryId: 1);
        final second = _createTextTab('ספר ב', categoryId: 2);
        final third = _createTextTab('ספר ג', categoryId: 3);

        bloc.add(AddTab(first));
        bloc.add(AddTab(second));
        bloc.add(AddTab(third));
        await bloc.stream.firstWhere((s) => s.tabs.length == 3);

        bloc.add(const SetCurrentTab(1));
        await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

        // בלי insertAdjacent — ברירת מחדל = הוספה בסוף
        final fromLibrary = _createTextTab('ספר ד', categoryId: 4);
        bloc.add(OpenOrFocusTab(fromLibrary));
        await bloc.stream.firstWhere((s) => s.tabs.length == 4);
        expect(bloc.state.tabs.last.title, 'ספר ד');
        expect(bloc.state.currentTabIndex, 3);

        // עם insertAdjacent: true — סמוך לטאב הנוכחי
        bloc.add(const SetCurrentTab(1));
        await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

        final crossRef = _createTextTab('מפרש ה', categoryId: 5);
        bloc.add(OpenOrFocusTab(crossRef, insertAdjacent: true));
        await bloc.stream.firstWhere((s) => s.tabs.length == 5);
        expect(bloc.state.tabs[2].title, 'מפרש ה');
        expect(bloc.state.currentTabIndex, 2);

        await _closeBlocAndAllowDeferredDispose(bloc);
      },
    );
  });

  // הגנת רגרסיה על הסיור המודרך: בעבר שלב "איתור מהיר" והקריאה סגרו את כל טאבי
  // הטקסט הפתוחים לפני פתיחת "בראשית" (כדי למנוע כפילות GlobalKeys). הסגירה
  // הוסרה מ-main_window_screen, והבטיחות מתבססת על כך שפתיחת הספר (ללא
  // insertAdjacent) משמרת את הטאבים הקיימים ומוסיפה את הספר בסוף הרשימה — כך
  // שב-PageView הוא מעובד אחרון וטאבי הטקסט הקיימים משחררים את מפתחות הסיור לפניו.
  group('TabsBloc — פתיחת ספר לסיור משמרת טאבים פתוחים', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test(
      'פתיחת בראשית לסיור לא סוגרת טאבי טקסט פתוחים ומוסיפה אותו בסוף',
      () async {
        final bloc = TabsBloc(repository: _FakeTabsRepository());
        final first = _createTextTab('ספר א', categoryId: 1);
        final second = _createTextTab('ספר ב', categoryId: 2);

        bloc.add(AddTab(first));
        bloc.add(AddTab(second));
        await bloc.stream.firstWhere((s) => s.tabs.length == 2);

        // כך הסיור פותח את בראשית: openBook → OpenOrFocusTab ללא insertAdjacent.
        final genesis = _createTextTab('בראשית', categoryId: 99);
        bloc.add(OpenOrFocusTab(genesis));
        await bloc.stream.firstWhere((s) => s.tabs.length == 3);

        expect(
          bloc.state.tabs.map((t) => t.title),
          containsAllInOrder(['ספר א', 'ספר ב']),
          reason: 'הטאבים שהמשתמש פתח לפני הסיור חייבים להישמר',
        );
        expect(
          bloc.state.tabs.last.title,
          'בראשית',
          reason:
              'בראשית מתווסף בסוף → מעובד אחרון ב-PageView ולא יוצר '
              'כפילות GlobalKeys',
        );
        expect(bloc.state.currentTabIndex, 2);

        await _closeBlocAndAllowDeferredDispose(bloc);
      },
    );

    test('פתיחת בראשית כשהוא כבר פתוח ממקדת אותו בלי לסגור או לשכפל', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final other = _createTextTab('ספר א', categoryId: 1);
      final genesis = _createTextTab('בראשית', index: 0, categoryId: 99);

      bloc.add(AddTab(other));
      bloc.add(AddTab(genesis));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      // ממקדים טאב אחר כדי לוודא שהפוקוס אכן חוזר לבראשית הקיים.
      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);

      // הסיור פותח שוב את בראשית (אותו ספר, אותו אינדקס) → התמקדות בקיים.
      final reopen = _createTextTab('בראשית', index: 0, categoryId: 99);
      bloc.add(OpenOrFocusTab(reopen));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

      expect(
        bloc.state.tabs,
        hasLength(2),
        reason: 'אסור לשכפל את בראשית או לסגור את הטאב האחר',
      );
      expect(bloc.state.currentTabIndex, 1);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('TabsBloc deferred dispose', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('סגירת טאב דוחה את dispose עד אחרי עדכון ה-state', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final searchTab = SearchingTab('חיפוש', 'בדיקה');

      bloc.add(AddTab(searchTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      bloc.add(RemoveTab(searchTab));
      await bloc.stream.firstWhere((s) => s.tabs.isEmpty);

      void titleListener() {}
      expect(
        () => searchTab.titleNotifier.addListener(titleListener),
        returnsNormally,
      );
      searchTab.titleNotifier.removeListener(titleListener);

      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        () => searchTab.titleNotifier.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );

      await bloc.close();
    });

    test(
      'ReplaceAllTabs לא משחרר את הטאבים הישנים לפני שה-UI מספיק להתנתק',
      () async {
        final bloc = TabsBloc(repository: _FakeTabsRepository());
        final oldTab = SearchingTab('חיפוש ישן', 'ישן');
        final newTab = SearchingTab('חיפוש חדש', 'חדש');

        bloc.add(AddTab(oldTab));
        await bloc.stream.firstWhere((s) => s.tabs.length == 1);

        bloc.add(ReplaceAllTabs([newTab], 0));
        await bloc.stream.firstWhere(
          (s) => s.tabs.length == 1 && identical(s.tabs.first, newTab),
        );

        void titleListener() {}
        expect(
          () => oldTab.titleNotifier.addListener(titleListener),
          returnsNormally,
        );
        oldTab.titleNotifier.removeListener(titleListener);

        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(
          () => oldTab.titleNotifier.addListener(() {}),
          throwsA(isA<FlutterError>()),
        );

        await _closeBlocAndAllowDeferredDispose(bloc);
      },
    );
  });

  group('TabsBloc remap book paths', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('RemapBookPaths ממפה נתיב PDF פתוח בזיכרון', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final pdf = PdfBookTab(
        book: PdfBook(title: 'ברכות', path: p.join('/lib', 'old', 'ברכות.pdf')),
        pageNumber: 1,
      );

      bloc.add(AddTab(pdf));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final newPath = p.join('/lib', 'new', 'ברכות.pdf');
      bloc.add(RemapBookPaths(p.join('/lib', 'old'), p.join('/lib', 'new')));
      await bloc.stream.firstWhere(
        (s) =>
            s.tabs.isNotEmpty &&
            (s.tabs.first as PdfBookTab).book.path == newPath,
      );

      expect((bloc.state.tabs.first as PdfBookTab).book.path, newPath);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test(
      'remapBookPathsAwaitable ממתין לסיום המיפוי (זיכרון + שמירה)',
      () async {
        final bloc = TabsBloc(repository: _FakeTabsRepository());
        final pdf = PdfBookTab(
          book: PdfBook(
            title: 'ברכות',
            path: p.join('/lib', 'old', 'ברכות.pdf'),
          ),
          pageNumber: 1,
        );

        bloc.add(AddTab(pdf));
        await bloc.stream.firstWhere((s) => s.tabs.length == 1);

        // ה-Future נפתר רק אחרי שה-state כבר עודכן — בלי race.
        await bloc.remapBookPathsAwaitable(
          p.join('/lib', 'old'),
          p.join('/lib', 'new'),
        );

        expect(
          (bloc.state.tabs.first as PdfBookTab).book.path,
          p.join('/lib', 'new', 'ברכות.pdf'),
        );

        await _closeBlocAndAllowDeferredDispose(bloc);
      },
    );

    test('remapBookPathsAwaitable נכשל אם שמירת הטאבים נכשלה', () async {
      final repo = _ThrowingSaveTabsRepository();
      final bloc = TabsBloc(repository: repo);
      final pdf = PdfBookTab(
        book: PdfBook(title: 'ברכות', path: p.join('/lib', 'old', 'ברכות.pdf')),
        pageNumber: 1,
      );

      bloc.add(AddTab(pdf));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      repo.armed = true;
      await expectLater(
        bloc.remapBookPathsAwaitable(
          p.join('/lib', 'old'),
          p.join('/lib', 'new'),
        ),
        throwsA(isA<Exception>()),
      );

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('RemapBookPaths לא משנה state כשאין נתיב תואם', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final pdf = PdfBookTab(
        book: PdfBook(title: 'אחר', path: p.join('/other', 'book.pdf')),
        pageNumber: 1,
      );

      bloc.add(AddTab(pdf));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);
      final before = bloc.state;

      bloc.add(RemapBookPaths(p.join('/lib', 'old'), p.join('/lib', 'new')));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(identical(bloc.state.tabs.first, pdf), isTrue);
      expect(bloc.state, same(before));

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('TabsBloc close active tab focus', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('סגירת הטאב הפעיל באמצע מעבירה לטאב הבא', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);
      final third = _createTextTab('ספר ג', categoryId: 3);

      bloc.add(AddTab(first));
      bloc.add(AddTab(second));
      bloc.add(AddTab(third));
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      bloc.add(const SetCurrentTab(1));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

      bloc.add(RemoveTab(second));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      // ספר ב היה באמצע — הפוקוס עובר לטאב הבא (ספר ג), שנכנס תחת אינדקס 1.
      expect(bloc.state.currentTabIndex, 1);
      expect(bloc.state.tabs[1].title, 'ספר ג');

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('סגירת הטאב הפעיל האחרון מעבירה לטאב שלפניו', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);

      bloc.add(AddTab(first));
      bloc.add(AddTab(second));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      // ספר ב פעיל ואחרון — אין טאב הבא, נופלים לטאב שלפניו.
      bloc.add(RemoveTab(second));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      expect(bloc.state.currentTabIndex, 0);
      expect(bloc.state.tabs[0].title, 'ספר א');

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('TabsBloc remove multiple tabs', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('RemoveTabs סוגר קבוצה ומשאיר את הטאב הפעיל ששרד', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);
      final third = _createTextTab('ספר ג', categoryId: 3);
      final fourth = _createTextTab('ספר ד', categoryId: 4);

      bloc.add(AddTab(first));
      bloc.add(AddTab(second));
      bloc.add(AddTab(third));
      bloc.add(AddTab(fourth));
      await bloc.stream.firstWhere((s) => s.tabs.length == 4);

      bloc.add(const SetCurrentTab(2));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 2);

      bloc.add(RemoveTabs([first, fourth]));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs.map((t) => t.title), ['ספר ב', 'ספר ג']);
      expect(bloc.state.currentTab, same(third));

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('RemoveTabs שכולל את הטאב הפעיל מעביר לטאב הסמוך ששרד', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);
      final third = _createTextTab('ספר ג', categoryId: 3);

      bloc.add(AddTab(first));
      bloc.add(AddTab(second));
      bloc.add(AddTab(third));
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      bloc.add(const SetCurrentTab(1));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

      bloc.add(RemoveTabs([first, second]));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      expect(bloc.state.tabs.single.title, 'ספר ג');
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('RemoveTabs של כל הטאבים מרוקן את הרשימה בלי לקרוס', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);

      bloc.add(AddTab(first));
      bloc.add(AddTab(second));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      bloc.add(RemoveTabs([first, second]));
      await bloc.stream.firstWhere((s) => s.tabs.isEmpty);

      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('RemoveTabs מתעלם מטאבים שכבר אינם ברשימה', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);
      final ghost = _createTextTab('רפאים', categoryId: 9);

      bloc.add(AddTab(first));
      bloc.add(AddTab(second));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      bloc.add(RemoveTabs([second, ghost]));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      expect(bloc.state.tabs.single, same(first));
      ghost.dispose();

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('שחזור אחרי RemoveTabs מחזיר את הטאבים שנסגרו', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);
      final third = _createTextTab('ספר ג', categoryId: 3);

      bloc.add(AddTab(first));
      bloc.add(AddTab(second));
      bloc.add(AddTab(third));
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      bloc.add(RemoveTabs([first, second]));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      bloc.add(const RestoreLastClosedTab());
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);
      bloc.add(const RestoreLastClosedTab());
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      expect(
        bloc.state.tabs.map((t) => t.title).toList(),
        ['ספר א', 'ספר ב', 'ספר ג'],
      );

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('TabsBloc tab selection', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    Future<TabsBloc> createBlocWithTabs(List<TextBookTab> tabs) async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      for (final tab in tabs) {
        bloc.add(AddTab(tab));
      }
      await bloc.stream.firstWhere((s) => s.tabs.length == tabs.length);
      return bloc;
    }

    test('ToggleTabSelection ראשון מצרף גם את הכרטיסיה הפעילה', () async {
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);
      final third = _createTextTab('ספר ג', categoryId: 3);
      final bloc = await createBlocWithTabs([first, second, third]);

      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);

      bloc.add(ToggleTabSelection(third));
      await bloc.stream.firstWhere((s) => s.selectedTabs.isNotEmpty);

      expect(bloc.state.selectedTabs, containsAll([first, third]));
      expect(bloc.state.selectedTabs, hasLength(2));

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('הסרה שמותירה כרטיסיה בודדת מפרקת את הבחירה', () async {
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);
      final bloc = await createBlocWithTabs([first, second]);

      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);

      bloc.add(ToggleTabSelection(second));
      await bloc.stream.firstWhere((s) => s.selectedTabs.length == 2);

      bloc.add(ToggleTabSelection(second));
      await bloc.stream.firstWhere((s) => s.selectedTabs.isEmpty);

      expect(bloc.state.selectedTabs, isEmpty);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('SelectTabRange בוחר טווח מהכרטיסיה הפעילה', () async {
      final tabs = [
        _createTextTab('ספר א', categoryId: 1),
        _createTextTab('ספר ב', categoryId: 2),
        _createTextTab('ספר ג', categoryId: 3),
        _createTextTab('ספר ד', categoryId: 4),
      ];
      final bloc = await createBlocWithTabs(tabs);

      bloc.add(const SetCurrentTab(1));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

      bloc.add(SelectTabRange(tabs[3]));
      await bloc.stream.firstWhere((s) => s.selectedTabs.isNotEmpty);

      expect(bloc.state.selectedTabs, [tabs[1], tabs[2], tabs[3]]);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ClearTabSelection מנקה את הבחירה', () async {
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);
      final bloc = await createBlocWithTabs([first, second]);

      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);
      bloc.add(ToggleTabSelection(second));
      await bloc.stream.firstWhere((s) => s.selectedTabs.isNotEmpty);

      bloc.add(const ClearTabSelection());
      await bloc.stream.firstWhere((s) => s.selectedTabs.isEmpty);

      expect(bloc.state.selectedTabs, isEmpty);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('CloseCurrentTab סוגר את כל הקבוצה כשהפעילה נבחרה', () async {
      final tabs = [
        _createTextTab('ספר א', categoryId: 1),
        _createTextTab('ספר ב', categoryId: 2),
        _createTextTab('ספר ג', categoryId: 3),
      ];
      final bloc = await createBlocWithTabs(tabs);

      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);

      bloc.add(ToggleTabSelection(tabs[1]));
      await bloc.stream.firstWhere((s) => s.selectedTabs.length == 2);

      // Ctrl+W: הכרטיסיה הפעילה בבחירה — הקיצור סוגר את כל הקבוצה.
      bloc.add(const CloseCurrentTab());
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      expect(bloc.state.tabs.single.title, 'ספר ג');
      expect(bloc.state.selectedTabs, isEmpty);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('CloseCurrentTab סוגר רק את הפעילה כשאינה חלק מהבחירה', () async {
      final tabs = [
        _createTextTab('ספר א', categoryId: 1),
        _createTextTab('ספר ב', categoryId: 2),
        _createTextTab('ספר ג', categoryId: 3),
      ];
      final bloc = await createBlocWithTabs(tabs);

      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);
      bloc.add(ToggleTabSelection(tabs[1]));
      await bloc.stream.firstWhere((s) => s.selectedTabs.length == 2);

      // מעבר לכרטיסיה שמחוץ לבחירה — הקיצור סוגר רק אותה.
      bloc.add(const SetCurrentTab(2));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 2);

      bloc.add(const CloseCurrentTab());
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs.map((t) => t.title), ['ספר א', 'ספר ב']);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('RemoveTab שמותיר נבחרת יחידה מפרק את הבחירה כולה', () async {
      final tabs = [
        _createTextTab('ספר א', categoryId: 1),
        _createTextTab('ספר ב', categoryId: 2),
        _createTextTab('ספר ג', categoryId: 3),
      ];
      final bloc = await createBlocWithTabs(tabs);

      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);
      bloc.add(ToggleTabSelection(tabs[1]));
      await bloc.stream.firstWhere((s) => s.selectedTabs.length == 2);

      // "העבר לשולחן עבודה" שולח RemoveTab; הנבחרת שנותרה לבדה אינה קבוצה.
      bloc.add(RemoveTab(tabs[1]));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.selectedTabs, isEmpty);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ReplaceTab מנרמל את הבחירה מול הטאב המוחלף', () async {
      final tabs = [
        _createTextTab('ספר א', categoryId: 1),
        _createTextTab('ספר ב', categoryId: 2),
      ];
      final bloc = await createBlocWithTabs(tabs);

      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);
      bloc.add(ToggleTabSelection(tabs[1]));
      await bloc.stream.firstWhere((s) => s.selectedTabs.length == 2);

      final replacement = _createTextTab('ספר ב מעודכן', categoryId: 2);
      bloc.add(ReplaceTab(oldTab: tabs[1], newTab: replacement));
      await bloc.stream.firstWhere((s) => identical(s.tabs[1], replacement));

      expect(
        bloc.state.selectedTabs,
        isEmpty,
        reason: 'המוחלף יצא מהבחירה והקבוצה שנותרה בת אחת מתפרקת',
      );

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('CreateCombinedTab מנרמל בחירה שכללה את הטאבים שאוחדו', () async {
      final tabs = [
        _createTextTab('ספר א', categoryId: 1),
        _createTextTab('ספר ב', categoryId: 2),
        _createTextTab('ספר ג', categoryId: 3),
      ];
      final bloc = await createBlocWithTabs(tabs);

      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);
      bloc.add(SelectTabRange(tabs[2]));
      await bloc.stream.firstWhere((s) => s.selectedTabs.length == 3);

      bloc.add(CreateCombinedTab(rightTab: tabs[0], leftTab: tabs[1]));
      await bloc.stream.firstWhere((s) => s.currentTab is CombinedTab);

      expect(
        bloc.state.selectedTabs,
        isEmpty,
        reason: 'שני הטאבים שאוחדו הוחלפו ב-CombinedTab; נותרה אחת — מתפרקת',
      );

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('RemoveTab מנקה את הכרטיסיה שנסגרה מהבחירה', () async {
      final tabs = [
        _createTextTab('ספר א', categoryId: 1),
        _createTextTab('ספר ב', categoryId: 2),
        _createTextTab('ספר ג', categoryId: 3),
      ];
      final bloc = await createBlocWithTabs(tabs);

      bloc.add(const SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);
      bloc.add(SelectTabRange(tabs[2]));
      await bloc.stream.firstWhere((s) => s.selectedTabs.length == 3);

      bloc.add(RemoveTab(tabs[1]));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.selectedTabs, [tabs[0], tabs[2]]);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('TabsBloc restore closed tab', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test(
      'משחזר את הטאב האחרון שנסגר לאינדקס המקורי ומעביר אליו פוקוס',
      () async {
        final bloc = TabsBloc(repository: _FakeTabsRepository());
        final first = _createTextTab('ספר א', categoryId: 1);
        final second = _createTextTab('ספר ב', index: 14, categoryId: 2);
        final third = _createTextTab('ספר ג', categoryId: 3);

        bloc.add(AddTab(first));
        bloc.add(AddTab(second));
        bloc.add(AddTab(third));
        await bloc.stream.firstWhere((s) => s.tabs.length == 3);

        bloc.add(RemoveTab(second));
        await bloc.stream.firstWhere(
          (s) => s.tabs.length == 2 && s.tabs.every((tab) => tab != second),
        );

        bloc.add(const RestoreLastClosedTab());
        await bloc.stream.firstWhere(
          (s) =>
              s.tabs.length == 3 &&
              s.currentTabIndex == 1 &&
              s.tabs[1].title == 'ספר ב',
        );

        expect(bloc.state.tabs[1], isA<TextBookTab>());
        expect((bloc.state.tabs[1] as TextBookTab).index, 14);

        await _closeBlocAndAllowDeferredDispose(bloc);
      },
    );

    test('שחזור סדרתי פותח קודם את האחרון שנסגר ואז את זה שלפניו', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final first = _createTextTab('ספר א', categoryId: 1);
      final second = _createTextTab('ספר ב', categoryId: 2);
      final third = _createTextTab('ספר ג', categoryId: 3);

      bloc.add(AddTab(first));
      bloc.add(AddTab(second));
      bloc.add(AddTab(third));
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      bloc.add(RemoveTab(third));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      bloc.add(RemoveTab(second));
      await bloc.stream.firstWhere(
        (s) => s.tabs.length == 1 && s.tabs.single.title == 'ספר א',
      );

      bloc.add(const RestoreLastClosedTab());
      await bloc.stream.firstWhere(
        (s) =>
            s.tabs.length == 2 &&
            s.currentTabIndex == 1 &&
            s.tabs[1].title == 'ספר ב',
      );

      bloc.add(const RestoreLastClosedTab());
      await bloc.stream.firstWhere(
        (s) =>
            s.tabs.length == 3 &&
            s.currentTabIndex == 2 &&
            s.tabs[2].title == 'ספר ג',
      );

      expect(
        bloc.state.tabs.map((tab) => tab.title).toList(),
        ['ספר א', 'ספר ב', 'ספר ג'],
      );

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('TabsBloc replace tab', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test(
      'ReplaceTab מחליף את הטאב באותו מיקום ושומר את האינדקס הנוכחי',
      () async {
        final bloc = TabsBloc(repository: _FakeTabsRepository());
        final first = _createTextTab('ספר א', categoryId: 1);
        final placeholder = ResolvingTab(
          fallbackTab: _createTextTab('ברכות', categoryId: 2),
          resolve: () async => _createTextTab('ברכות', categoryId: 2),
        );
        final third = _createTextTab('ספר ג', categoryId: 3);

        bloc.add(AddTab(first));
        bloc.add(AddTab(placeholder));
        bloc.add(AddTab(third));
        await bloc.stream.firstWhere((s) => s.tabs.length == 3);

        bloc.add(SetCurrentTab(0));
        await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);

        final resolved = _createTextTab('ברכות', index: 7, categoryId: 2);
        bloc.add(ReplaceTab(oldTab: placeholder, newTab: resolved));
        await bloc.stream.firstWhere((s) => identical(s.tabs[1], resolved));

        expect(bloc.state.tabs, hasLength(3));
        expect(bloc.state.currentTabIndex, 0);
        expect(bloc.state.tabs.map((tab) => tab.title).toList(), [
          'ספר א',
          'ברכות',
          'ספר ג',
        ]);

        await _closeBlocAndAllowDeferredDispose(bloc);
      },
    );

    test('ReplaceTab על טאב שכבר נסגר לא מוסיף את הטאב החדש', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final first = _createTextTab('ספר א', categoryId: 1);
      final placeholder = ResolvingTab(
        fallbackTab: _createTextTab('ברכות', categoryId: 2),
        resolve: () async => _createTextTab('ברכות', categoryId: 2),
      );

      bloc.add(AddTab(first));
      bloc.add(AddTab(placeholder));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      bloc.add(RemoveTab(placeholder));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      bloc.add(
        ReplaceTab(
          oldTab: placeholder,
          newTab: _createTextTab('ברכות', categoryId: 2),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.tabs.single.title, 'ספר א');

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('ResolvingTab', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('ensureResolved ממוזכר — הרזולוציה רצה פעם אחת בלבד', () async {
      var calls = 0;
      final tab = ResolvingTab(
        fallbackTab: _createTextTab('ברכות', categoryId: 2),
        resolve: () async {
          calls++;
          return _createTextTab('ברכות', categoryId: 2);
        },
      );

      final firstResult = await tab.ensureResolved();
      final secondResult = await tab.ensureResolved();

      expect(calls, 1);
      expect(identical(firstResult, secondResult), isTrue);
      firstResult.dispose();
      tab.dispose();
    });

    test('כשל ברזולוציה נופל לעותק של טאב היעד החלופי', () async {
      final tab = ResolvingTab(
        fallbackTab: _createTextTab('ברכות', index: 5, categoryId: 2),
        resolve: () async => throw Exception('mapping failed'),
      );

      final resolved = await tab.ensureResolved();

      expect(resolved, isA<TextBookTab>());
      expect(resolved.title, 'ברכות');
      expect((resolved as TextBookTab).index, 5);
      expect(identical(resolved, tab.fallbackTab), isFalse);
      resolved.dispose();
      tab.dispose();
    });

    test('שמירה ושחזור עוברים דרך טאב היעד החלופי', () async {
      final tab = ResolvingTab(
        fallbackTab: _createTextTab('ברכות', index: 12, categoryId: 2),
        resolve: () async => _createTextTab('ברכות', categoryId: 2),
      );

      final json = tab.toJson();
      expect(json['type'], 'TextBookTab');
      expect(json['initalIndex'], 12);

      final clone = OpenedTab.from(tab);
      expect(clone, isA<TextBookTab>());
      expect(clone.title, 'ברכות');
      clone.dispose();
      tab.dispose();
    });
  });

  group('OpenedTab.from for search tabs', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('משכפל SearchingTab למופע חדש עם controllers חדשים', () {
      final original = SearchingTab('חיפוש: שבת', 'שבת');
      original.searchOptions['שבת_0'] = {'קידומות': true};
      original.alternativeWords[0] = ['שבתות'];
      original.spacingValues['0-1'] = '2';

      final cloned = OpenedTab.from(original) as SearchingTab;

      expect(cloned, isNot(same(original)));
      expect(cloned.queryController, isNot(same(original.queryController)));
      expect(
        cloned.searchFieldFocusNode,
        isNot(same(original.searchFieldFocusNode)),
      );
      expect(cloned.queryController.text, original.queryController.text);
      expect(cloned.searchOptions, isNot(same(original.searchOptions)));
      expect(cloned.searchOptions['שבת_0']?['קידומות'], isTrue);
      expect(cloned.alternativeWords[0], ['שבתות']);
      expect(cloned.spacingValues['0-1'], '2');

      original.dispose();

      expect(
        () => cloned.queryController.addListener(() {}),
        returnsNormally,
      );

      cloned.dispose();
    });

    test('TextBookTab משמר pinpointHighlight ו-section index בעת clone', () {
      final original = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 12,
        pinpointHighlight: 'אור',
        pinpointHighlightSectionIndex: 7,
      );

      final cloned = OpenedTab.from(original) as TextBookTab;

      expect(cloned.pinpointHighlight, 'אור');
      expect(
        cloned.pinpointHighlightSectionIndex,
        7,
        reason:
            'בעת clone או side-by-side חייבים לשמר את הסעיף שעליו הוחלה ההדגשה, אחרת ההדגשה תיעלם או תופיע בסעיף שגוי.',
      );

      original.dispose();
      cloned.dispose();
    });

    test('TextBookTab משמר צורת הדף ותצוגה מפוצלת גם כשה-bloc לא נטען', () {
      // תרחיש החלפת שולחן עבודה: הטאב השמור מעולם לא הוצג (state נשאר
      // TextBookInitial), ובחזרה אליו הוא משוכפל שוב.
      final original = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 3,
        splitedView: false,
        showPageShapeView: true,
        openLeftPane: true,
      );

      final cloned = OpenedTab.from(original) as TextBookTab;
      final clonedState = cloned.bloc.state as TextBookInitial;

      expect(
        clonedState.showPageShapeView,
        isTrue,
        reason:
            'טאב בשולחן עבודה לא-פעיל נשאר ב-TextBookInitial; בלי קריאת הערכים ממנו צורת הדף מתאפסת בכל החלפת שולחן עבודה.',
      );
      expect(clonedState.splitedView, isFalse);
      expect(clonedState.showLeftPane, isTrue);

      original.dispose();
      cloned.dispose();
    });

    test('TextBookTab.toJson משמר מפרשים ו-showLeftPane כשה-bloc לא נטען', () {
      // saveWorkspaces מסריאלת גם טאבים של שולחנות לא-פעילים שמעולם לא נטענו;
      // בלי נפילה לערכי הטאב הם היו נשמרים לדיסק עם [] ו-false.
      final tab = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 3,
        commentators: ['רש"י'],
        openLeftPane: true,
        splitedView: false,
        showPageShapeView: true,
      );

      final json = tab.toJson();

      expect(json['commentators'], ['רש"י']);
      expect(json['showLeftPane'], isTrue);
      expect(json['showPageShapeView'], isTrue);
      expect(json['splitedView'], isFalse);

      tab.dispose();
    });

    test('TextBookTab dispose משחרר גם את openNotesTabNotifier', () {
      final tab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 0,
      );

      tab.dispose();

      expect(
        () => tab.openNotesTabNotifier.addListener(() {}),
        throwsA(isA<FlutterError>()),
        reason:
            'ה-notifier נוסף בסטייט של הטאב וחייב להשתחרר יחד איתו כדי לא להשאיר מאזינים דולפים.',
      );
    });
  });

  group('OpenOrFocusTab עם highlight על טאב קיים', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test(
      'מחיל ApplyMarkHighlight על ה-bloc של הטאב הקיים במקום לפתוח טאב חדש',
      () async {
        final tabsBloc = TabsBloc(repository: _FakeTabsRepository());

        final existingBloc = _createLoadedTextBookBloc(
          book: TextBook(id: 42, title: 'בראשית'),
          initialIndex: 5,
        );
        await existingBloc.stream.firstWhere((s) => s is TextBookLoaded);

        final existingTab = TextBookTab(
          book: TextBook(id: 42, title: 'בראשית'),
          index: 5,
          blocOverride: existingBloc,
        );

        tabsBloc.add(AddTab(existingTab));
        await tabsBloc.stream.firstWhere((s) => s.tabs.length == 1);

        // אותו ספר מגיע מ‑deep link עם הדגשה ממוקדת לסעיף 5.
        final incomingTab = TextBookTab(
          book: TextBook(id: 42, title: 'בראשית'),
          index: 5,
          highlightText: 'אור',
          permanentHighlightLine: 5,
        );

        tabsBloc.add(OpenOrFocusTab(incomingTab));

        // ה-bloc של הטאב הקיים אמור לקבל ApplyMarkHighlight ולעדכן state.
        final updated =
            await existingBloc.stream
                    .firstWhere(
                      (s) => s is TextBookLoaded && s.highlightText == 'אור',
                    )
                    .timeout(const Duration(seconds: 2))
                as TextBookLoaded;

        expect(updated.permanentHighlightLine, 5);
        expect(updated.highlightText, 'אור');
        expect(
          tabsBloc.state.tabs,
          hasLength(1),
          reason: 'אסור להוסיף טאב חדש; הטאב הקיים אמור להתעדכן.',
        );
        expect(tabsBloc.state.currentTabIndex, 0);

        await _closeBlocAndAllowDeferredDispose(tabsBloc);
      },
    );

    test(
      'מחיל ApplyMarkHighlight כש‑bloc הקיים עדיין ב‑Initial וטוען רק אחרי כן',
      () async {
        final tabsBloc = TabsBloc(repository: _FakeTabsRepository());

        // bloc חדש שעדיין לא טען — נשאר ב‑TextBookInitial עד שנוסיף LoadContent.
        final repository = _PinpointFakeTextBookRepository();
        final existingBloc = TextBookBloc(
          repository: repository,
          initialState: TextBookInitial.named(
            TextBook(id: 99, title: 'שמות'),
            3,
            false,
            const [],
          ),
          scrollController: ItemScrollController(),
          positionsListener: ItemPositionsListener.create(),
        );

        final existingTab = TextBookTab(
          book: TextBook(id: 99, title: 'שמות'),
          index: 3,
          blocOverride: existingBloc,
        );
        tabsBloc.add(AddTab(existingTab));
        await tabsBloc.stream.firstWhere((s) => s.tabs.length == 1);

        // ההדגשה נשלחת לפני שה‑bloc הגיע ל‑Loaded — חייב להישאר ולהיות
        // מוחל ברגע שה‑Loaded מגיע.
        final incomingTab = TextBookTab(
          book: TextBook(id: 99, title: 'שמות'),
          index: 3,
          highlightText: 'משה',
          permanentHighlightLine: 3,
        );
        tabsBloc.add(OpenOrFocusTab(incomingTab));

        // עכשיו טוענים את התוכן — ה‑bloc יעבור ל‑Loaded וה‑pending יוחל.
        existingBloc.add(
          const LoadContent(
            fontSize: 20,
            showSplitView: false,
            removeNikud: false,
            loadCommentators: false,
          ),
        );

        final updated =
            await existingBloc.stream
                    .firstWhere(
                      (s) => s is TextBookLoaded && s.highlightText == 'משה',
                    )
                    .timeout(const Duration(seconds: 2))
                as TextBookLoaded;

        expect(updated.permanentHighlightLine, 3);
        expect(updated.highlightText, 'משה');
        expect(tabsBloc.state.tabs, hasLength(1));

        await _closeBlocAndAllowDeferredDispose(tabsBloc);
      },
    );

    // הגנה על האיחוד של שני מסלולי ה-highlight ב-_propagatePinpointHighlightToExistingTab.
    // הטסטים מעלינו מכסים רק את highlightText/permanentHighlightLine. כאן
    // בודקים שגם pinpointHighlight (המסלול שהיה נפרד לפני האיחוד) ממשיך לעבוד.
    // הערה: בזרימה אמיתית tab.index == pinpointHighlightSectionIndex (ראה
    // book_open_coordinator.dart) ולכן הטאבים תואמים ב-_findMatchingTopLevelTabIndex.
    test(
      'pinpointHighlight על טאב קיים — מוחל באמצעות pinpointHighlightSectionIndex',
      () async {
        final tabsBloc = TabsBloc(repository: _FakeTabsRepository());

        final existingBloc = _createLoadedTextBookBloc(
          book: TextBook(id: 77, title: 'ויקרא'),
          initialIndex: 8,
        );
        await existingBloc.stream.firstWhere((s) => s is TextBookLoaded);

        final existingTab = TextBookTab(
          book: TextBook(id: 77, title: 'ויקרא'),
          index: 8,
          blocOverride: existingBloc,
        );
        tabsBloc.add(AddTab(existingTab));
        await tabsBloc.stream.firstWhere((s) => s.tabs.length == 1);

        // pinpoint לסעיף 8 (כפי שזורם מ-coordinator: tab.index == sectionIndex).
        final incomingTab = TextBookTab(
          book: TextBook(id: 77, title: 'ויקרא'),
          index: 8,
          pinpointHighlight: 'אהרן',
          pinpointHighlightSectionIndex: 8,
        );
        tabsBloc.add(OpenOrFocusTab(incomingTab));

        final updated =
            await existingBloc.stream
                    .firstWhere(
                      (s) => s is TextBookLoaded && s.highlightText == 'אהרן',
                    )
                    .timeout(const Duration(seconds: 2))
                as TextBookLoaded;

        expect(updated.highlightText, 'אהרן');
        expect(updated.permanentHighlightLine, 8);
        expect(tabsBloc.state.tabs, hasLength(1));

        await _closeBlocAndAllowDeferredDispose(tabsBloc);
      },
    );

    test(
      'pinpointHighlight בלי sectionIndex — נופל ל-incomingTab.index',
      () async {
        final tabsBloc = TabsBloc(repository: _FakeTabsRepository());

        final existingBloc = _createLoadedTextBookBloc(
          book: TextBook(id: 88, title: 'במדבר'),
          initialIndex: 4,
        );
        await existingBloc.stream.firstWhere((s) => s is TextBookLoaded);

        final existingTab = TextBookTab(
          book: TextBook(id: 88, title: 'במדבר'),
          index: 4,
          blocOverride: existingBloc,
        );
        tabsBloc.add(AddTab(existingTab));
        await tabsBloc.stream.firstWhere((s) => s.tabs.length == 1);

        // pinpointHighlight ללא sectionIndex — fallback ל-incomingTab.index.
        // מגן על הענף `?? incomingTab.index` ב-_propagatePinpointHighlightToExistingTab.
        final incomingTab = TextBookTab(
          book: TextBook(id: 88, title: 'במדבר'),
          index: 4,
          pinpointHighlight: 'מסע',
        );
        tabsBloc.add(OpenOrFocusTab(incomingTab));

        final updated =
            await existingBloc.stream
                    .firstWhere(
                      (s) => s is TextBookLoaded && s.highlightText == 'מסע',
                    )
                    .timeout(const Duration(seconds: 2))
                as TextBookLoaded;

        expect(
          updated.permanentHighlightLine,
          4,
          reason: 'כשאין sectionIndex, נופלים ל-incomingTab.index',
        );

        await _closeBlocAndAllowDeferredDispose(tabsBloc);
      },
    );

    test('pinpointHighlight גובר על highlightText כששניהם קיימים', () async {
      final tabsBloc = TabsBloc(repository: _FakeTabsRepository());

      final existingBloc = _createLoadedTextBookBloc(
        book: TextBook(id: 55, title: 'דברים'),
      );
      await existingBloc.stream.firstWhere((s) => s is TextBookLoaded);

      final existingTab = TextBookTab(
        book: TextBook(id: 55, title: 'דברים'),
        index: 0,
        blocOverride: existingBloc,
      );
      tabsBloc.add(AddTab(existingTab));
      await tabsBloc.stream.firstWhere((s) => s.tabs.length == 1);

      // שניהם קיימים — pinpoint אמור לזכות (סדר עדיפות).
      final incomingTab = TextBookTab(
        book: TextBook(id: 55, title: 'דברים'),
        index: 0,
        pinpointHighlight: 'pinpoint-value',
        pinpointHighlightSectionIndex: 3,
        highlightText: 'mark-value',
        permanentHighlightLine: 9,
      );
      tabsBloc.add(OpenOrFocusTab(incomingTab));

      final updated =
          await existingBloc.stream
                  .firstWhere(
                    (s) => s is TextBookLoaded && s.highlightText.isNotEmpty,
                  )
                  .timeout(const Duration(seconds: 2))
              as TextBookLoaded;

      expect(
        updated.highlightText,
        'pinpoint-value',
        reason: 'pinpoint גובר על mark',
      );
      expect(
        updated.permanentHighlightLine,
        3,
        reason: 'sectionIndex של pinpoint גובר על permanentHighlightLine',
      );

      await _closeBlocAndAllowDeferredDispose(tabsBloc);
    });
  });
}

TextBookBloc _createLoadedTextBookBloc({
  required TextBook book,
  int initialIndex = 0,
}) {
  final bloc = TextBookBloc(
    repository: _PinpointFakeTextBookRepository(),
    initialState: TextBookInitial.named(book, initialIndex, false, const []),
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
  bloc.add(
    const LoadContent(
      fontSize: 20,
      showSplitView: false,
      removeNikud: false,
      loadCommentators: false,
    ),
  );
  return bloc;
}

class _PinpointFakeTextBookRepository extends TextBookRepository {
  _PinpointFakeTextBookRepository()
    : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async {
    return List.generate(20, (index) => 'שורה $index').join('\n');
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
}

TextBookTab _createTextTab(String title, {int index = 0, int? categoryId}) {
  return TextBookTab(
    book: TextBook(title: title, categoryId: categoryId),
    index: index,
  );
}

/// Closes the bloc and waits for deferred tab disposal (350 ms timers) to settle.
Future<void> _closeBlocAndAllowDeferredDispose(TabsBloc bloc) async {
  await bloc.close();
  await Future<void>.delayed(const Duration(milliseconds: 400));
}

class _FakeTabsRepository extends TabsRepository {
  List<Map<String, dynamic>> _tabsJson = const [];
  int _currentTabIndex = 0;

  @override
  List<OpenedTab> loadTabs() =>
      _tabsJson.map((tab) => TextBookTab.fromJson(tab)).toList();

  @override
  int loadCurrentTabIndex() => _currentTabIndex;

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {
    _tabsJson = tabs
        .map<Map<String, dynamic>>((tab) => tab.toJson())
        .toList(growable: false);
    _currentTabIndex = currentTabIndex;
  }

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {
    _currentTabIndex = currentTabIndex;
  }
}

/// כמו _FakeTabsRepository אך זורק ב-saveTabs כשהוא "חמוש" — לבדיקת התפשטות
/// כשל שמירה דרך ה-Future של remapBookPathsAwaitable.
class _ThrowingSaveTabsRepository extends _FakeTabsRepository {
  bool armed = false;

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {
    if (armed) throw Exception('save failed');
    return super.saveTabs(tabs, currentTabIndex);
  }
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
