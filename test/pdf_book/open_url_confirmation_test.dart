import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/widgets/open_url_confirmation.dart';

/// דיאלוג האישור למעבר לכתובת חיצונית מתוך PDF (issue #1482).
void main() {
  final url = Uri.parse('https://example.com/a/b?q=1&x=2');

  Future<void> open(WidgetTester tester, {bool Function()? onResult}) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showOpenUrlConfirmation(context, url);
                },
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    expect(result, isNull, reason: 'הדיאלוג עדיין פתוח');
  }

  testWidgets('הכתובת מוצגת בכיוון LTR מפורש (issue #1482)', (tester) async {
    await open(tester);

    final urlText = tester.widget<Text>(find.text(url.toString()));
    expect(
      urlText.textDirection,
      TextDirection.ltr,
      reason: 'בפסקה RTL ה-bidi מסדר מחדש את הסלאש והפרמטרים של הכתובת',
    );
  });
}
