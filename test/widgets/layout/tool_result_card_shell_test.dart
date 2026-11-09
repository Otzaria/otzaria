import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/tool_result_card_shell.dart';

void main() {
  Future<(BuildContext, List<BuildContext>)> pumpCards(
    WidgetTester tester, {
    required bool enabled,
  }) async {
    late BuildContext outer;
    final inner = <BuildContext>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: enabled,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                outer = context;
                return ListView(
                  children: [
                    for (var i = 0; i < 2; i++)
                      ToolResultCardShell(
                        child: Builder(
                          builder: (context) {
                            inner.add(context);
                            return Text('כרטיס $i');
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    return (outer, inner);
  }

  testWidgets('הטיקרים של כל כרטיס נרשמים ל-notifier משלו', (tester) async {
    final (outer, inner) = await pumpCards(tester, enabled: true);
    final ValueListenable<TickerModeData> list = TickerMode.getValuesNotifier(
      outer,
    );
    final first = TickerMode.getValuesNotifier(inner[0]);
    final second = TickerMode.getValuesNotifier(inner[1]);

    // notifier משותף לכל הרשימה הופך את פירוק אלפי הכרטיסים לריבועי.
    expect(first, isNot(same(list)));
    expect(second, isNot(same(first)));
    expect(first.value.enabled, isTrue);
  });

  testWidgets('TickerMode כבוי מעל הרשימה כבוי גם בכרטיס', (tester) async {
    final (_, inner) = await pumpCards(tester, enabled: false);
    expect(TickerMode.getValuesNotifier(inner[0]).value.enabled, isFalse);
  });
}
