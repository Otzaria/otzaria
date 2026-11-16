import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import '../../test_helpers/activate_correction_paragraph.dart';

Future<PluginCorrectionSessionService> _begin(
  WidgetTester tester,
  List<String> sources,
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
      loadSource: (index) async => sources[index],
    ),
  );
  return service;
}

Future<void> _pumpEditor(
  WidgetTester tester,
  PluginCorrectionSessionService service,
  String source, {
  int section = 0,
  Brightness brightness = Brightness.light,
  bool activate = true,
  Widget? original,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: PluginCorrectionParagraph(
            tabId: 'tab',
            sectionIndex: section,
            sourceText: source,
            settings: const RenderSettings(fontSize: 20),
            original: original ?? const Text('קריאה'),
            service: service,
            sessionActive: true,
          ),
        ),
      ),
    ),
  );
  if (activate && find.byType(EditableText).evaluate().isEmpty) {
    await activateCorrectionParagraph(tester, find.text('קריאה'));
    await tester.pump();
  }
}

EditableText _editor(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText));

TextSpan _renderedSpan(WidgetTester tester) {
  final editor = _editor(tester);
  return editor.controller.buildTextSpan(
    context: tester.element(find.byType(EditableText)),
    style: editor.style,
    withComposing: true,
  );
}

Future<void> _finish(
  WidgetTester tester,
  PluginCorrectionSessionService service,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() async {
    expect(await service.flushAll(), isTrue);
    await service.shutdown(timeout: const Duration(seconds: 5));
    expect(await service.flushAll(), isTrue);
  });
  await tester.pump();
}

TextStyle _styleAt(TextSpan span, int offset, [TextStyle? inherited]) {
  final style = (inherited ?? const TextStyle()).merge(span.style);
  final ownLength = span.text?.length ?? 0;
  if (offset < ownLength) return style;
  offset -= ownLength;
  for (final child in span.children ?? <InlineSpan>[]) {
    final length = child.toPlainText().length;
    if (offset < length) return _styleAt(child as TextSpan, offset, style);
    offset -= length;
  }
  throw RangeError('אין תו במיקום המבוקש');
}

