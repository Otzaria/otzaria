import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import '../../test_helpers/activate_correction_paragraph.dart';

const _patah = 'ַ';
const _holam = 'ֹ';
const _qamats = 'ָ';
const _shinDot = 'ׁ';
const _paseq = '׀';

/// הטקסט שהקורא מציג אחרי הסתרת ניקוד וטעמים.
String _readerText(
  String source, {
  required bool nikud,
  required bool teamim,
}) => utils.removeMarks(source, nikud: nikud, teamim: teamim);

void main() {
  Future<PluginCorrectionSessionService> begin(
    WidgetTester tester,
    String source,
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
        loadSource: (_) async => source,
      ),
    );
    return service;
  }

  Widget paragraph(
    PluginCorrectionSessionService service,
    String source, {
    bool nikud = false,
    bool teamim = false,
  }) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: 400,
            child: PluginCorrectionParagraph(
              tabId: 'tab',
              sectionIndex: 0,
              sourceText: source,
              settings: RenderSettings(
                fontSize: 14,
                removeNikud: nikud,
                removeTeamim: teamim,
              ),
              original: const Text('קריאה'),
              service: service,
              sessionActive: true,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await activateCorrectionParagraph(tester, find.text('קריאה'));
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump(const Duration(seconds: 1));
  }

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

  PluginCorrectionController clean(WidgetTester tester) =>
      tester.widget<RtlTextField>(find.byType(RtlTextField)).controller
          as PluginCorrectionController;

  /// עריכה כפי שהמקלדת שולחת: הבחירה לפני העריכה, ואז הטקסט והסמן החדשים.
  Future<void> edit(
    WidgetTester tester, {
    required int caretBefore,
    required String text,
    required int caretAfter,
  }) async {
    editor(tester).controller.selection = TextSelection.collapsed(
      offset: caretBefore,
    );
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caretAfter),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> undo(WidgetTester tester, {bool redo = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  String canonical(PluginCorrectionSessionService service, String source) =>
      service.editableText('tab', 0, source);

  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  group('ניקוד מוסתר', () {
    testWidgets('הדבקת ניקוד ממפה את הסמן ומאפשרת להמשיך להקליד', (
      tester,
    ) async {
      const source = 'א';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      await edit(tester, caretBefore: 1, text: 'אב$_patah', caretAfter: 3);
      expect(editor(tester).controller.text, 'אב');
      expect(editor(tester).controller.selection.extentOffset, 2);
      await edit(tester, caretBefore: 2, text: 'אבג', caretAfter: 3);
      expect(canonical(service, source), 'אב$_patahג');
      await finish(tester, service);
    });

    testWidgets('החלפת בחירה מסירה גם את הניקוד של אות זהה', (
      tester,
    ) async {
      const source = 'ב$_patahב$_holam';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      editor(tester).controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ב',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(canonical(service, source), 'ב');
      await finish(tester, service);
    });

    testWidgets('הדבקה מתפריט ההקשר שומרת ניקוד וממקמת את הסמן', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? {'text': 'ב$_holam'} : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      const source = 'ב$_patahב$_patah';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      editor(tester).controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      final click = await tester.startGesture(
        tester.getCenter(find.byType(EditableText)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await click.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('הדבק'));
      await tester.pumpAndSettle();
      expect(clean(tester).text, 'ב');
      expect(clean(tester).selection.extentOffset, 1);
      expect(canonical(service, source), 'ב$_holam');
      await finish(tester, service);
    });

    testWidgets('ניקוד בהרכבה נשמר אחרי אישור המקלדת', (tester) async {
      const source = 'א';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      editor(tester).controller.selection = const TextSelection.collapsed(
        offset: 1,
      );
      const composing = TextEditingValue(
        text: 'אב$_patah',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 1, end: 3),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      expect(editor(tester).controller.value, composing);
      tester.testTextInput.updateEditingValue(
        composing.copyWith(composing: TextRange.empty),
      );
      await tester.pump();
      expect(editor(tester).controller.text, 'אב');
      expect(editor(tester).controller.selection.extentOffset, 2);
      expect(canonical(service, source), 'אב$_patah');
      await finish(tester, service);
    });

    testWidgets('שינוי ניקוד בלבד נשמר וניתן לביטול ולביצוע חוזר', (
      tester,
    ) async {
      const source = 'אב';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      await edit(tester, caretBefore: 1, text: 'א\nב', caretAfter: 2);
      await edit(tester, caretBefore: 4, text: 'א\r\nב$_patah', caretAfter: 5);
      expect(editor(tester).controller.text, 'א\r\nב');
      expect(canonical(service, source), 'א\nב$_patah');
      await edit(tester, caretBefore: 4, text: 'א\r\nב$_patah', caretAfter: 5);
      expect(canonical(service, source), 'א\nב$_patah$_patah');
      await undo(tester);
      expect(canonical(service, source), 'א\nב$_patah');
      await undo(tester);
      expect(editor(tester).controller.text, 'א\r\nב');
      expect(canonical(service, source), 'א\nב');
      await undo(tester, redo: true);
      expect(canonical(service, source), 'א\nב$_patah');
      await finish(tester, service);
    }, variant: windows);

    testWidgets('מחיקת האות הראשונה מוחקת את הניקוד שלה ולא של השנייה', (
      tester,
    ) async {
      const source = 'ב$_patahב$_holam';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      expect(clean(tester).text, 'בב');
      await edit(tester, caretBefore: 1, text: 'ב', caretAfter: 0);
      expect(canonical(service, source), 'ב$_holam');
      await finish(tester, service);
    });

    testWidgets('מחיקת האות השנייה משאירה את הניקוד של הראשונה', (
      tester,
    ) async {
      const source = 'ב$_patahב$_holam';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      await edit(tester, caretBefore: 2, text: 'ב', caretAfter: 1);
      expect(canonical(service, source), 'ב$_patah');
      await finish(tester, service);
    });

    testWidgets('הקלדה בין אותיות מנוקדות נכנסת אחרי הניקוד של הקודמת', (
      tester,
    ) async {
      const source = 'ב$_patahב$_holam';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      await edit(tester, caretBefore: 1, text: 'בגב', caretAfter: 2);
      expect(canonical(service, source), 'ב$_patahגב$_holam');
      await finish(tester, service);
    });

    testWidgets('החלפת מילה מוחקת את הניקוד שלה בלבד', (tester) async {
      const source = 'א$_patahב ג$_qamatsד ה$_holam';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      expect(clean(tester).text, 'אב גד ה');
      editor(tester).controller.selection = const TextSelection(
        baseOffset: 3,
        extentOffset: 5,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'אב חש ה',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(canonical(service, source), 'א$_patahב חש ה$_holam');
      await finish(tester, service);
    });

    testWidgets('תיקון בתוך טווח הרכבה לא מוחק ניקוד של אותיות שלא השתנו', (
      tester,
    ) async {
      const source = 'ב$_patahב$_holam';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'בב',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'בבג',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(canonical(service, source), 'ב$_patahב$_holamג');
      await finish(tester, service);
    });

    testWidgets('החלפה בתוך טווח הרכבה משאירה את הניקוד של האותיות שלא השתנו', (
      tester,
    ) async {
      const source = 'ב$_patahב$_holam';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      editor(tester).controller.value = const TextEditingValue(
        text: 'בב',
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange(start: 0, end: 2),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'בגב',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(canonical(service, source), 'ב$_patahגב$_holam');
      await finish(tester, service);
    });

    testWidgets('עיצוב מיושר לטקסט הגלוי', (tester) async {
      const source = '<b>ב$_patah</b>ב$_holam';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      expect(clean(tester).text, 'בב');
      expect(clean(tester).formats.map((f) => f.bold), [true, false]);
      await edit(tester, caretBefore: 1, text: 'בגב', caretAfter: 2);
      expect(clean(tester).formats.map((f) => f.bold), [true, true, false]);
      await finish(tester, service);
    });
  });

  group('ביטול וביצוע חוזר', () {
    testWidgets('ביטול וביצוע חוזר של iOS שומרים ניקוד מוסתר', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.undoManager,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.undoManager,
          null,
        ),
      );
      const source = 'אב';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      await edit(tester, caretBefore: 2, text: 'אב$_patah', caretAfter: 3);
      expect(canonical(service, source), 'אב$_patah');
      UndoManager.client!.handlePlatformUndo(UndoDirection.undo);
      await tester.pump();
      expect(canonical(service, source), source);
      UndoManager.client!.handlePlatformUndo(UndoDirection.redo);
      await tester.pump();
      expect(canonical(service, source), 'אב$_patah');
      await finish(tester, service);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('מחיקה וביטול מחזירים את הניקוד', (tester) async {
      const source = 'ש$_qamats$_shinDotלו$_holamם עו$_holamל$_qamatsם';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      expect(clean(tester).text, 'שלום עולם');
      await edit(tester, caretBefore: 4, text: 'שלם עולם', caretAfter: 3);
      expect(
        canonical(service, source),
        'ש$_qamats$_shinDotלם עו$_holamל$_qamatsם',
      );
      await undo(tester);
      expect(clean(tester).text, 'שלום עולם');
      expect(canonical(service, source), source);
      await undo(tester, redo: true);
      expect(canonical(service, source), contains('לם עו'));
      await finish(tester, service);
    }, variant: windows);

    testWidgets('Enter בין אותיות מנוקדות, מחיקת השנייה וביטול', (
      tester,
    ) async {
      const source = 'ב$_patahב$_holam';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await open(tester);
      await edit(tester, caretBefore: 1, text: 'ב\nב', caretAfter: 2);
      expect(canonical(service, source), 'ב$_patah\nב$_holam');
      await edit(tester, caretBefore: 3, text: 'ב\n', caretAfter: 2);
      expect(canonical(service, source), 'ב$_patah\n');
      await undo(tester);
      expect(clean(tester).text, 'ב\nב');
      expect(canonical(service, source), 'ב$_patah\nב$_holam');
      await undo(tester, redo: true);
      expect(canonical(service, source), 'ב$_patah\n');
      await finish(tester, service);
    }, variant: windows);
  });

  group('הסתרה לפי ההגדרות', () {
    const verse = 'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֣ת־הַשָּׁמַ֔יִם';
    for (final nikud in [false, true]) {
      for (final teamim in [false, true]) {
        testWidgets('טקסט העורך כמו בקורא: ניקוד=$nikud טעמים=$teamim', (
          tester,
        ) async {
          final service = await begin(tester, verse);
          await tester.pumpWidget(
            paragraph(service, verse, nikud: nikud, teamim: teamim),
          );
          await open(tester);
          final shown = _readerText(verse, nikud: nikud, teamim: teamim);
          expect(clean(tester).text, shown);
          expect(clean(tester).formats.length, shown.length);
          // הקלדה וביטולה בלי נגיעה בשאר הטקסט מחזירות את המקור כמות שהוא.
          await edit(
            tester,
            caretBefore: shown.length,
            text: '${shown}X',
            caretAfter: shown.length + 1,
          );
          expect(canonical(service, verse), '${verse}X');
          await edit(
            tester,
            caretBefore: shown.length + 1,
            text: shown,
            caretAfter: shown.length,
          );
          expect(canonical(service, verse), verse);
          await finish(tester, service);
        });
      }
    }

    testWidgets('מקף מוצג כרווח ומחיקתו מוחקת רק אותו', (tester) async {
      const source = 'אֵ֣ת־הַשָּׁמַ֔יִם';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(service, source, nikud: true, teamim: true),
      );
      await open(tester);
      expect(clean(tester).text, 'את השמים');
      await edit(tester, caretBefore: 3, text: 'אתהשמים', caretAfter: 2);
      expect(canonical(service, source), source.replaceFirst('־', ''));
      await finish(tester, service);
    });

    testWidgets('פסק אחרי רווח נעלם בתצוגה ונשמר במקור', (tester) async {
      const source = 'אב $_paseq גד';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, teamim: true));
      await open(tester);
      expect(
        clean(tester).text,
        _readerText(source, nikud: false, teamim: true),
      );
      final shown = clean(tester).text;
      await edit(
        tester,
        caretBefore: shown.length,
        text: '$shownה',
        caretAfter: shown.length + 1,
      );
      expect(canonical(service, source), '$sourceה');
      await finish(tester, service);
    });

    testWidgets('טיוטה שמורה מוצגת בלי ניקוד וניתנת להמשך עריכה', (
      tester,
    ) async {
      const source = 'ב$_patahב$_holamג$_qamats';
      final service = await begin(tester, source);
      service.editParagraph('tab', 0, source, 'ב$_patahב$_holamג');
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await tester.pump();
      expect(clean(tester).text, 'בבג');
      await tester.showKeyboard(find.byType(EditableText));
      await edit(tester, caretBefore: 3, text: 'בבגד', caretAfter: 4);
      expect(canonical(service, source), 'ב$_patahב$_holamגד');
      await finish(tester, service);
    });

    testWidgets('החלפת ההגדרה בזמן עריכה שומרת תיקונים ומחליפה את התצוגה', (
      tester,
    ) async {
      const source = 'ב$_patahב$_holam';
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source));
      await open(tester);
      expect(clean(tester).text, source);
      await edit(
        tester,
        caretBefore: source.length,
        text: '$sourceג',
        caretAfter: source.length + 1,
      );
      await tester.pumpWidget(paragraph(service, source, nikud: true));
      await tester.pump();
      expect(clean(tester).text, 'בבג');
      expect(clean(tester).selection, const TextSelection.collapsed(offset: 3));
      expect(canonical(service, source), '$sourceג');
      await tester.pumpWidget(paragraph(service, source));
      await tester.pump();
      expect(clean(tester).text, '$sourceג');
      expect(canonical(service, source), '$sourceג');
      await finish(tester, service);
    });
  });
}
