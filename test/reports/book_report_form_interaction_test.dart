import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/reports/bloc/book_report_draft_cubit.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

import '../test_helpers/memory_cache_provider.dart';

class _RecordingDraftStore extends ReportDraftStore {
  int writes = 0;

  @override
  Future<int> write({
    required String id,
    required String kind,
    required String title,
    required Map<String, dynamic> payload,
    required int revision,
    Map<String, dynamic>? attachments,
  }) async {
    writes++;
    return revision + 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('focus and caret changes do not autosave a book report', (
    tester,
  ) async {
    const initialForm = <String, dynamic>{
      'mode': 'freeText',
      'details': '',
      'proposedText': '',
      'proposalMode': 'replace',
      'selectionStart': 0,
      'selectionEnd': 4,
    };
    final store = _RecordingDraftStore();
    final draft = BookReportDraftCubit(
      target: {'bookTitle': 'ספר לדוגמה'},
      initialForm: initialForm,
      store: store,
    );
    try {
      final changes = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsTextScope(
            language: SettingsLanguage.hebrew,
            child: Scaffold(
              body: RegularReportTab(
                selectedText: 'קטע.',
                fontSize: 18,
                directReportTargetLabel: 'אוצריא',
                initialForm: initialForm,
                onDraftChanged: (form) {
                  changes.add(form);
                  draft.updateForm(form);
                },
                onActionSelected: (_, _) {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final details = find.descendant(
        of: find.byKey(const ValueKey('report-details-field')),
        matching: find.byType(TextField),
      );
      final field = tester.widget<TextField>(details);
      field.controller!.selection = const TextSelection.collapsed(offset: -1);
      field.focusNode!.requestFocus();
      await tester.pump();
      field.controller!.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump(const Duration(milliseconds: 700));

      expect(changes, isEmpty);
      expect(draft.hasContent, isFalse);
      expect(store.writes, 0);
      await draft.flush();
      expect(store.writes, 0);

      await tester.enterText(details, 'פירוט חדש');
      await tester.pump(const Duration(milliseconds: 700));
      expect(changes, hasLength(1));
      expect(changes.single['proposedText'], '');
      expect(store.writes, 1);
      field.controller!.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      field.controller!.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump(const Duration(milliseconds: 700));
      expect(changes, hasLength(1));
      expect(store.writes, 1);
    } finally {
      // Session futures were created in this fake-clock zone. Close the Cubit
      // while the zone still pumps microtasks, rather than in addTearDown.
      await tester.pumpWidget(const SizedBox.shrink());
      await draft.close();
      expect(draft.isClosed, isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  for (final (source, word, direction, reverse) in const [
    ('😀 first repeat second repeat last', 'repeat', TextDirection.ltr, true),
    ('אחד מילה שני מילה שלישי', 'מילה', TextDirection.rtl, false),
  ]) {
    testWidgets('quote selection keeps the repeated occurrence in $direction', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
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
      final changes = <Map<String, dynamic>>[];
      final submissions = <ReportedErrorData>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: SettingsTextScope(
            language: SettingsLanguage.english,
            child: Scaffold(
              body: RegularReportTab(
                selectedText: word,
                selectionSource: source,
                fontSize: 18,
                directReportTargetLabel: 'אוצריא',
                onDraftChanged: changes.add,
                onActionSelected: (_, data) => submissions.add(data),
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final quote = find.byKey(const ValueKey('report-location-quote'));
      final quoteBounds = tester.getRect(quote);
      final clear = find.widgetWithText(TextButton, 'Clear selection');
      expect(tester.widget<TextButton>(clear).onPressed, isNull);
      expect(
        find.ancestor(of: quote, matching: find.byType(AppSelectionArea)),
        findsOneWidget,
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: quote, matching: find.byType(RichText)),
      );
      expect(paragraph.text.toPlainText(), source);
      expect(paragraph.textDirection, direction);
      final start = source.lastIndexOf(word);
      final end = start + word.length;
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end),
          )
          .single;
      final left = paragraph.localToGlobal(
        Offset(box.left + 1, (box.top + box.bottom) / 2),
      );
      final right = paragraph.localToGlobal(
        Offset(box.right - 1, (box.top + box.bottom) / 2),
      );
      final forwardStart = direction == TextDirection.rtl ? right : left;
      final forwardEnd = direction == TextDirection.rtl ? left : right;
      final gesture = await tester.startGesture(
        reverse ? forwardEnd : forwardStart,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(reverse ? forwardStart : forwardEnd);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(changes.last['selectionStart'], start);
      expect(changes.last['selectionEnd'], end);
      expect(tester.getRect(quote), quoteBounds);
      expect(
        paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: end),
            )
            .single
            .toRect(),
        box.toRect(),
        reason:
            'Marking the location must not move or resize the selected text.',
      );
      expect(tester.widget<TextButton>(clear).onPressed, isNotNull);

      final copyGesture = await tester.startGesture(
        Offset.lerp(left, right, 0.5)!,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pump();
      await copyGesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, word);
      expect(tester.takeException(), isNull);

      final details = find.descendant(
        of: find.byKey(const ValueKey('report-details-field')),
        matching: find.byType(TextField),
      );
      await tester.enterText(
        details,
        'The second occurrence needs correction.',
      );
      await tester.pump();
      await tester.tap(find.text('Save for later sending'));
      await tester.pump();
      final submitted = submissions.single;
      expect(submitted.selectedText, word);
      expect(submitted.selection!.start, start);
      expect(submitted.selection!.end, end);
      expect(submitted.selectionContext, contains('$start–$end'));
      expect(submitted.selectionContext, contains(source));

      final nextStart = source.indexOf(word);
      final nextEnd = nextStart + word.length;
      final nextBox = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: nextStart, extentOffset: nextEnd),
          )
          .single;
      final nextLeft = paragraph.localToGlobal(
        Offset(nextBox.left + 1, (nextBox.top + nextBox.bottom) / 2),
      );
      final nextRight = paragraph.localToGlobal(
        Offset(nextBox.right - 1, (nextBox.top + nextBox.bottom) / 2),
      );
      final nextGesture = await tester.startGesture(
        direction == TextDirection.rtl ? nextRight : nextLeft,
        kind: PointerDeviceKind.mouse,
      );
      await nextGesture.moveTo(
        direction == TextDirection.rtl ? nextLeft : nextRight,
      );
      await nextGesture.up();
      // Submit before a rebuild: the action must collect the latest location,
      // rather than the report data captured by the previous build.
      if (direction == TextDirection.ltr) {
        await tester.tap(find.text('Save for later sending'));
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.text('Confirm report'), findsOneWidget);
        await tester.tap(find.text('Send report'));
      }
      await tester.pumpAndSettle();
      expect(submissions, hasLength(2));
      expect(submissions.last.selectedText, word);
      expect(submissions.last.selection!.start, nextStart);
      expect(submissions.last.selection!.end, nextEnd);
      expect(
        submissions.last.selectionContext,
        contains('$nextStart–$nextEnd'),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      expect(changes.last['selectionStart'], isNull);
      expect(changes.last['selectionEnd'], isNull);
      expect(tester.widget<TextButton>(clear).onPressed, isNull);
      expect(tester.getRect(quote), quoteBounds);
      expect(paragraph.text.toPlainText(), source);
      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(minutes: 1)));
  }
}
