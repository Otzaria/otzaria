// סעיף 30 (q30): כותרת הסרגל בקורא גדלה עד פי 1.3 ועוצרת, גם בהגדלת טקסט
// של המערכת עד פי 2.
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
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/fake_commentary_library_provider.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/reader_screen_rig.dart';

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

  /// גובה פסקת הכותרת בסרגל הקורא בהגדלת טקסט [scale].
  Future<double> titleHeight(WidgetTester tester, double scale) async {
    DeviceChrome.debugMobileOverride = false;
    addTearDown(() => DeviceChrome.debugMobileOverride = null);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rig = ReaderRig.create(title: 'ספר בדיקה', currentTitle: 'סימן א');
    rigs.add(rig);
    await tester.pumpWidget(_app(rig, 600));
    await tester.pump();
    await tester.pump();
    final paragraph = find.descendant(
      of: find.byType(ReaderNavCenter),
      matching: find.textContaining('סימן א'),
    );
    return tester.getSize(paragraph.first).height;
  }

  testWidgets('כותרת הקורא: 1.5 ו-2.0 נעצרות בגובה של 1.3', (tester) async {
    final base = await titleHeight(tester, 1.0);
    final capped = await titleHeight(tester, 1.3);
    final big = await titleHeight(tester, 2.0);
    expect(capped, greaterThan(base));
    expect(big, closeTo(capped, 0.01));
  });
}
