import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';

void main() {
  testWidgets('Escape סוגר את תפריט הסינון לפי מאפיין (#2528)', (
    tester,
  ) async {
    final fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: fieldFocus, autofocus: true),
              SearchDimensionFilterButton(
                selectedFacets: const [],
                onToggle: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fieldFocus.hasFocus, isTrue);

    await tester.tap(find.byTooltip('סינון לפי מאפיין'));
    await tester.pumpAndSettle();
    expect(find.text('ספרי יסוד'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('ספרי יסוד'), findsNothing);
    expect(fieldFocus.hasFocus, isTrue, reason: 'הפוקוס חוזר לשדה');
  });
}
