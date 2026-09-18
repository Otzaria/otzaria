import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Directionality(textDirection: TextDirection.rtl, child: child),
  ),
);

/// ה-x של התו הראשון מ-[needle] בתוך הפסקה שמכילה את [marker].
double _charLeft(WidgetTester tester, String marker, String needle) {
  final paragraph = tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .firstWhere((p) => p.text.toPlainText().contains(marker));
  final text = paragraph.text.toPlainText();
  final offset = text.indexOf(needle);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: offset, extentOffset: offset + 1),
  );
  return boxes.first.left;
}

void main() {
  for (final (pinned, width) in [
    (false, 800.0),
    (true, 800.0),
    (true, 420.0),
  ]) {
    testWidgets('נתיב עם שם עברי מוצג משמאל לימין ($pinned, $width)', (
      tester,
    ) async {
      const path = r'D:\מסדים משותפים';
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: width,
            child: SettingsActionTile.path(
              icon: FluentIcons.folder_24_regular,
              title: 'תיקיית מסדים',
              path: path,
              placeholder: '',
              pinnedTrailing: pinned
                  ? IconButton(onPressed: () {}, icon: const Icon(Icons.abc))
                  : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final drive = _charLeft(tester, 'D:', 'D');
      final colon = _charLeft(tester, 'D:', ':');
      final hebrew = _charLeft(tester, 'D:', 'מ');
      expect(drive, lessThan(colon));
      expect(colon, lessThan(hebrew));
    });
  }
}
