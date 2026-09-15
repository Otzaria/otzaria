import 'dart:async';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart' show OpenedTab;
import 'package:otzaria/tabs/tabs_repository.dart';

import '../helpers/memory_settings_cache.dart';

/// הבאג: currentScreen מתעדכן רק ב-NavigateToScreen מפורש. לחיצה על תוצאת
/// חיפוש שולחת OpenOrFocusTab בלבד ל-TabsBloc, ולכן המסך נשאר Screen.search
/// גם כשהמשתמש כבר קורא ספר — ואייקון "חיפוש" בסרגל נשאר מודגש במקום "עיון".
/// אותו דבר בהחלפת לשונית עליונה בין טאב חיפוש לטאב ספר.
///
/// החוזה הנבדק: NavigationBloc מאזין לזרם החלונית הפעילה ומיישר את המסך —
/// טאב חיפוש פעיל ⇢ Screen.search, כל טאב אחר ⇢ Screen.reading — ורק כאשר
/// המשתמש נמצא ממילא בעמוד הטאבים (עיון/חיפוש). מסכים אחרים אינם נחטפים.

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _DummyTab extends OpenedTab {
  _DummyTab() : super('ספר');

  /// stub חסר state — אין מה לשכפל.
  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'title': title};
}

class _FakeNavigationRepository implements NavigationRepository {
  @override
  bool checkLibraryIsEmpty() => false;

  @override
  Future<void> refreshLibrary() async {}
}

class _FakeTabsRepository implements TabsRepository {
  @override
  List<OpenedTab> loadTabs() => [];

  @override
  Future<void> flushPendingWrites() async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ─── Tests ───────────────────────────────────────────────────────────────────

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // SearchingTab בונה SearchBloc שקורא העדפות תצוגה מ-Settings.
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('סנכרון המסך עם החלונית הפעילה', () {
    late StreamController<OpenedTab?> panes;
    late NavigationBloc bloc;

    setUp(() {
      panes = StreamController<OpenedTab?>();
      bloc = NavigationBloc(
        repository: _FakeNavigationRepository(),
        tabsRepository: _FakeTabsRepository(),
        activePaneStream: panes.stream,
      );
    });

    tearDown(() async {
      await bloc.close();
      await panes.close();
    });

    // אירוע זרם עובר שני שלבים אסינכרוניים (מסירת ה-stream ואז עיבוד
    // ה-event ב-bloc), לכן שתי המתנות.
    Future<void> pump() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    SearchingTab searchTab() {
      final tab = SearchingTab('חיפוש', null);
      addTearDown(tab.dispose);
      return tab;
    }

    test('פתיחת ספר מטאב חיפוש מעבירה את המסך לעיון', () async {
      bloc.add(const NavigateToScreen(Screen.search));
      await pump();

      panes.add(_DummyTab());
      await pump();

      expect(bloc.state.currentScreen, Screen.reading);
    });

    test('מעבר ללשונית חיפוש מעביר את המסך לחיפוש', () async {
      bloc.add(const NavigateToScreen(Screen.reading));
      await pump();

      panes.add(searchTab());
      await pump();

      expect(bloc.state.currentScreen, Screen.search);
    });

    test('שינוי טאב ברקע אינו חוטף את מסך הספרייה', () async {
      bloc.add(const NavigateToScreen(Screen.library));
      await pump();

      panes.add(_DummyTab());
      panes.add(searchTab());
      await pump();

      expect(bloc.state.currentScreen, Screen.library);
    });

    test('שינוי טאב ברקע אינו חוטף את מסך ההגדרות', () async {
      bloc.add(const NavigateToScreen(Screen.settings));
      await pump();

      panes.add(searchTab());
      await pump();

      expect(bloc.state.currentScreen, Screen.settings);
    });

    test('בלי חלונית פעילה (נסגרו כל הטאבים) המסך אינו משתנה', () async {
      bloc.add(const NavigateToScreen(Screen.search));
      await pump();

      panes.add(null);
      await pump();

      expect(bloc.state.currentScreen, Screen.search);
    });

    test('טאב ספר כשהמסך כבר בעיון אינו פולט state מיותר', () async {
      bloc.add(const NavigateToScreen(Screen.reading));
      await pump();

      var emissions = 0;
      final subscription = bloc.stream.listen((_) => emissions++);
      addTearDown(subscription.cancel);

      panes.add(_DummyTab());
      await pump();

      expect(emissions, 0);
      expect(bloc.state.currentScreen, Screen.reading);
    });

    test('סגירת ה-bloc מבטלת את המנוי — אירוע מאוחר אינו קורס', () async {
      await bloc.close();

      panes.add(_DummyTab());
      await pump();
      // אין assert — הטסט נכשל אם add-אחרי-close זורק StateError.
    });
  });
}
