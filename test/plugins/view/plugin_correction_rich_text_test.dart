import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
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

  testWidgets('מאפיינים רגילים שומרים בולד בעורך המחובר', (tester) async {
    const source = '<b class="bold">אב</b>';
    final service = await _begin(tester, [source]);
    await _pumpEditor(tester, service, source);
    expect(_styleAt(_renderedSpan(tester), 0).fontWeight, FontWeight.bold);
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

  final styles = <String, Matcher>{
    'b': predicate<TextStyle>((style) => style.fontWeight == FontWeight.bold),
    'i': predicate<TextStyle>((style) => style.fontStyle == FontStyle.italic),
    'big': predicate<TextStyle>((style) => style.fontSize! > 20),
    'small': predicate<TextStyle>((style) => style.fontSize! < 20),
    'h2': predicate<TextStyle>(
      (style) => style.fontWeight == FontWeight.bold && style.fontSize! > 20,
    ),
  };
  for (final entry in styles.entries) {
    testWidgets('העורך המחובר משמר ${entry.key} לפני הקלדה ואחריה', (
      tester,
    ) async {
      final source = '<${entry.key}>אב</${entry.key}>';
      final service = await _begin(tester, [source]);
      await _pumpEditor(tester, service, source);
      expect(_renderedSpan(tester).toPlainText(), 'אב');
      expect(_styleAt(_renderedSpan(tester), 0), entry.value);
      await tester.showKeyboard(find.byType(EditableText));
      final focus = _editor(tester).focusNode;
      final controller = _editor(tester).controller;
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'אגב',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(_editor(tester).controller, same(controller));
      expect(_editor(tester).focusNode, same(focus));
      expect(focus.hasFocus, isTrue);
      expect(_renderedSpan(tester).toPlainText(), 'אגב');
      expect(_styleAt(_renderedSpan(tester), 1), entry.value);
      expect(_editor(tester).controller.selection.extentOffset, 2);
      expect(
        service.editableText('tab', 0, source),
        entry.key == 'h2' ? ' אגב ' : 'אגב',
      );
      await _finish(tester, service);
    });
  }

  testWidgets('בחירה ו-IME נשמרים בעורך המעוצב בעת הקלדה והתראה חיצונית', (
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
    expect(_styleAt(span, 1).fontWeight, FontWeight.bold);
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
    expect(_styleAt(_renderedSpan(tester), 1).fontWeight, FontWeight.bold);
    await _finish(tester, service);
  });

  testWidgets('עדכון חיצוני מסנכרן טקסט ועיצוב בלי להחליף עורך או מיקוד', (
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
    expect(_styleAt(span, 0).fontWeight, FontWeight.bold);
    expect(_styleAt(span, 3).fontStyle, FontStyle.italic);
    expect(_editor(tester).controller, same(controller));
    expect(_editor(tester).focusNode, same(focus));
    expect(focus.hasFocus, isTrue);
    await _finish(tester, service);
  });

  testWidgets('מעבר פסקה עם אותו טקסט מרענן סגנון גם במצב כהה', (tester) async {
    const first = '<b>אב</b>';
    const second = '<i>אב</i>';
    final service = await _begin(tester, [first, second]);
    await _pumpEditor(tester, service, first);
    expect(_styleAt(_renderedSpan(tester), 0).fontWeight, FontWeight.bold);
    await _pumpEditor(tester, service, second, section: 1);
    final lightSpan = _renderedSpan(tester);
    expect(lightSpan.toPlainText(), 'אב');
    expect(_styleAt(lightSpan, 0).fontStyle, FontStyle.italic);
    expect(_styleAt(lightSpan, 0).fontWeight, isNot(FontWeight.bold));
    await _pumpEditor(
      tester,
      service,
      second,
      section: 1,
      brightness: Brightness.dark,
    );
    final darkSpan = _renderedSpan(tester);
    expect(darkSpan.toPlainText(), 'אב');
    expect(_styleAt(darkSpan, 0).fontStyle, FontStyle.italic);
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
