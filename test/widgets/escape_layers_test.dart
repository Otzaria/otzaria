import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/escape_layers.dart';

void main() {
  testWidgets('ESC מגיע רק לשכבה העליונה שמטפלת בו (issue #2528)', (
    tester,
  ) async {
    final calls = <String>[];
    KeyEventResult lower(KeyEvent e) {
      calls.add('lower');
      return KeyEventResult.handled;
    }

    KeyEventResult upper(KeyEvent e) {
      if (e is! KeyDownEvent) return KeyEventResult.ignored;
      calls.add('upper');
      return KeyEventResult.handled;
    }

    await tester.pumpWidget(
      const MaterialApp(home: Focus(autofocus: true, child: SizedBox())),
    );
    EscapeLayers.add(lower);
    EscapeLayers.add(upper);
    addTearDown(() {
      EscapeLayers.remove(upper);
      EscapeLayers.remove(lower);
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    expect(calls, ['upper']);

    // שכבה שמתעלמת מהאירוע מעבירה אותו לשכבה שמתחתיה.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    expect(calls, ['upper', 'lower']);

    EscapeLayers.remove(upper);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(calls, ['upper', 'lower', 'lower', 'lower']);
  });
}
