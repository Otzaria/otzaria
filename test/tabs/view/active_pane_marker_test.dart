import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/active_pane_marker.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// bloc שמתעד את האירועים שנשלחו אליו.
class _RecordingTabsBloc extends Bloc<TabsEvent, TabsState>
    implements TabsBloc {
  _RecordingTabsBloc(super.initial) {
    on<TabsEvent>((event, _) {});
  }

  final List<TabsEvent> events = [];

  @override
  void add(TabsEvent event) {
    events.add(event);
    super.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  /// טאב מפוצל ושתי החלוניות שבו, כדי שהמסמן יסמן חלונית אמיתית.
  ({_RecordingTabsBloc bloc, OpenedTab first, OpenedTab second}) newBloc() {
    final first = _LeafTab('א');
    final second = _LeafTab('ב');
    final split = CombinedTab(rightTab: first, leftTab: second);
    final bloc = _RecordingTabsBloc(
      TabsState(tabs: [split], currentTabIndex: 0),
    );
    addTearDown(bloc.close);
    return (bloc: bloc, first: first, second: second);
  }

  Widget host(
    _RecordingTabsBloc bloc, {
    required bool enabled,
    required OpenedTab pane,
    VoidCallback? onButtonPressed,
  }) {
    return MaterialApp(
      home: BlocProvider<TabsBloc>.value(
        value: bloc,
        child: Scaffold(
          body: ActivePaneMarker(
            pane: pane,
            enabled: enabled,
            child: Center(
              child: ElevatedButton(
                onPressed: onButtonPressed ?? () {},
                child: const Text('כפתור בתוך החלונית'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<OpenedTab> markedPanes(_RecordingTabsBloc bloc) =>
      bloc.events.whereType<SetActivePane>().map((e) => e.pane).toList();

  testWidgets('לחיצה בחלונית מסמנת אותה כפעילה', (tester) async {
    final t = newBloc();
    await tester.pumpWidget(host(t.bloc, enabled: true, pane: t.second));

    await tester.tapAt(const Offset(100, 100));
    await tester.pump();

    expect(markedPanes(t.bloc), [same(t.second)]);
  });

  testWidgets('הלחיצה ממשיכה לתוכן ואינה נבלעת', (tester) async {
    final t = newBloc();
    var pressed = 0;
    await tester.pumpWidget(
      host(
        t.bloc,
        enabled: true,
        pane: t.first,
        onButtonPressed: () => pressed++,
      ),
    );

    await tester.tap(find.text('כפתור בתוך החלונית'));
    await tester.pump();

    // גם הכפתור פעל וגם החלונית סומנה — הסימון הוא תופעת לוואי.
    expect(pressed, 1);
    expect(markedPanes(t.bloc), [same(t.first)]);
  });

  testWidgets('בטאב שאינו מפוצל אין סימון כלל', (tester) async {
    final t = newBloc();
    await tester.pumpWidget(host(t.bloc, enabled: false, pane: t.first));

    await tester.tapAt(const Offset(100, 100));
    await tester.pump();

    expect(markedPanes(t.bloc), isEmpty);
  });

  testWidgets('כל לחיצה מדווחת; ה-bloc מסנן חזרות', (tester) async {
    final t = newBloc();
    await tester.pumpWidget(host(t.bloc, enabled: true, pane: t.second));

    await tester.tapAt(const Offset(100, 100));
    await tester.tapAt(const Offset(120, 120));
    await tester.pump();

    expect(markedPanes(t.bloc), hasLength(2));
  });

  testWidgets('ריחוף וגלילה אינם מסמנים — רק לחיצה', (tester) async {
    final t = newBloc();
    await tester.pumpWidget(host(t.bloc, enabled: true, pane: t.second));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(const Offset(140, 140));
    await tester.pump();
    await tester.sendEventToBinding(
      testPointer(const Offset(140, 140)).scroll(const Offset(0, 60)),
    );
    await tester.pump();

    expect(
      markedPanes(t.bloc),
      isEmpty,
      reason: 'סימון בגלילה היה מזיז את החלונית הפעילה בלי כוונת המשתמש',
    );
  });
}

/// מצביע עכבר לצורך אירוע גלגלת.
TestPointer testPointer(Offset location) {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  pointer.hover(location);
  return pointer;
}
