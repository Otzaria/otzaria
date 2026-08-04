import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/widgets/nav_panel_tour_target.dart';

/// ילד עם State שסופר יצירות — כך אפשר להוכיח שהחלונית לא נבנתה מאפס.
class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static int initCount = 0;
  static int disposeCount = 0;
  int taps = 0;

  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => taps++),
      child: Text('taps: $taps'),
    );
  }
}

/// עוטף את [TextBookNavPanelTourTarget] בבורר שמדמה מעבר בין טאב פעיל לרקע.
class _Host extends StatefulWidget {
  const _Host({required this.initialIsActive});

  final bool initialIsActive;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool isActive = widget.initialIsActive;

  void setActive(bool value) => setState(() => isActive = value);

  @override
  Widget build(BuildContext context) {
    return TextBookNavPanelTourTarget(
      isActiveTab: isActive,
      child: const _Probe(),
    );
  }
}

void main() {
  setUp(() {
    _ProbeState.initCount = 0;
    _ProbeState.disposeCount = 0;
    activeTextBookNavPanelTourTargetKey = null;
  });

  Future<_HostState> pumpHost(
    WidgetTester tester, {
    bool isActive = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(home: _Host(initialIsActive: isActive)),
    );
    return tester.state<_HostState>(find.byType(_Host));
  }

  testWidgets('מעבר בין טאב פעיל לרקע וחזרה לא בונה את החלונית מחדש', (
    tester,
  ) async {
    final host = await pumpHost(tester);
    expect(_ProbeState.initCount, 1);

    host.setActive(false);
    await tester.pump();
    host.setActive(true);
    await tester.pump();

    expect(
      _ProbeState.initCount,
      1,
      reason: 'החלונית נבנתה מאפס — מצב החיפוש והניווט אובד',
    );
    expect(_ProbeState.disposeCount, 0);
  });

  testWidgets('מצב פנימי של החלונית נשמר במעבר לרקע וחזרה', (tester) async {
    final host = await pumpHost(tester);

    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('taps: 1'), findsOneWidget);

    host.setActive(false);
    await tester.pump();
    host.setActive(true);
    await tester.pump();

    expect(find.text('taps: 1'), findsOneWidget);
  });

  testWidgets('הטאב הפעיל מפרסם את מפתח החלונית שלו', (tester) async {
    await pumpHost(tester);

    final key = activeTextBookNavPanelTourTargetKey;
    expect(key, isNotNull);
    expect(key!.currentContext, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(_Probe),
      ),
      findsOneWidget,
    );
  });

  testWidgets('טאב רקע אינו מפרסם מפתח', (tester) async {
    await pumpHost(tester, isActive: false);

    expect(activeTextBookNavPanelTourTargetKey, isNull);
  });

  testWidgets('הפעלת טאב שהיה ברקע מפרסמת את המפתח שלו', (tester) async {
    final host = await pumpHost(tester, isActive: false);
    expect(activeTextBookNavPanelTourTargetKey, isNull);

    host.setActive(true);
    await tester.pump();

    expect(activeTextBookNavPanelTourTargetKey, isNotNull);
  });

  testWidgets('טאב שיורד לרקע לבדו מנקה את הפרסום', (tester) async {
    final host = await pumpHost(tester);
    expect(activeTextBookNavPanelTourTargetKey, isNotNull);

    host.setActive(false);
    await tester.pump();

    expect(
      activeTextBookNavPanelTourTargetKey,
      isNull,
      reason: 'הסיור לא אמור להדגיש חלונית של טאב שאינו על המסך',
    );
  });

  /// שני טאבים חיים במקביל ומתעדכנים באותו frame; הבדיקה מריצה את שני כיווני
  /// המעבר, כי סדר העדכון בין הטאבים אינו מובטח.
  Future<void> expectPublishFollowsActiveTab(
    WidgetTester tester, {
    required int from,
    required int to,
  }) async {
    late StateSetter setOuterState;
    var activeIndex = from;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setOuterState = setState;
            return Column(
              children: [
                for (var i = 0; i < 2; i++)
                  TextBookNavPanelTourTarget(
                    key: ValueKey(i),
                    isActiveTab: i == activeIndex,
                    child: SizedBox(key: ValueKey('child-$i')),
                  ),
              ],
            );
          },
        ),
      ),
    );

    final firstKey = activeTextBookNavPanelTourTargetKey;
    expect(firstKey, isNotNull);

    setOuterState(() => activeIndex = to);
    await tester.pump();

    final secondKey = activeTextBookNavPanelTourTargetKey;
    expect(secondKey, isNotNull, reason: 'הפרסום של הטאב הנכנס נמחק');
    expect(secondKey, isNot(firstKey));
    expect(
      find.descendant(
        of: find.byKey(secondKey!),
        matching: find.byKey(ValueKey('child-$to')),
      ),
      findsOneWidget,
      reason: 'הפרסום צריך להצביע על החלונית של הטאב הפעיל',
    );
  }

  testWidgets('מעבר קדימה בין טאבים מעביר את הפרסום לטאב הנכנס', (
    tester,
  ) async {
    await expectPublishFollowsActiveTab(tester, from: 0, to: 1);
  });

  testWidgets('מעבר אחורה בין טאבים מעביר את הפרסום לטאב הנכנס', (
    tester,
  ) async {
    await expectPublishFollowsActiveTab(tester, from: 1, to: 0);
  });

  testWidgets('סגירת הטאב הפעיל מנקה את הפרסום', (tester) async {
    await pumpHost(tester);
    expect(activeTextBookNavPanelTourTargetKey, isNotNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    expect(activeTextBookNavPanelTourTargetKey, isNull);
  });

  testWidgets('סגירת טאב רקע לא מוחקת את הפרסום של הטאב הפעיל', (
    tester,
  ) async {
    late StateSetter setOuterState;
    var showBackgroundTab = true;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setOuterState = setState;
            return Column(
              children: [
                const TextBookNavPanelTourTarget(
                  key: ValueKey('active'),
                  isActiveTab: true,
                  child: SizedBox(),
                ),
                if (showBackgroundTab)
                  const TextBookNavPanelTourTarget(
                    key: ValueKey('background'),
                    isActiveTab: false,
                    child: SizedBox(),
                  ),
              ],
            );
          },
        ),
      ),
    );

    final activeKey = activeTextBookNavPanelTourTargetKey;
    expect(activeKey, isNotNull);

    setOuterState(() => showBackgroundTab = false);
    await tester.pump();

    expect(activeTextBookNavPanelTourTargetKey, activeKey);
  });
}
