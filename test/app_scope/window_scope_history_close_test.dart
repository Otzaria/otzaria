import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/app_scope_providers.dart';
import 'package:otzaria/app_scope/window_scope_providers.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../helpers/memory_settings_cache.dart';
import '../support/search_engine_test_init.dart';

class _MemoryHistoryRepository extends HistoryRepository {
  List<Bookmark> stored = [];

  @override
  Future<List<Bookmark>> load() async => stored;

  @override
  Future<List<Bookmark>> mutate(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async {
    stored = List<Bookmark>.from(apply(List<Bookmark>.from(stored)));
    return List<Bookmark>.from(stored);
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  // פירוק העץ בלי שטיפה קודמת, כמו באתחול מחדש: ה-context של הספקים כבר מפורק.
  testWidgets(
    'פירוק עץ החלון רושם בהיסטוריה את הכרטיסיה הפעילה',
    (tester) async {
      final repository = _MemoryHistoryRepository();
      final tab = SearchingTab('הכרטיסיה הפעילה', 'הכרטיסיה הפעילה');
      addTearDown(tab.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        AppScopeProviders(
          settingsRepository: SettingsRepository(),
          child: WindowScopeProviders(
            historyRepository: repository,
            initialTab: tab,
            // בלי משבצת: הכרטיסיות אינן נשמרות לדיסק.
            tabsSession: WindowTabsSession(slot: () => null),
            child: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      final history = context.read<HistoryBloc>();
      await tester.pump();
      expect(history.state, isA<HistoryLoaded>());
      expect(repository.stored, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();

      expect(history.isClosed, isTrue);
      expect(repository.stored.map((b) => b.book.title), ['הכרטיסיה הפעילה']);
    },
    skip: !engineReady,
  );
}
