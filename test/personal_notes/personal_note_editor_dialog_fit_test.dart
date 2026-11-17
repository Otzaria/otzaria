import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

/// issue #5048: בחלון נמוך "שמור" ואזור הכתיבה גלויים בלי לגלול את הדיאלוג.
/// אזור הכתיבה מתכווץ לגובה שנשאר, ובחלון גבוה נשאר בגובהו המלא (220).

final _longReference = List.filled(
  40,
  'וַיֹּאמֶר אֱלֹהִים יְהִי אוֹר וַיְהִי אוֹר, וַיַּרְא אֱלֹהִים אֶת הָאוֹר כִּי טוֹב.',
).join(' ');

Future<void> _openDialog(WidgetTester tester, Size window) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => PersonalNoteEditorDialog(
                initialContent: 'שלום',
                title: 'עריכת הערה',
                referenceText: _longReference,
              ),
            ),
            child: const Text('פתח'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

Rect _saveButtonRect(WidgetTester tester) => tester.getRect(
  find.ancestor(of: find.text('שמור'), matching: find.byType(ActionButton)),
);

/// ה-SizedBox של אזור הכתיבה (זה שעוטף את תופס הגרירה). הגובה בפועל — מה-RenderBox.
final _editorBox = find.ancestor(
  of: find.byType(quill.QuillEditor),
  matching: find.byWidgetPredicate(
    (w) => w is SizedBox && w.child is RawGestureDetector,
  ),
);

/// היקף הגלילה של כל Scrollable שעוטף את העורך — כלומר גלילה של הדיאלוג
/// עצמו, לא הגלילה הפנימית של Quill או של טקסט ההקשר.
List<double> _outerScrollExtents(WidgetTester tester) => [
  for (final state in tester.stateList<ScrollableState>(
    find.ancestor(
      of: find.byType(quill.QuillEditor),
      matching: find.byType(Scrollable),
    ),
  ))
    state.position.maxScrollExtent,
];

void _expectInside(Rect inner, Rect outer, String what) {
  expect(inner.top, greaterThanOrEqualTo(outer.top - 0.5), reason: what);
  expect(inner.left, greaterThanOrEqualTo(outer.left - 0.5), reason: what);
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + 0.5), reason: what);
  expect(inner.right, lessThanOrEqualTo(outer.right + 0.5), reason: what);
}

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => '/tmp');
  });

  for (final window in const [Size(800, 420), Size(800, 320)]) {
    testWidgets(
      'חלון נמוך ${window.width.toInt()}x${window.height.toInt()}: '
      '"שמור" ואזור הכתיבה גלויים בלי גלילה',
      (tester) async {
        await _openDialog(tester, window);

        expect(tester.takeException(), isNull, reason: 'אין overflow');
        expect(find.byType(PersonalNoteEditorDialog), findsOneWidget);

        final screen = Offset.zero & window;
        final save = _saveButtonRect(tester);
        _expectInside(save, screen, '"שמור" כולו בתוך החלון');
        expect(
          find.text('שמור').hitTestable(),
          findsOneWidget,
          reason: '"שמור" לחיץ בלי לגלול',
        );

        // הדיאלוג עצמו לא גולל: טקסט ההקשר, סרגל הכלים ואזור הכתיבה כולם
        // בתצוגה (לפני #5048 חלקם נדחקו אל מחוץ לגלילה החיצונית).
        expect(
          _outerScrollExtents(tester),
          everyElement(lessThanOrEqualTo(0.5)),
          reason: 'אין גלילה חיצונית בדיאלוג',
        );

        // אזור הכתיבה מתחת לרצועת השמירה, ונשאר שמיש (כמה שורות).
        final editor = tester.getRect(_editorBox);
        expect(editor.height, greaterThanOrEqualTo(40));
        expect(editor.height, lessThanOrEqualTo(220.5));
        expect(
          editor.top,
          greaterThanOrEqualTo(save.bottom),
          reason: 'בחלון נמוך "שמור" בכותרת ואזור הכתיבה גלוי מתחתיו',
        );
        _expectInside(editor, screen, 'אזור הכתיבה בתוך החלון');
      },
    );
  }

  testWidgets('חלון גבוה 800x1000: אזור הכתיבה בגובה המלא (220)', (
    tester,
  ) async {
    const window = Size(800, 1000);
    await _openDialog(tester, window);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(_editorBox).height, closeTo(220, 0.5));
    _expectInside(_saveButtonRect(tester), Offset.zero & window, '"שמור"');
  });
}
