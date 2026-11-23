import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/widgets/text/rtl_text_field.dart';

void main() {
  testWidgets(
    'שדה שעלה על FocusNode בפוקוס לא מחזיר אליו פוקוס אם עבר לפקד אחר באותו פריים (#2536)',
    (tester) async {
      final shared = FocusNode();
      final other = FocusNode();
      addTearDown(shared.dispose);
      addTearDown(other.dispose);
      var showField = false;
      late StateSetter setOuter;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return Column(
                  children: [
                    if (showField)
                      RtlTextField(
                        focusNode: shared,
                        autofocus:
                            defaultTargetPlatform == TargetPlatform.android,
                      )
                    else
                      Focus(focusNode: shared, child: const SizedBox()),
                    Focus(focusNode: other, child: const Text('אחר')),
                  ],
                );
              },
            ),
          ),
        ),
      );
      shared.requestFocus();
      await tester.pump();
      expect(shared.hasPrimaryFocus, isTrue);

      // השדה עולה על FocusNode שכבר בפוקוס, ובאותו פריים הפוקוס עובר לפקד אחר.
      tester.binding.addPostFrameCallback((_) {
        other.requestFocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
      });
      setOuter(() => showField = true);
      await tester.pump();
      await tester.pump();

      expect(other.hasPrimaryFocus, isTrue);
      expect(shared.hasFocus, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.linux,
    }),
  );

  testWidgets('שדה שעלה על FocusNode בפוקוס פותח מקלדת (#2536)', (
    tester,
  ) async {
    final shared = FocusNode();
    addTearDown(shared.dispose);
    var showField = false;
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return showField
                  ? RtlTextField(focusNode: shared)
                  : Focus(focusNode: shared, child: const SizedBox());
            },
          ),
        ),
      ),
    );
    shared.requestFocus();
    await tester.pump();
    setOuter(() => showField = true);
    await tester.pump();
    await tester.pump();

    expect(shared.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
  });
}
