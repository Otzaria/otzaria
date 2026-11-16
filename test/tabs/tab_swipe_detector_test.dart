import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/view/tab_swipe_detector.dart';
import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));
  testWidgets('הסרת הגלאי באמצע גרירה משחררת את דיכוי הסנכרון', (
    tester,
  ) async {
    final bloc = TabsBloc(repository: _FakeTabsRepository());
    addTearDown(bloc.close);
    final controller = PageController();
    addTearDown(controller.dispose);
    final active = <bool>[];

    await tester.pumpWidget(
      BlocProvider<TabsBloc>.value(
        value: bloc,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TabSwipeDetector(
            controller: controller,
            onActiveChanged: active.add,
            child: PageView(
              controller: controller,
              physics: const NeverScrollableScrollPhysics(),
              children: const [SizedBox.expand(), SizedBox.expand()],
            ),
          ),
        ),
      ),
    );

    const center = Offset(400, 300);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center, timeStamp: Duration.zero);
    for (var i = 1; i <= 3; i++) {
      await gesture.panZoomUpdate(
        center,
        pan: Offset(-30.0 * i, 0),
        timeStamp: Duration(milliseconds: 10 * i),
      );
      await tester.pump();
    }
    expect(active, [true]);

    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 50));

    expect(active, [true, false]);
  });

  testWidgets('הסרת הגלאי בזמן התיישבות משחררת פעם אחת בלי callback מאוחר', (
    tester,
  ) async {
    final tabs = [
      for (var i = 0; i < 2; i++)
        PdfBookTab(
          book: PdfBook(title: '$i', path: '/tmp/$i.pdf'),
          pageNumber: 1,
        ),
    ];
    final bloc = TabsBloc(repository: _FakeTabsRepository());
    addTearDown(bloc.close);
    bloc.emit(TabsState(tabs: tabs, currentTabIndex: 0));
    final controller = PageController();
    addTearDown(controller.dispose);
    final active = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: TabSwipeDetector(
            controller: controller,
            onActiveChanged: active.add,
            child: PageView(
              controller: controller,
              physics: const NeverScrollableScrollPhysics(),
              children: const [SizedBox.expand(), SizedBox.expand()],
            ),
          ),
        ),
      ),
    );
    const center = Offset(400, 300);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center, timeStamp: Duration.zero);
    for (var i = 1; i <= 5; i++) {
      await gesture.panZoomUpdate(
        center,
        pan: Offset(-30.0 * i, 0),
        timeStamp: Duration(milliseconds: i * 10),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 16));
    expect(active, [true]);
    expect(bloc.state.currentTabIndex, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
    expect(active, [true, false]);
    expect(tester.takeException(), isNull);
  });
}

class _FakeTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}
