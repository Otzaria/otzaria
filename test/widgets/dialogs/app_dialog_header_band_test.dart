import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

void main() {
  testWidgets('דיאלוג עם פס כותרת משאיר רווח בין התוכן לכפתורים', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTwoActionsDialog(
              context: context,
              title: 'כותרת',
              customContent: const SizedBox(key: Key('body'), height: 40),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final bodyBottom = tester.getBottomLeft(find.byKey(const Key('body'))).dy;
    final buttonsTop = tester.getTopLeft(find.byType(FilledButton).first).dy;

    expect(buttonsTop - bodyBottom, greaterThanOrEqualTo(AppTokens.spaceMD));
  });
}
