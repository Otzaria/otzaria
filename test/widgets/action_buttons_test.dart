import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

void main() {
  testWidgets('NeutralActionButton מרכז טקסט ומשאיר אייקון בצד במצב center', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: SizedBox(
                width: 320,
                child: ActionButton.neutral(
                  text: 'חלץ מקובץ דחוס',
                  onPressed: () {},
                  iconWidget: const RtlIcon(
                    FluentIcons.folder_zip_24_regular,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final buttonFinder = find.byType(FilledButton);
    final textFinder = find.text('חלץ מקובץ דחוס');
    final iconFinder = find.byType(RtlIcon);

    final buttonCenter = tester.getCenter(buttonFinder);
    final textCenter = tester.getCenter(textFinder);
    final iconCenter = tester.getCenter(iconFinder);

    expect(textCenter.dx, closeTo(buttonCenter.dx, 3));
    expect(iconCenter.dx, greaterThan(textCenter.dx + 20));
  });
}
