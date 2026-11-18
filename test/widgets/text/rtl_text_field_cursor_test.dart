import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

void main() {
  testWidgets('focused cursor stays visible after blink timeout (#4459)', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RtlTextField(
            focusNode: focusNode,
            cursorColor: Colors.blue,
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
    expect(tester.widget<TextField>(find.byType(TextField)).cursorColor, Colors.blue);
  });
}