void main() {
  testWidgets('ביטול וביצוע חוזר במקלדת מעדכנים גם את טיוטת הטקסט', (
    tester,
  ) async {
    const source = 'אב<b>גד</b>ה';
    final service = await _begin(tester, [source]);
    await _pumpEditor(tester, service, source);
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump(const Duration(seconds: 1));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'אבה',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(service.editableText('tab', 0, source), 'אבה');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(_editor(tester).controller.text, 'אבגדה');
    expect(service.editableText('tab', 0, source), 'אבגדה');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(_editor(tester).controller.text, 'אבה');
    expect(service.editableText('tab', 0, source), 'אבה');
    await _finish(tester, service);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'ביטול וביצוע חוזר משחזרים עיצוב של מופע חוזר אחרי שתי עריכות',
    (
      tester,
    ) async {
      const source = '<b>אב</b> אב <i>גד</i>';
      final service = await _begin(tester, [source]);
      await _pumpEditor(tester, service, source);
      await tester.showKeyboard(find.byType(EditableText));
      await tester.pump(const Duration(seconds: 1));
      _editor(tester).controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'אב גד',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        _styleAt(_renderedSpan(tester), 0).fontWeight,
        isNot(FontWeight.bold),
      );
      _editor(tester).controller.selection = const TextSelection(
        baseOffset: 3,
        extentOffset: 5,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'אב דה',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      Future<void> undoOrRedo({bool redo = false}) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await undoOrRedo();
      expect(_editor(tester).controller.text, 'אב גד');
      expect(
        _styleAt(_renderedSpan(tester), 0).fontWeight,
        isNot(FontWeight.bold),
      );
      expect(_styleAt(_renderedSpan(tester), 3).fontStyle, FontStyle.italic);
      expect(service.editableText('tab', 0, source), 'אב גד');
      await undoOrRedo();
      expect(_editor(tester).controller.text, 'אב אב גד');
      expect(_styleAt(_renderedSpan(tester), 0).fontWeight, FontWeight.bold);
      expect(
        _styleAt(_renderedSpan(tester), 3).fontWeight,
        isNot(FontWeight.bold),
      );
      await undoOrRedo(redo: true);
      expect(_editor(tester).controller.text, 'אב גד');
      expect(
        _styleAt(_renderedSpan(tester), 0).fontWeight,
        isNot(FontWeight.bold),
      );
      expect(_styleAt(_renderedSpan(tester), 3).fontStyle, FontStyle.italic);
      await undoOrRedo(redo: true);
      expect(_editor(tester).controller.text, 'אב דה');
      expect(
        _styleAt(_renderedSpan(tester), 0).fontWeight,
        isNot(FontWeight.bold),
      );
      expect(_styleAt(_renderedSpan(tester), 3).fontStyle, FontStyle.italic);
      expect(service.editableText('tab', 0, source), 'אב דה');
      await _finish(tester, service);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.android,
    }),
  );

  testWidgets('הרכבה מחדש אחרי מחיקת מופע חוזר אינה מעבירה אליו הדגשה', (
    tester,
  ) async {
    const source = '<b>אב</b> אב <i>גד</i>';
    final service = await _begin(tester, [source]);
    await _pumpEditor(tester, service, source);
    await tester.showKeyboard(find.byType(EditableText));
    _editor(tester).controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 3,
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'אב גד',
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await _pumpEditor(tester, service, source);
    expect(_editor(tester).controller.text, 'אב גד');
    expect(
      _styleAt(_renderedSpan(tester), 0).fontWeight,
      isNot(FontWeight.bold),
    );
    expect(_styleAt(_renderedSpan(tester), 3).fontStyle, FontStyle.italic);
    await _finish(tester, service);
  });

  for (final separator in ['\n', '\r\n', '\r']) {
    testWidgets('סנכרון RTL עם שבר קשיח נשאר תקין: ${separator.codeUnits}', (
      tester,
    ) async {
      final controller = PluginCorrectionController('<b>אב</b>$separatorגד');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RtlTextField(controller: controller, maxLines: null),
          ),
        ),
      );
      await tester.showKeyboard(find.byType(EditableText));
      await tester.pump(const Duration(seconds: 1));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'אב\r\nגה',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 4, end: 6),
        ),
      );
      await tester.pump();
      expect(controller.text, 'אב\nגה');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      expect(controller.value.composing, const TextRange(start: 3, end: 5));
      expect(_editor(tester).controller.text, 'אב\r\nגה');
      expect(_renderedSpan(tester).toPlainText(), 'אב\r\nגה');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'אב\r\nגה',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.text, 'אב\nגד');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets('שחזור והרכבה מחדש שומרים עיצוב בעורך ומקור מעוצב ללא שינוי', (
    tester,
  ) async {
    const source =
        '<div><font color="#ff0000"><s>אב</s></font> רגיל <i>גד</i></div>';
    const proposed = ' אם רגיל גק ';
    const original = SmartTextWidget(
      text: source,
      settings: RenderSettings(fontSize: 20),
    );
    final service = await _begin(tester, [source]);
    await _pumpEditor(
      tester,
      service,
      source,
      activate: false,
      original: original,
    );
    await tester.pumpAndSettle();
    TextStyle readerStyle(String character) {
      final span = tester
          .renderObjectList<RenderParagraph>(
            find.descendant(
              of: find.byType(SmartTextWidget),
              matching: find.byType(RichText),
            ),
          )
          .map((paragraph) => paragraph.text)
          .firstWhere(
            (span) => span.toPlainText().contains(character),
          );
      return _styleAt(span as TextSpan, span.toPlainText().indexOf(character));
    }

    final redStruck = readerStyle('א');
    final italic = readerStyle('ד');
    expect(redStruck.color, const Color(0xffff0000));
    expect(redStruck.decoration?.contains(TextDecoration.lineThrough), isTrue);
    expect(italic.fontStyle, FontStyle.italic);
    final restored = (await tester.runAsync(
      () => service.restore(
        owner: 'owner',
        id: service.sessionIdForTab('owner', 'tab')!,
        expectedRevision: 0,
        bookUid: 'id:1',
        libraryVersion: '1',
        changes: [
          {
            'sectionIndex': 0,
            'originalSourceText': source,
            'originalText': TextRendererService.stripHtml(source),
            'proposedText': proposed,
          },
        ],
      ),
    ))!;
    await tester.pump();
    expect(_editor(tester).controller.text, 'אם רגיל גק');
    expect(
      _styleAt(_renderedSpan(tester), 0).color,
      _editor(tester).style.color,
    );
    void expectEditorFormatting() {
      final span = _renderedSpan(tester);
      expect(
        _styleAt(span, 0).decoration?.contains(TextDecoration.lineThrough),
        isTrue,
      );
      expect(
        _styleAt(span, 3).decoration?.contains(TextDecoration.lineThrough),
        isNot(isTrue),
      );
      expect(_styleAt(span, 3).fontStyle, isNot(FontStyle.italic));
      expect(_styleAt(span, 8).fontStyle, FontStyle.italic);
    }

    expectEditorFormatting();
    final oldController = _editor(tester).controller;
    await tester.pumpWidget(const SizedBox());
    await _pumpEditor(tester, service, source, original: original);
    expect(_editor(tester).controller, isNot(same(oldController)));
    expect(_editor(tester).controller.text, 'אם רגיל גק');
    expectEditorFormatting();
    expect(service.editableText('tab', 0, source), proposed);
    final change = (restored['changes'] as List).single as Map;
    expect(change['originalSourceText'], source);
    expect(change['originalText'], TextRendererService.stripHtml(source));
    service.reset(
      'owner',
      service.sessionIdForTab('owner', 'tab')!,
      0,
      restored['revision'] as int,
    );
    await tester.pumpAndSettle();
    expect(find.byType(RtlTextField), findsNothing);
    expect(
      tester.widget<SmartTextWidget>(find.byType(SmartTextWidget)).text,
      source,
    );
    expect(readerStyle('א'), redStruck);
    expect(readerStyle('ד'), italic);
    await _finish(tester, service);
  });

  testWidgets('הקשה, קישור, הערה, פוקוס צאצא ובחירה משמרים את המקור', (
    tester,
  ) async {
    const source = 'קישור הערה';
    const originalKey = ValueKey('selectable-original');
    final service = await _begin(tester, [source]);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var links = 0;
    var notes = 0;
    final link = TapGestureRecognizer()..onTap = () => links++;
    final note = TapGestureRecognizer()..onTap = () => notes++;
    addTearDown(link.dispose);
    addTearDown(note.dispose);
    await _pumpEditor(
      tester,
      service,
      source,
      activate: false,
      original: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(text: 'קישור', recognizer: link),
            TextSpan(text: ' הערה', recognizer: note),
          ],
        ),
        key: originalKey,
        focusNode: focus,
        style: const TextStyle(fontSize: 20),
      ),
    );
    final originalElement = tester.element(find.byKey(originalKey));
    final selectable = find.descendant(
      of: find.byKey(originalKey),
      matching: find.byType(EditableText),
    );
    final state = tester.state<EditableTextState>(selectable);
    Offset point(int offset) => state.renderEditable.localToGlobal(
      state.renderEditable
          .getLocalRectForCaret(TextPosition(offset: offset))
          .center,
    );
    await tester.tapAt(point(1));
    await tester.pump(const Duration(milliseconds: 350));
    expect(links, 1);
    expect(find.byType(RtlTextField), findsNothing);
    expect(tester.element(find.byKey(originalKey)), same(originalElement));
    await tester.tapAt(point(7));
    await tester.pump(const Duration(milliseconds: 350));
    expect(notes, 1);
    expect(find.byType(RtlTextField), findsNothing);
    focus.requestFocus();
    await tester.pump();
    await tester.dragFrom(
      point(1),
      point(8) - point(1),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(focus.hasFocus, isTrue);
    expect(state.widget.controller.selection.isCollapsed, isFalse);
    expect(find.byType(RtlTextField), findsNothing);
    expect(service.isCorrected('tab', 0, source), isFalse);
    await _finish(tester, service);
  });

  testWidgets('רווח שהוקלד אחרי הסרת שולי HTML אינו מבטל IME בהד חוזר', (
    tester,
  ) async {
    const source = '<br><b>אב</b><br>';
    final service = await _begin(tester, [source, 'אחר']);
    service.editParagraph('tab', 0, source, 'אם');
    await _pumpEditor(tester, service, source);
    await tester.showKeyboard(find.byType(EditableText));
    const input = TextEditingValue(
      text: ' אמת ',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 1, end: 4),
    );
    tester.testTextInput.updateEditingValue(input);
    await tester.pump();
    service.editParagraph('tab', 1, 'אחר', 'חדש');
    await tester.pump(const Duration(milliseconds: 350));
    expect(_editor(tester).controller.value, input);
    expect(service.editableText('tab', 0, source), input.text);
    expect(_editor(tester).focusNode.hasFocus, isTrue);
    await _finish(tester, service);
  });

  testWidgets('מאפיין עם סוגר תג מצוטט שאינו קנוני נשאר במקור', (tester) async {
    const source = '<b title="x > y">אב</b>';
    final service = await _begin(tester, [source]);
    await _pumpEditor(tester, service, source, activate: false);
    await activateCorrectionParagraph(tester, find.text('קריאה'));
    expect(find.text('קריאה'), findsOneWidget);
    expect(find.byType(RtlTextField), findsNothing);
    await _finish(tester, service);
  });
  for (final source in [
    '<br><b>אב</b>',
    '<b>אב</b><br>',
    '<br><b>אב</b><br>',
  ]) {
    testWidgets('תיקון מקלדת אינו משכפל שולי בלוק שנמחקו: $source', (
      tester,
    ) async {
      final service = await _begin(tester, [source]);
      service.editParagraph('tab', 0, source, 'אם');
      await _pumpEditor(tester, service, source);
      expect(_editor(tester).controller.text, 'אם');
      await tester.showKeyboard(find.byType(EditableText));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'אמת',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      expect(service.editableText('tab', 0, source), 'אמת');
      await _finish(tester, service);
    });
  }

  testWidgets('בחירה ו-IME נשמרים בעורך הטקסט בעת הקלדה והתראה חיצונית', (
    tester,
  ) async {
    const source = '<b>אב גד</b>';
    final service = await _begin(tester, [source, 'אחר']);
    await _pumpEditor(tester, service, source);
    await tester.showKeyboard(find.byType(EditableText));
    const value = TextEditingValue(
      text: 'אבו גד',
      selection: TextSelection(baseOffset: 1, extentOffset: 3),
      composing: TextRange(start: 0, end: 3),
    );
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
    expect(_editor(tester).controller.value, value);
    final span = _renderedSpan(tester);
    expect(span.toPlainText(), value.text);
    expect(_styleAt(span, 1).decoration, TextDecoration.underline);
    service.editParagraph('tab', 1, 'אחר', 'חדש');
    await tester.pump();
    expect(_editor(tester).controller.value, value);
    expect(_editor(tester).focusNode.hasFocus, isTrue);
    tester.testTextInput.updateEditingValue(
      value.copyWith(composing: TextRange.empty),
    );
    await tester.pump();
    expect(_editor(tester).controller.value.composing, TextRange.empty);
    await _finish(tester, service);
  });

  testWidgets('עדכון חיצוני מסנכרן טקסט בלי להחליף עורך או מיקוד', (
    tester,
  ) async {
    const source = '<b>אב</b> <i>גד</i>';
    final service = await _begin(tester, [source]);
    await _pumpEditor(tester, service, source);
    await tester.showKeyboard(find.byType(EditableText));
    final controller = _editor(tester).controller;
    final focus = _editor(tester).focusNode;
    service.editParagraph('tab', 0, source, 'אם גד');
    await tester.pump();
    final span = _renderedSpan(tester);
    expect(span.toPlainText(), 'אם גד');
    expect(_editor(tester).controller, same(controller));
    expect(_editor(tester).focusNode, same(focus));
    expect(focus.hasFocus, isTrue);
    await _finish(tester, service);
  });

  testWidgets('מעבר פסקה עם אותו טקסט מרענן מקור גם במצב כהה', (tester) async {
    const first = '<b>אב</b>';
    const second = '<i>אב</i>';
    final service = await _begin(tester, [first, second]);
    await _pumpEditor(tester, service, first);
    await _pumpEditor(tester, service, second, section: 1);
    final lightSpan = _renderedSpan(tester);
    expect(lightSpan.toPlainText(), 'אב');
    await _pumpEditor(
      tester,
      service,
      second,
      section: 1,
      brightness: Brightness.dark,
    );
    final darkSpan = _renderedSpan(tester);
    expect(darkSpan.toPlainText(), 'אב');
    expect(_styleAt(darkSpan, 0).color, _editor(tester).style.color);
    expect(tester.takeException(), isNull);
    await _finish(tester, service);
  });

  testWidgets('פסקת p שומרת רווחים מקוריים בלי רווחי בלוק או הזחה מלאכותית', (
    tester,
  ) async {
    const source = '<p>  אב  גד  </p>';
    final service = await _begin(tester, [source]);
    await _pumpEditor(tester, service, source);
    expect(_editor(tester).controller.text, '  אב  גד  ');
    expect(_renderedSpan(tester).toPlainText(), '  אב  גד  ');
    expect(
      tester.getTopRight(find.byType(EditableText)).dx,
      tester.getTopRight(find.byType(PluginCorrectionParagraph)).dx,
    );
    await tester.showKeyboard(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '  אם  גד  ',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pump();
    expect(_renderedSpan(tester).toPlainText(), '  אם  גד  ');
    expect(service.editableText('tab', 0, source), '   אם  גד   ');
    expect(
      tester.getTopRight(find.byType(EditableText)).dx,
      tester.getTopRight(find.byType(PluginCorrectionParagraph)).dx,
    );
    await _finish(tester, service);
  });

  testWidgets('המקור נשמר לפני עריכה וחוזר אחרי יציאה ממיקוד ואיפוס', (
    tester,
  ) async {
    const source = '<span style="color: red">אב</span>';
    final service = await _begin(tester, [source]);
    await _pumpEditor(tester, service, source, activate: false);
    expect(find.text('קריאה'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    await activateCorrectionParagraph(tester, find.text('קריאה'));
    await tester.pump();
    await tester.showKeyboard(find.byType(EditableText));
    _editor(tester).focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('קריאה'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(service.isCorrected('tab', 0, source), isFalse);
    await activateCorrectionParagraph(tester, find.text('קריאה'));
    await tester.pump();
    await tester.showKeyboard(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'אם',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    expect(service.isCorrected('tab', 0, source), isTrue);
    service.editParagraph('tab', 0, source, 'אב');
    await tester.pump();
    expect(service.isCorrected('tab', 0, source), isFalse);
    expect(_editor(tester).controller.text, 'אב');
    _editor(tester).focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('קריאה'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    await _finish(tester, service);
  });

  testWidgets('Tab מפעיל פסקה שטרם נערכה ומעביר מיקוד לעורך', (tester) async {
    const source = '<b>אב גד</b>';
    final service = await _begin(tester, [source]);
    await _pumpEditor(tester, service, source, activate: false);
    expect(find.byType(EditableText), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(find.byType(EditableText), findsOneWidget);
    expect(_editor(tester).focusNode.hasFocus, isTrue);
    expect(_editor(tester).controller.text, 'אב גד');
    await _finish(tester, service);
  });

  testWidgets('דאבל קליק בקצה הימני של המקור ממקם סמן בתחילת הטקסט', (
    tester,
  ) async {
    const source = 'אב גד';
    final service = await _begin(tester, [source]);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 600,
              child: PluginCorrectionParagraph(
                tabId: 'tab',
                sectionIndex: 0,
                sourceText: source,
                settings: const RenderSettings(fontSize: 20),
                original: const Text(source, style: TextStyle(fontSize: 20)),
                service: service,
                sessionActive: true,
              ),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.text(source));
    await activateCorrectionParagraph(
      tester,
      find.text(source),
      position: Offset(rect.right - 1, rect.center.dy),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(EditableText), findsOneWidget);
    expect(_editor(tester).focusNode.hasFocus, isTrue);
    expect(
      _editor(tester).controller.selection,
      const TextSelection.collapsed(offset: 0),
    );
    await _finish(tester, service);
  });

  testWidgets('פסקה עם מעבר שורה נשארת במקור ואינה מפעילה עורך', (
    tester,
  ) async {
    const source = 'אב\nגד';
    final service = await _begin(tester, [source]);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: PluginCorrectionParagraph(
              tabId: 'tab',
              sectionIndex: 0,
              sourceText: source,
              settings: const RenderSettings(fontSize: 20),
              original: const Text(source, style: TextStyle(fontSize: 20)),
              service: service,
              sessionActive: true,
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.text(source));
    await tester.tapAt(Offset(rect.right - 1, rect.bottom - 10));
    await tester.pump();
    await tester.pump();
    expect(find.text(source), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(service.isCorrected('tab', 0, source), isFalse);
    await _finish(tester, service);
  });
}
