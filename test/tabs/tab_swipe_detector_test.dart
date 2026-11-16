import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/view/tab_swipe_detector.dart';

void main() {
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
}

class _FakeTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}
