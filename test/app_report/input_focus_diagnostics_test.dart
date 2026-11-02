import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/input_focus_diagnostics.dart';

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.node});

  final FocusNode node;

  @override
  Widget build(BuildContext context) => TextField(focusNode: node);
}

class ReaderPane extends StatelessWidget {
  const ReaderPane({super.key, required this.node});

  final FocusNode node;

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: node, child: const SizedBox(width: 10, height: 10));
}

void main() {
  final diagnostics = InputFocusDiagnostics.instance;
  tearDown(diagnostics.resetForTesting);

  group('describeFocus', () {
    test('בלי פוקוס', () {
      expect(InputFocusDiagnostics.describeFocus(null), {'kind': 'none'});
    });

    testWidgets('שדה טקסט: הסוג והווידג\'טים הציבוריים שמעליו', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(child: _SearchBox(node: node)),
        ),
      );
      node.requestFocus();
      await tester.pump();

      final described = InputFocusDiagnostics.describeFocus(node);
      expect(described['kind'], 'text');
      expect(described['owners'], contains('TextField'));
      expect(described['owners'], isNot(contains('Focus')));
      expect(
        (described['owners']! as List).where((o) => '$o'.startsWith('_')),
        isEmpty,
      );
    });

    testWidgets('דיאלוג: סוג popup והמסלול', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  actions: [
                    TextButton(
                      autofocus: true,
                      onPressed: () {},
                      child: const Text('אישור'),
                    ),
                  ],
                ),
              ),
              child: const Text('פתח'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      final described = InputFocusDiagnostics.describeFocus(
        FocusManager.instance.primaryFocus,
      );
      expect(described['kind'], 'popup');
      expect(described['route'], startsWith('DialogRoute'));
      expect(described['screen'], 'AlertDialog');
    });

    testWidgets('screen הוא הווידג\'ט העליון במסך', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(MaterialApp(home: ReaderPane(node: node)));
      node.requestFocus();
      await tester.pump();

      expect(InputFocusDiagnostics.describeFocus(node)['screen'], 'ReaderPane');
    });
  });

  group('היסטוריה', () {
    testWidgets('המעברים שקדמו לטופס נשמרים, בלי כפילויות', (tester) async {
      final field = FocusNode();
      final reader = FocusNode();
      final sameReader = FocusNode();
      addTearDown(field.dispose);
      addTearDown(reader.dispose);
      addTearDown(sameReader.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Column(
              children: [
                _SearchBox(node: field),
                ReaderPane(node: reader),
                ReaderPane(node: sameReader),
              ],
            ),
          ),
        ),
      );
      diagnostics.install();

      field.requestFocus();
      await tester.pump();
      reader.requestFocus();
      await tester.pump();
      sameReader.requestFocus();
      await tester.pump();

      final recent = diagnostics.collect()['recentFocus'] as List;
      expect([for (final e in recent) e['kind']], ['text', 'other']);
      expect((recent.last as Map)['owners'], contains('ReaderPane'));
      expect((recent.first as Map)['msAgo'], isA<int>());
    });

    testWidgets('שומר רק את המעברים האחרונים', (tester) async {
      final nodes = List.generate(
        InputFocusDiagnostics.maxHistory + 5,
        (_) => FocusNode(),
      );
      for (final node in nodes) {
        addTearDown(node.dispose);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ListView(
              children: [
                for (var i = 0; i < nodes.length; i++)
                  i.isEven
                      ? ReaderPane(node: nodes[i])
                      : _SearchBox(node: nodes[i]),
              ],
            ),
          ),
        ),
      );
      diagnostics.install();
      for (final node in nodes) {
        node.requestFocus();
        await tester.pump();
      }

      expect(
        diagnostics.collect()['recentFocus'],
        hasLength(InputFocusDiagnostics.maxHistory),
      );
    });

    testWidgets('בלי התקנה אין היסטוריה, ושאר המקטע נאסף', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      final collected = diagnostics.collect();
      expect(collected.containsKey('recentFocus'), isFalse);
      expect(collected['primaryFocus'], isA<Map>());
    });
  });

  testWidgets('מקש שנשאר לחוץ נרשם בדוח', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft));

    expect(diagnostics.collect()['pressedKeys'], contains('Shift Left'));
  });
}
