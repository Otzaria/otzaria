import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/reader_menu_entries.dart';

void main() {
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (value) {
          context = value;
          return const SizedBox.shrink();
        },
      ),
    );
    return context;
  }

  testWidgets('בלי onShare אין פעולת שיתוף בשורת הפעולות', (tester) async {
    final context = await pumpContext(tester);
    final row = buildReaderIconRow(
      context: context,
      selection: ReaderMenuSelection('בראשית'),
      book: TextBook(title: 'ספר'),
      paragraphIndex: 0,
      selectedText: 'בראשית',
      sourceSelectedText: 'בראשית',
      onCopy: () {},
      onAddNote: () {},
    );
    expect(
      row.iconRowActions!.map((a) => a.label),
      isNot(contains('שיתוף')),
    );
  });

  testWidgets('עם onShare: פעולת "שיתוף" פעילה כשיש בחירה ומפעילה אותו', (
    tester,
  ) async {
    final context = await pumpContext(tester);
    var shared = 0;
    final row = buildReaderIconRow(
      context: context,
      selection: ReaderMenuSelection('בראשית'),
      book: TextBook(title: 'ספר'),
      paragraphIndex: 0,
      selectedText: 'בראשית',
      sourceSelectedText: 'בראשית',
      onCopy: () {},
      onAddNote: () {},
      onShare: () => shared++,
    );
    final labels = row.iconRowActions!.map((a) => a.label).toList();
    final share = row.iconRowActions!.singleWhere((a) => a.label == 'שיתוף');
    expect(share.enabled, isTrue);
    share.onTap!();
    expect(shared, 1);
    expect(
      labels.indexOf('שיתוף'),
      labels.indexOf('העתקה') + 1,
      reason: 'השיתוף צמוד להעתקה',
    );
  });

  testWidgets('בלי טקסט נבחר פעולת השיתוף מנוטרלת', (tester) async {
    final context = await pumpContext(tester);
    final row = buildReaderIconRow(
      context: context,
      selection: ReaderMenuSelection(''),
      book: TextBook(title: 'ספר'),
      paragraphIndex: 0,
      selectedText: null,
      sourceSelectedText: null,
      onCopy: () {},
      onAddNote: () {},
      onShare: () {},
    );
    expect(
      row.iconRowActions!.singleWhere((a) => a.label == 'שיתוף').enabled,
      isFalse,
    );
  });
}
