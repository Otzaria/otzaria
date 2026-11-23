import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import '../../test_helpers/activate_correction_paragraph.dart';

void main() {
  Future<PluginCorrectionSessionService> begin(
    WidgetTester tester,
    List<String> texts,
  ) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final service = PluginCorrectionSessionService()
      ..draftRepository = PluginCorrectionDraftRepository.direct(db);
    addTearDown(service.dispose);
    await tester.runAsync(
      () => service.begin(
        owner: 'owner',
        tabId: 'tab',
        bookId: 'ספר',
        bookUid: 'id:1',
        libraryVersion: '1',
        loadSource: (index) async => texts[index],
      ),
    );
    return service;
  }

  Widget paragraphs(
    PluginCorrectionSessionService service,
    List<String> texts, {
    double width = 400,
  }) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                for (var i = 0; i < texts.length; i++)
                  PluginCorrectionParagraph(
                    tabId: 'tab',
                    sectionIndex: i,
                    sourceText: texts[i],
                    settings: const RenderSettings(fontSize: 14),
                    original: Text('קריאה $i'),
                    service: service,
                    sessionActive: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> finish(
    WidgetTester tester,
    PluginCorrectionSessionService service,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => service.flushAll());
  }

  EditableText editor(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText));

  /// בקר העורך הנקי; ל-EditableText עצמו מגיע בקר פנימי עם \r\n.
  PluginCorrectionController clean(WidgetTester tester) =>
      tester.widget<RtlTextField>(find.byType(RtlTextField)).controller
          as PluginCorrectionController;

  Future<void> type(WidgetTester tester, String text, int caret) async {
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openFirst(WidgetTester tester) async {
    await activateCorrectionParagraph(tester, find.text('קריאה 0'));
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump(const Duration(seconds: 1));
  }

  group('Enter', () {
    testWidgets('הפעולה במקלדת היא ירידת שורה ולא סיום', (tester) async {
      const texts = ['אבגד'];
      final service = await begin(tester, texts);
      await tester.pumpWidget(paragraphs(service, texts));
      await openFirst(tester);
      expect(editor(tester).textInputAction, TextInputAction.newline);
      await finish(tester, service);
    });

    testWidgets('ירידת שורה שהוקלדה נשמרת בהצעה ונשארת בשדה', (tester) async {
      const texts = ['אבגד'];
      final service = await begin(tester, texts);
      await tester.pumpWidget(paragraphs(service, texts));
      await openFirst(tester);
      await type(tester, 'אב\nגד', 3);
      expect(service.editableText('tab', 0, texts[0]), 'אב\nגד');
      expect(clean(tester).text, 'אב\nגד');
      await finish(tester, service);
    });

    testWidgets('תגית או ישות בהצעה עם ירידת שורה עדיין נדחות', (tester) async {
      const texts = ['אבגד'];
      final service = await begin(tester, texts);
      await tester.pumpWidget(paragraphs(service, texts));
      await openFirst(tester);
      await type(tester, 'אב\n<b>גד', 6);
      expect(service.editableText('tab', 0, texts[0]), texts[0]);
      await finish(tester, service);
    });

    testWidgets(
      'ביטול אחרי Enter בין אותיות מנוקדות ומחיקת השנייה מחזיר ניקוד',
      (
        tester,
      ) async {
        const source = 'בַבֹ';
        final service = await begin(tester, [source]);
        await tester.pumpWidget(paragraphs(service, [source]));
        await openFirst(tester);
        await type(tester, 'בַ\nבֹ', 3);
        await type(tester, 'בַ\nֹ', 3);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(clean(tester).text, 'בַ\nבֹ');
        expect(service.editableText('tab', 0, source), 'בַ\nבֹ');
        await finish(tester, service);
      },
    );
  });

  group('פסקה מעוצבת שפוצלה בירידת שורה', () {
    const source = 'אב<b>גד</b>ה';

    /// האם כל תו בטקסט המצויר מודגש, לפי הסגנון שמגיע ל-EditableText.
    List<bool> boldPerChar(WidgetTester tester) {
      final field = editor(tester);
      final span = field.controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: field.style,
        withComposing: false,
      );
      final flags = <bool>[];
      void walk(InlineSpan node, bool inherited) {
        if (node is! TextSpan) return;
        final bold = node.style?.fontWeight == FontWeight.bold || inherited;
        for (final unit in (node.text ?? '').codeUnits) {
          if (unit != 0x0D) flags.add(bold);
        }
        node.children?.forEach((child) => walk(child, bold));
      }

      walk(span, false);
      return flags;
    }

    testWidgets('העיצוב מוצג גם אחרי ירידת השורה', (tester) async {
      final service = await begin(tester, [source]);
      await tester.pumpWidget(paragraphs(service, [source]));
      await openFirst(tester);
      await type(tester, 'אב\nגדה', 3);
      expect(boldPerChar(tester), [false, false, false, true, true, false]);
      await finish(tester, service);
    });

    testWidgets('ביטול וביצוע חוזר אחרי מחיקת תו מודגש מחזירים את העיצוב', (
      tester,
    ) async {
      final service = await begin(tester, [source]);
      await tester.pumpWidget(paragraphs(service, [source]));
      await openFirst(tester);
      await type(tester, 'אב\nגדה', 3);
      await type(tester, 'אב\nדה', 3);
      Future<void> undoOrRedo({bool redo = false}) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await undoOrRedo();
      expect(clean(tester).text, 'אב\nגדה');
      expect(clean(tester).formats.map((f) => f.bold), [
        false,
        false,
        false,
        true,
        true,
        false,
      ]);
      expect(boldPerChar(tester), [false, false, false, true, true, false]);
      await undoOrRedo(redo: true);
      expect(clean(tester).text, 'אב\nדה');
      expect(clean(tester).formats.map((f) => f.bold), [
        false,
        false,
        false,
        true,
        false,
      ]);
      await finish(tester, service);
    });
  });

  group('חצים', () {
    testWidgets('מעבר מעלה לשורה האחרונה של תיקון רב שורתי', (tester) async {
      const texts = ['אבגד', 'אבגד'];
      final service = await begin(tester, texts);
      service.editParagraph('tab', 0, texts[0], 'אבגד\nאבגד');
      await tester.pumpWidget(paragraphs(service, texts));
      await activateCorrectionParagraph(tester, find.text('קריאה 1'));
      await tester.pump();
      final editors = find.byType(EditableText);
      final second = tester.widget<EditableText>(editors.last);
      expect(second.focusNode.hasFocus, isTrue);
      second.controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final first = tester.widget<EditableText>(editors.first);
      expect(first.focusNode.hasFocus, isTrue);
      expect(first.controller.selection.baseOffset, 10);
      await finish(tester, service);
    });

    testWidgets('חץ מטה ומעלה עוברים בין פסקאות ושומרים את העמודה', (
      tester,
    ) async {
      const texts = ['פסקה ראשונה', 'פסקה שנייה'];
      final service = await begin(tester, texts);
      await tester.pumpWidget(paragraphs(service, texts));
      await activateCorrectionParagraph(tester, find.text('קריאה 0'));
      await tester.pump();
      editor(tester).controller.selection = const TextSelection.collapsed(
        offset: 3,
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsOneWidget);
      expect(editor(tester).controller.text, texts[1]);
      expect(editor(tester).controller.selection.baseOffset, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(editor(tester).controller.text, texts[0]);
      expect(editor(tester).controller.selection.baseOffset, 3);
      await finish(tester, service);
    });

    testWidgets('בפסקה של כמה שורות החצים נעים בין השורות ורק בקצה עוברים', (
      tester,
    ) async {
      const long = 'אבגד הוזח טיכל מנסע פצקר שתאב גדהו זחטי כלמנ סעפצ קרשת';
      const texts = [long, 'פסקה שנייה'];
      final service = await begin(tester, texts);
      await tester.pumpWidget(paragraphs(service, texts, width: 160));
      await activateCorrectionParagraph(tester, find.text('קריאה 0'));
      await tester.pump();
      editor(tester).controller.selection = const TextSelection.collapsed(
        offset: 1,
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(editor(tester).controller.text, long);
      final moved = editor(tester).controller.selection.baseOffset;
      expect(moved, greaterThan(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(editor(tester).controller.text, long);
      expect(editor(tester).controller.selection.baseOffset, lessThan(moved));
      editor(tester).controller.selection = TextSelection.collapsed(
        offset: long.length,
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(editor(tester).controller.text, texts[1]);
      await finish(tester, service);
    });
  });

  group('Escape', () {
    testWidgets('יוצא מהעריכה בפסקה שלא תוקנה', (tester) async {
      const texts = ['פסקה ראשונה'];
      final service = await begin(tester, texts);
      await tester.pumpWidget(paragraphs(service, texts));
      await activateCorrectionParagraph(tester, find.text('קריאה 0'));
      await tester.pump();
      expect(find.byType(EditableText), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('קריאה 0'), findsOneWidget);
      await finish(tester, service);
    });

    testWidgets('בפסקה שתוקנה משאיר את התיקון ומוציא את המיקוד', (
      tester,
    ) async {
      const texts = ['פסקה ראשונה'];
      final service = await begin(tester, texts);
      await tester.pumpWidget(paragraphs(service, texts));
      await openFirst(tester);
      await type(tester, 'פסקה ראשונה!', 12);
      expect(service.editableText('tab', 0, texts[0]), 'פסקה ראשונה!');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(editor(tester).focusNode.hasFocus, isFalse);
      expect(service.editableText('tab', 0, texts[0]), 'פסקה ראשונה!');
      await finish(tester, service);
    });

    testWidgets('פסקה עם תיקון שמור שנפתחה מחדש לעריכה לא בולעת Escape', (
      tester,
    ) async {
      const texts = ['פסקה ראשונה'];
      final service = await begin(tester, texts);
      service.editParagraph('tab', 0, texts[0], 'פסקה ראשונה!');
      await tester.pumpWidget(paragraphs(service, texts));
      expect(find.byType(EditableText), findsOneWidget);
      await tester.tap(find.byType(EditableText));
      await tester.pump(const Duration(milliseconds: 50));
      expect(editor(tester).focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(editor(tester).focusNode.hasFocus, isFalse);
      expect(service.editableText('tab', 0, texts[0]), 'פסקה ראשונה!');
      await finish(tester, service);
    });
  });
}
