import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/share/shared_selection.dart';
import 'package:otzaria/core/share/text_share_service.dart';
import 'package:otzaria/core/ui_snack.dart';

class _FakeShareService implements TextShareService {
  final shared = <String>[];

  /// כשאינו null, השיתוף זורק אותו (כמו PlatformException מהגיליון).
  Object? failure;

  @override
  Future<void> shareText(String text, {Rect? origin}) async {
    if (failure != null) throw failure!;
    shared.add(text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeShareService share;
  late TextShareService previous;

  setUp(() {
    previous = TextShareService.instance;
    share = _FakeShareService();
    TextShareService.instance = share;
  });

  tearDown(() => TextShareService.instance = previous);

  group('segmentCount מהקורא', () {
    // שורות מקור שמוצגות כפסקה ממוזגת מופרדות ברווח ולא ב-\n, ולכן ספירה לפי
    // הטקסט מחזירה 1 גם כשהטווח במקור גדול מהמותר.
    const mergedParagraph = 'שורה אחת שורה שתיים שורה שלוש';
    const protection = BookProtection(level: 1);

    test('טווח שורות מעל המגבלה נחסם גם כשהטקסט ללא \\n', () async {
      await shareSelectedText(
        mergedParagraph,
        protection: protection,
        segmentCount: BookProtection.copySegmentLimit + 1,
      );
      expect(share.shared, isEmpty);
    });

    test('טווח שורות עד המגבלה מותר', () async {
      await shareSelectedText(
        mergedParagraph,
        protection: protection,
        segmentCount: BookProtection.copySegmentLimit,
      );
      expect(share.shared, [mergedParagraph]);
    });

    test('בלי segmentCount הספירה לפי הטקסט, כמו קודם', () async {
      await shareSelectedText(mergedParagraph, protection: protection);
      expect(share.shared, [mergedParagraph]);
    });
  });

  group('כשל בגיליון השיתוף', () {
    testWidgets('לא זורק ומציג הודעה קצרה', (tester) async {
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
      );
      share.failure = Exception('TransactionTooLargeException');

      await shareSelectedText('טקסט ארוך');
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(CommonMessages.shareFailed), findsOneWidget);

      UiSnack.hide();
      await tester.pump(const Duration(seconds: 5));
    });

    test('לא זורק גם בלי חלון להצגת ההודעה', () async {
      share.failure = Exception('no activity');
      await expectLater(shareSelectedText('טקסט'), completes);
    });
  });
}
