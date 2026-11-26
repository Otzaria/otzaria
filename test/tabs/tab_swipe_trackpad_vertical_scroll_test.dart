import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/view/tab_swipe_detector.dart';
import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  testWidgets('גלילה אנכית בלוח מגע אינה מאבדת את תחילת המחווה (#3975)', (
    tester,
  ) async {
    final bloc = TabsBloc(repository: _FakeTabsRepository());
    addTearDown(bloc.close);
    bloc.emit(
      TabsState(
        tabs: [
          for (var i = 0; i < 2; i++)
            PdfBookTab(
              book: PdfBook(title: '$i', path: '/tmp/$i.pdf'),
              pageNumber: 1,
            ),
        ],
        currentTabIndex: 0,
      ),
    );
    final pages = PageController();
    addTearDown(pages.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: TabSwipeDetector(
            controller: pages,
            onActiveChanged: (_) {},
            child: PageView(
              controller: pages,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ListView(
                  controller: scroll,
                  children: [
                    for (var i = 0; i < 100; i++) const SizedBox(height: 50),
                  ],
                ),
                const SizedBox.expand(),
              ],
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(ListView));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center, timeStamp: Duration.zero);
    final offsets = <double>[];
    for (var i = 1; i <= 8; i++) {
      await gesture.panZoomUpdate(
        center,
        pan: Offset(0, -4.0 * i),
        timeStamp: Duration(milliseconds: i * 10),
      );
      await tester.pump(const Duration(milliseconds: 10));
      offsets.add(scroll.offset);
    }
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 90));
    await tester.pumpAndSettle();

    // הכיוון מוכרע בעדכון הראשון, ומשם הגלילה צמודה לאצבעות.
    expect(offsets, [for (var i = 0; i < 8; i++) 4.0 * i]);
    expect(bloc.state.currentTabIndex, 0);
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
