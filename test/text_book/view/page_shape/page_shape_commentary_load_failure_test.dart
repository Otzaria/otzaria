// טור מפרש שטעינתו נכשלה בצורת הדף אינו נתקע: כשל זמני לא נשמר במטמון,
// והחלונית מציעה "נסה שוב" (issue #5744).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';

import 'page_shape_commentary_failure_harness.dart';

const _commentator = 'מפרש זמני';
const _failedMessage = 'לא ניתן לטעון את $_commentator';
const _retry = 'נסה שוב';

void main() {
  setUpPageShapeFailureTests();

  // תרחיש אחד לקובץ: אתחול המסד שמתחיל בבדיקת צורת הדף נשאר תלוי באזור
  // הזמן שלה, ובדיקה נוספת בקובץ הייתה ממתינה לו לנצח.
  testWidgets('כשל זמני בטעינת מפרש מציע "נסה שוב" ואינו נשמר במטמון '
      '(issue #5744)', (tester) async {
    // חריגה זמנית: הטור נשאר עם הודעה וכפתור, והלחיצה טוענת את המפרש.
    final provider = FakeCommentaryProvider(const [_commentator])
      ..textFailures = 1;
    await pumpPageShape(tester, provider, bookTitle: 'ספר א');
    await pumpUntil(tester, () => provider.textFailures == 0);
    await pumpUntil(tester, () => false);
    expect(find.text(_failedMessage), findsOneWidget);
    expect(find.text(_retry), findsOneWidget);
    await tester.runAsync(ErrorLogFile.flushPending);
    expect(
      File(ErrorLogFile.resolvePath()).readAsStringSync(),
      contains('database is locked'),
    );
    await tester.tap(find.text(_retry));
    await pumpUntil(tester, () => commentaryViewer().evaluate().isNotEmpty);
    expect(find.text(_failedMessage), findsNothing);
    expect(
      tester.widget<SimpleTextViewer>(commentaryViewer()).bookTitle,
      _commentator,
    );

    // טקסט ריק: הטור מוסתר כמקודם, אבל הכשל אינו נשמר במטמון — פתיחה
    // מחדש של הספר טוענת את המפרש.
    const missing = 'מפרש ריק';
    final empty = FakeCommentaryProvider(const [missing])..emptyTexts = 1;
    await pumpPageShape(tester, empty, bookTitle: 'ספר ב');
    await pumpUntil(tester, () => empty.emptyTexts == 0);
    await pumpUntil(tester, () => false);
    expect(find.text('לא ניתן לטעון את $missing'), findsNothing);
    expect(commentaryViewer(), findsNothing);
    await pumpPageShape(tester, empty, bookTitle: 'ספר ב');
    await pumpUntil(tester, () => commentaryViewer().evaluate().isNotEmpty);
    expect(
      tester.widget<SimpleTextViewer>(commentaryViewer()).bookTitle,
      missing,
    );
  });
}
