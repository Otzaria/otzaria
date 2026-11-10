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

  // q10-f: בחציית 600 ה-leading וה-trailing עוברים מקום בכותרת, והמצב שלהם
  // (למשל טקסט שהוקלד בשדה) נשמר.
  testWidgets('leading ו-trailing שומרים מצב בחציית רוחב הטלפון', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 600);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: AppDialogHeader(
            title: 'כותרת',
            leading: const SizedBox(
              width: 120,
              child: TextField(key: Key('lead')),
            ),
            trailing: const SizedBox(
              width: 120,
              child: TextField(key: Key('trail')),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('lead')), 'א');
    await tester.enterText(find.byKey(const Key('trail')), 'ב');
    final leadState = tester.state(find.byKey(const Key('lead')));
    final trailState = tester.state(find.byKey(const Key('trail')));

    tester.view.physicalSize = const Size(400, 600);
    await tester.pump();

    expect(tester.state(find.byKey(const Key('lead'))), same(leadState));
    expect(tester.state(find.byKey(const Key('trail'))), same(trailState));
    expect(find.text('א'), findsOneWidget);
    expect(find.text('ב'), findsOneWidget);
  });
}
