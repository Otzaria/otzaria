// סעיף 17 (סבב ג'): בסרגל הקורא בחלונית צרה יש כפתור "עוד ⋮" אחד, שבו פעולות
// ההתחלה שקופלו (חזרה, נעיצה, צורת דף) לצד פעולות הקורא, ושורת "חזרה" בו
// פעילה רק כשיש היסטוריה.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/find_ref_recent_store.dart';
import 'package:otzaria/find_ref/view/find_ref_dialog.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/view/pane_drag_handle.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/fake_commentary_library_provider.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/reader_screen_rig.dart';

const _moreTooltip = 'עוד פעולות';
const _backLabel = 'חזרה למיקום הקודם';

/// החלונית ברוחב [paneWidth] בתוך חלון רחב: התפריט נפתח מחוץ לחלונית, כמו
/// בפיצול אמיתי.
Widget _app(ReaderRig rig, double paneWidth) {
  final cs = AppThemeData.createColorScheme(
    AppSeedColors.defaultLight,
    Brightness.light,
  );
  return rig.wrap(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppThemeData.light(cs, compactMenuMode: false),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: paneWidth,
            child: Builder(
              builder: (context) {
                final tab = context.read<TabsBloc>().state.tabs.single;
                return PaneDragHandleScope(
                  pane: tab,
                  enabled: true,
                  child: TextBookViewerBloc(
                    tab: tab as TextBookTab,
                    isInCombinedView: false,
                    openBookCallback: (_) {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

Finder get _barMore => find.descendant(
  of: find.byType(AppTopBar),
  matching: find.byTooltip(_moreTooltip),
);

Future<void> main() async {
  await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();

  final rigs = <ReaderRig>[];
  tearDown(() async {
    for (final r in rigs) {
      await r.dispose();
    }
    rigs.clear();
    LibraryProviderManager.instance.resetForTesting();
  });

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    await text_utils.splitByEra(const []);
    FindRefRecentStore.clear();
    FindRefDialog.resetExamplesRotationForTesting();
    LibraryProviderManager.instance.resetForTesting();
    final p = FakeCommentaryLibraryProvider();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): p,
      },
      providers: [p],
    );
  });

  Future<ReaderRig> pumpReader(WidgetTester tester, {required double width}) {
    DeviceChrome.debugMobileOverride = false;
    addTearDown(() => DeviceChrome.debugMobileOverride = null);
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rig = ReaderRig.create(
      showLeftPane: true,
      pinLeftPane: true,
      pageShape: true,
    );
    rigs.add(rig);
    return tester.pumpWidget(_app(rig, width)).then((_) async {
      await tester.pump();
      await tester.pump();
      return rig;
    });
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(_barMore.hitTestable().first);
    await tester.pumpAndSettle();
  }

  bool rowEnabled(WidgetTester tester, String label) {
    final row = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
    );
    return (tester.widget(row.first) as PopupMenuItem).enabled;
  }

  group('סרגל הקורא: תפריט "עוד ⋮" אחד', () {
    testWidgets('חלונית צרה: כפתור ⋮ אחד, ובו פעולות ההתחלה ופעולות הקורא', (
      tester,
    ) async {
      await pumpReader(tester, width: 210);
      expect(tester.takeException(), isNull);
      expect(
        tester.widgetList(_barMore.hitTestable()).length,
        1,
        reason: 'לא שני כפתורי ⋮ זה לצד זה',
      );

      await openMenu(tester);
      expect(find.text('בטל נעיצה'), findsOneWidget);
      expect(find.text('הגדרות צורת הדף'), findsOneWidget);
      expect(find.text(_backLabel), findsOneWidget);
      expect(find.text('הדפסה'), findsOneWidget);
    });

    testWidgets('חלון רחב: אין שורות התחלה בתפריט הקורא', (tester) async {
      await pumpReader(tester, width: 600);
      await openMenu(tester);
      expect(find.text('בטל נעיצה'), findsNothing);
      expect(find.text(_backLabel), findsNothing);
      expect(find.text('הדפסה'), findsOneWidget);
    });

    testWidgets('שורת "חזרה" מושבתת בלי היסטוריה ופעילה אחריה', (tester) async {
      await pumpReader(tester, width: 210);
      await openMenu(tester);
      expect(rowEnabled(tester, _backLabel), isFalse);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();

      final tab =
          tester
                  .element(find.byType(TextBookViewerBloc))
                  .read<TabsBloc>()
                  .state
                  .tabs
                  .single
              as TextBookTab;
      tab.lines.restoreHistory({
        'back': [const ReadingAnchor(line: 2).toJson()],
        'forward': <Object>[],
      });
      await tester.pump();
      await tester.pump();

      await openMenu(tester);
      expect(rowEnabled(tester, _backLabel), isTrue);
    });
  });
}
