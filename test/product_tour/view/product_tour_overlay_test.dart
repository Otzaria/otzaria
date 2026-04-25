import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/product_tour/product_tour_exports.dart';

void main() {
  testWidgets('ProductTourOverlay מציג מבנה כרטיס חדש עם סיום, מונה וטיפ',
      (tester) async {
    final state = ProductTourState.initial().copyWith(
      activeIntroStepIndex: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ProductTourOverlay(
                state: state,
                onNext: () {},
                onPrevious: () {},
                onDismiss: () {},
                onFinish: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('סיום'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('טיפ'), findsOneWidget);
    expect(find.text('איתור מקור מדויק'), findsOneWidget);
  });
}
