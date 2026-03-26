import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TabsBloc side-by-side', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('יוצר CombinedTab עם עותקים נפרדים של הטאבים', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final rightTab = _createTextTab('ספר ימין');
      final leftTab = _createTextTab('ספר שמאל');

      bloc.add(AddTab(rightTab));
      bloc.add(AddTab(leftTab));
      await Future<void>.delayed(Duration.zero);

      bloc.add(EnableSideBySideMode(rightTab: rightTab, leftTab: leftTab));
      await Future<void>.delayed(Duration.zero);

      final currentState = bloc.state;
      expect(currentState.tabs, hasLength(1));
      expect(currentState.currentTab, isA<CombinedTab>());

      final combinedTab = currentState.currentTab! as CombinedTab;
      expect(combinedTab.rightTab, isNot(same(rightTab)));
      expect(combinedTab.leftTab, isNot(same(leftTab)));

      final combinedRightTab = combinedTab.rightTab as TextBookTab;
      final combinedLeftTab = combinedTab.leftTab as TextBookTab;

      expect(combinedRightTab.scrollController,
          isNot(same(rightTab.scrollController)));
      expect(combinedLeftTab.scrollController,
          isNot(same(leftTab.scrollController)));

      await bloc.close();
      rightTab.dispose();
      leftTab.dispose();
    });

    test('פירוק CombinedTab מחזיר טאבים חדשים ולא את מופעי המשנה הישנים',
        () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final rightTab = _createTextTab('ספר א');
      final leftTab = _createTextTab('ספר ב');

      bloc.add(AddTab(rightTab));
      bloc.add(AddTab(leftTab));
      await Future<void>.delayed(Duration.zero);

      bloc.add(EnableSideBySideMode(rightTab: rightTab, leftTab: leftTab));
      await Future<void>.delayed(Duration.zero);

      final combinedTab = bloc.state.currentTab! as CombinedTab;
      final combinedRightTab = combinedTab.rightTab;
      final combinedLeftTab = combinedTab.leftTab;

      bloc.add(const DisableSideBySideMode());
      await Future<void>.delayed(Duration.zero);

      final restoredState = bloc.state;
      expect(restoredState.tabs, hasLength(2));
      expect(restoredState.tabs[0], isNot(same(combinedRightTab)));
      expect(restoredState.tabs[1], isNot(same(combinedLeftTab)));

      await bloc.close();
      rightTab.dispose();
      leftTab.dispose();
    });
  });

  group('TabsBloc open or focus', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('ממקד טאב טקסט קיים כשאותו ספר פתוח באותה כותרת', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final firstTab = _createTextTab('ספר א', index: 0)
        ..currentTitle.value = 'פרק א';
      final secondTab = _createTextTab('ספר ב', index: 0);

      bloc.add(AddTab(firstTab));
      bloc.add(AddTab(secondTab));
      await Future<void>.delayed(Duration.zero);

      final targetTab = _createTextTab('ספר א', index: 12);
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר א, פרק א'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTabIndex, 0);

      await bloc.close();
      firstTab.dispose();
      secondTab.dispose();
    });

    test('פותח טאב חדש כשאותו ספר נפתח בכותרת אחרת', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = _createTextTab('ספר א', index: 0)
        ..currentTitle.value = 'פרק א';

      bloc.add(AddTab(existingTab));
      await Future<void>.delayed(Duration.zero);

      final targetTab = _createTextTab('ספר א', index: 25);
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'פרק ב'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTabIndex, 1);

      await bloc.close();
      existingTab.dispose();
    });

    test('ממקד טאב PDF קיים לפי כותרת גם אם העמוד שונה', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 10,
      )..currentTitle.value = 'שער ראשון';

      bloc.add(AddTab(existingTab));
      await Future<void>.delayed(Duration.zero);

      final targetTab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 14,
      );
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר PDF, שער ראשון'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);

      await bloc.close();
      existingTab.dispose();
    });

    test('ממקד CombinedTab כשאחת החלוניות תואמת', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final combinedTab = CombinedTab(
        rightTab: _createTextTab('ספר ימין', index: 0)
          ..currentTitle.value = 'פרק א',
        leftTab: _createTextTab('ספר שמאל', index: 0)
          ..currentTitle.value = 'פרק ג',
      );

      bloc.add(AddTab(combinedTab));
      await Future<void>.delayed(Duration.zero);

      final targetTab = _createTextTab('ספר שמאל', index: 99);
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר שמאל, פרק ג'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);
      expect(bloc.state.currentTab, same(combinedTab));

      await bloc.close();
      combinedTab.dispose();
    });
  });
}

TextBookTab _createTextTab(String title, {int index = 0}) {
  return TextBookTab(
    book: TextBook(title: title),
    index: index,
  );
}

class _FakeTabsRepository extends TabsRepository {
  List<Map<String, dynamic>> _tabsJson = const [];
  int _currentTabIndex = 0;
  SideBySideMode? _sideBySideMode;

  @override
  List<OpenedTab> loadTabs() =>
      _tabsJson.map((tab) => TextBookTab.fromJson(tab)).toList();

  @override
  int loadCurrentTabIndex() => _currentTabIndex;

  @override
  SideBySideMode? loadSideBySideMode() => _sideBySideMode;

  @override
  void saveTabs(
    List<OpenedTab> tabs,
    int currentTabIndex, [
    SideBySideMode? sideBySideMode,
  ]) {
    _tabsJson = tabs
        .map<Map<String, dynamic>>((tab) => tab.toJson())
        .toList(growable: false);
    _currentTabIndex = currentTabIndex;
    _sideBySideMode = sideBySideMode;
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
