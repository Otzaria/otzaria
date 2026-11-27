import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/commentary_notes_section.dart';

PersonalNote _note(String bookId, int? line, String text, {String? title}) {
  final now = DateTime(2026);
  return PersonalNote(
    id: '$bookId-$line-$text',
    bookId: bookId,
    lineNumber: line,
    displayTitle: title,
    lastKnownLineNumber: line,
    status: line == null
        ? PersonalNoteStatus.missing
        : PersonalNoteStatus.located,
    content: text,
    contentPlain: text,
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Map<String, List<PersonalNote>> store;
  late ValueNotifier<int> revision;
  final opened = <(String, int)>[];

  setUp(() {
    store = {};
    revision = ValueNotifier(0);
    opened.clear();
  });

  Widget build(List<String> bookIds) => MaterialApp(
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: CommentaryNotesSection(
            bookIds: bookIds,
            revision: revision,
            loader: (bookId, {categoryId}) async => store[bookId] ?? const [],
            onOpenNote: (bookId, line) => opened.add((bookId, line)),
          ),
        ),
      ),
    ),
  );

  testWidgets('מציג רק מפרשים עם הערות ממוקמות, ולחיצה פותחת את ההערה', (
    tester,
  ) async {
    store = {
      'רש"י': [_note('רש"י', 4, 'הערה על רש"י', title: 'רש"י ד"ה אמר')],
      'תוספות': [_note('תוספות', null, 'הערה חסרת מיקום')],
    };

    await tester.pumpWidget(build(['רש"י', 'תוספות']));
    await tester.pumpAndSettle();

    expect(find.text('הערות על המפרשים המוצגים'), findsOneWidget);
    expect(find.text('רש"י ד"ה אמר'), findsOneWidget);
    expect(find.text('תוספות'), findsNothing);

    await tester.tap(find.text('הערה על רש"י'));
    expect(opened, [('רש"י', 4)]);
  });

  testWidgets('בלי הערות על המפרשים האזור לא מוצג', (tester) async {
    await tester.pumpWidget(build(['רש"י']));
    await tester.pumpAndSettle();

    expect(find.text('הערות על המפרשים המוצגים'), findsNothing);
  });

  testWidgets('נטען מחדש כשהערה נשמרת', (tester) async {
    await tester.pumpWidget(build(['רש"י']));
    await tester.pumpAndSettle();
    expect(find.text('הערות על המפרשים המוצגים'), findsNothing);

    store['רש"י'] = [_note('רש"י', 2, 'חדשה')];
    revision.value++;
    await tester.pumpAndSettle();

    expect(find.text('שורה 2'), findsOneWidget);
    expect(find.text('חדשה'), findsOneWidget);
  });

  testWidgets('בחירת הערות והעתקתן שומרת מעברי שורה וניווט בעכבר', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const firstContent = 'תוכן ההערה להעתקה';
    store = {
      'רש"י': [_note('רש"י', 4, firstContent)],
      'תוספות': [_note('תוספות', 5, 'תוכן נוסף', title: 'הערה שנייה')],
    };
    await tester.pumpWidget(build(['רש"י', 'תוספות']));
    await tester.pumpAndSettle();

    // לחיצה על הכותרת מעבירה את המיקוד לאזור בלי לפתוח הערה; Ctrl+A מסמן.
    await tester.tap(find.text('הערות על המפרשים המוצגים'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(opened, isEmpty);

    Future<void> copy() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC, character: 'ב');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await copy();
    expect(copied, [
      'הערות על המפרשים המוצגים\nרש"י\nשורה 4\n'
          '$firstContent\nתוספות\nהערה שנייה\nתוכן נוסף',
    ]);

    final content = find.text(firstContent);
    final richText = find.descendant(
      of: content,
      matching: find.byType(RichText),
    );
    final paragraph = tester.renderObject<RenderParagraph>(richText);
    final bounds = tester.getRect(richText);
    const partialContent = 'תוכן ההערה';
    final endCaret = paragraph.getOffsetForCaret(
      TextPosition(offset: partialContent.length),
      Rect.zero,
    );
    final dragEnd = Offset(
      paragraph.localToGlobal(endCaret).dx,
      bounds.center.dy,
    );
    final drag = await tester.startGesture(
      bounds.centerRight - const Offset(1, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await drag.moveBy(const Offset(-30, 0));
    await tester.pump();
    await drag.moveTo(dragEnd);
    await drag.up();
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await copy();
    expect(copied.last, partialContent);

    final rightClick = await tester.startGesture(
      Offset.lerp(bounds.centerRight, dragEnd, 0.5)!,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await rightClick.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('העתק'));
    await tester.pumpAndSettle();
    expect(copied, hasLength(3));
    expect(copied.last, partialContent);
    expect(opened, isEmpty);

    await tester.tap(content, kind: PointerDeviceKind.mouse);
    expect(opened, [('רש"י', 4)]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
