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
import 'package:otzaria/tabs/utils/tab_swipe_log.dart';
import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));
  for (final rtl in [false, true]) {
    for (final layout in [
      (offset: Offset.zero, scale: 1.0),
      (offset: const Offset(80, 120), scale: 1.0),
      (offset: const Offset(80, 120), scale: 0.5),
    ]) {
      testWidgets(
        '${rtl ? 'RTL' : 'LTR'}: התנועה אינה תלויה במיקום הגלאי $layout',
        (tester) async {
          final tabs = [
            for (var i = 0; i < 3; i++)
              PdfBookTab(
                book: PdfBook(title: '$i', path: '/tmp/$i.pdf'),
                pageNumber: 1,
              ),
          ];
          final bloc = TabsBloc(repository: _FakeTabsRepository());
          addTearDown(bloc.close);
          bloc.emit(TabsState(tabs: tabs, currentTabIndex: 1));
          final controller = PageController(initialPage: 1);
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: BlocProvider.value(
                value: bloc,
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: layout.offset.dx,
                      top: layout.offset.dy,
                    ),
                    child: Transform.scale(
                      scale: layout.scale,
                      alignment: Alignment.topCenter,
                      child: TabSwipeDetector(
                        controller: controller,
                        onActiveChanged: (_) {},
                        child: PageView(
                          controller: controller,
                          physics: const NeverScrollableScrollPhysics(),
                          children: const [
                            SizedBox.expand(),
                            SizedBox.expand(),
                            SizedBox.expand(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final center = tester.getCenter(find.byType(PageView));
          Future<void> pan(List<Offset> offsets) async {
            final gesture = await tester.createGesture(
              kind: PointerDeviceKind.trackpad,
            );
            await gesture.panZoomStart(center, timeStamp: Duration.zero);
            for (var i = 0; i < offsets.length; i++) {
              await gesture.panZoomUpdate(
                center,
                pan: offsets[i],
                timeStamp: Duration(milliseconds: (i + 1) * 10),
              );
              await tester.pump(const Duration(milliseconds: 10));
            }
            await gesture.panZoomEnd(
              timeStamp: Duration(milliseconds: (offsets.length + 1) * 10),
            );
            await tester.pumpAndSettle();
          }

          final forward = rtl ? 1.0 : -1.0;
          for (final sign in [forward, -forward]) {
            await pan([
              for (var i = 1; i <= 5; i++) Offset(sign * 12 * i, 0),
            ]);
            final expected = sign == forward ? 2 : 1;
            expect(bloc.state.currentTabIndex, expected);
            expect(controller.page, expected);
            expect(TabSwipeLog.of(bloc).last['dy'], 0);
          }
          for (final sign in [forward, -forward]) {
            await pan([
              Offset(sign * 30, -2),
              Offset(sign * 50, -80),
              Offset(sign * 65, -180),
              Offset(sign * 80, -300),
            ]);
            expect(bloc.state.currentTabIndex, 1);
            expect(controller.page, 1);
            expect(TabSwipeLog.of(bloc).last['dy'], 300 / layout.scale);
          }
        },
      );
    }
  }

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
