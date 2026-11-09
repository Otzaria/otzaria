import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';

/// סרגל העיצוב בעורך ההערות בשורה אחת: 10 כלים ו"עוד" ברוחב הדיאלוג, כל
/// 12 בצפיפות קומפקטית, ובחלונית צרה עוד כלים עוברים לתפריט (q12 Q6).
const _all = [
  'מודגש',
  'נטוי',
  'קו תחתי',
  'קו חוצה',
  'הדגשה',
  'הגדל כתב',
  'הקטן כתב',
  'כותרת',
  'רשימה',
  'רשימה ממוספרת',
  'ציטוט',
  'הוסף קישור',
];
const _more = 'עוד פעולות';

/// כפתורי הכלים בסרגל, בלי כפתור "עוד" (שגם הוא BarButton).
Finder _toolbarButtons() => find.byWidgetPredicate(
  (w) => w is BarButton && w.tooltip != _more,
);

/// הכלים הגלויים בסדר הקריאה: מימין לשמאל.
List<String> _visibleTools(WidgetTester tester) {
  final buttons = _toolbarButtons().evaluate().toList()
    ..sort(
      (a, b) => tester
          .getCenter(find.byWidget(b.widget))
          .dx
          .compareTo(tester.getCenter(find.byWidget(a.widget)).dx),
    );
  return [for (final e in buttons) (e.widget as BarButton).tooltip];
}

void _expectOneRow(WidgetTester tester) {
  final rows = _toolbarButtons().evaluate().map(
    (e) => tester.getRect(find.byWidget(e.widget)).center.dy,
  );
  expect(rows.toSet().length, 1, reason: 'כל הכלים באותה שורה');
  expect(
    tester.getCenter(find.byTooltip(_more).hitTestable()).dy,
    closeTo(rows.first, 0.5),
  );
}

Future<void> _pumpDialog(WidgetTester tester, {bool compact = false}) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = ThemeData(
    extensions: [compact ? AppDensity.compact : AppDensity.regular],
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const PersonalNoteEditorDialog(
                initialContent: 'שלום',
                title: 'עריכת הערה',
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

Future<PersonalNoteEditorController> _pumpBody(
  WidgetTester tester, {
  required double width,
  FocusNode? focusNode,
}) async {
  final controller = buildPersonalNoteEditorController(
    initialContent: 'שלום',
    initialFormat: PersonalNoteContentFormat.plain,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: PersonalNoteEditorBody(
                controller: controller,
                focusNode: focusNode ?? FocusNode(),
                scrollController: ScrollController(),
                autofocus: focusNode != null,
                linkableNotes: const [],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void _selectAll(PersonalNoteEditorController c) =>
    c.quillController.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 4),
      quill.ChangeSource.local,
    );

Object? _attr(PersonalNoteEditorController c, String key) {
  for (final op in c.quillController.document.toDelta().toList()) {
    final value = op.attributes?[key];
    if (value != null) return value;
  }
  return null;
}

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => '/tmp');
  });

  testWidgets('בדיאלוג (560): שורה אחת, 10 כלים ו"עוד" עם ציטוט וכותרת', (
    tester,
  ) async {
    await _pumpDialog(tester);

    expect(_visibleTools(tester), [
      for (final t in _all)
        if (t != 'ציטוט' && t != 'כותרת') t,
    ]);
    _expectOneRow(tester);
    // RTL: הכלי הראשון בימין, "עוד" בקצה השמאלי.
    final bold = tester.getCenter(find.byTooltip('מודגש'));
    final link = tester.getCenter(find.byTooltip('הוסף קישור'));
    final more = tester.getCenter(find.byTooltip(_more).hitTestable());
    expect(bold.dx, greaterThan(link.dx));
    expect(link.dx, greaterThan(more.dx));

    await tester.tap(find.byTooltip(_more).hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('כותרת'), findsOneWidget);
    expect(find.text('ציטוט'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('כותרת')).dy,
      lessThan(tester.getTopLeft(find.text('ציטוט')).dy),
      reason: 'התפריט שומר על סדר הסרגל',
    );
  });

  testWidgets('בדיאלוג בצפיפות קומפקטית: כל 12 הכלים, בלי "עוד"', (
    tester,
  ) async {
    await _pumpDialog(tester, compact: true);

    expect(_visibleTools(tester), _all);
    expect(find.byTooltip(_more), findsNothing);
    final rows = _toolbarButtons().evaluate().map(
      (e) => tester.getRect(find.byWidget(e.widget)).center.dy,
    );
    expect(rows.toSet().length, 1);
  });

  testWidgets('ברוחב צר עוד כלים עוברים ל"עוד", מהנדיר לנפוץ', (tester) async {
    await _pumpBody(tester, width: 300);

    final visible = _visibleTools(tester);
    expect(visible, [
      'מודגש',
      'קו תחתי',
      'הדגשה',
      'רשימה',
      'הוסף קישור',
    ]);
    _expectOneRow(tester);

    await tester.tap(find.byTooltip(_more).hitTestable());
    await tester.pumpAndSettle();
    for (final t in _all.where((t) => !visible.contains(t))) {
      expect(find.text(t), findsOneWidget, reason: '$t בתפריט');
    }
  });

  testWidgets('לכל כלי יש tooltip', (tester) async {
    await _pumpBody(tester, width: 800);
    for (final t in _all) {
      expect(find.byTooltip(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('כל כלי בסרגל מחיל את העיצוב שלו', (tester) async {
    final c = await _pumpBody(tester, width: 800);
    final cases = <(String, String, Object)>[
      ('מודגש', 'bold', true),
      ('נטוי', 'italic', true),
      ('קו תחתי', 'underline', true),
      ('קו חוצה', 'strike', true),
      ('הדגשה', 'background', '#fff59d'),
      ('כותרת', 'header', 2),
      ('רשימה', 'list', 'bullet'),
      ('רשימה ממוספרת', 'list', 'ordered'),
      ('ציטוט', 'blockquote', true),
    ];
    for (final (tooltip, key, value) in cases) {
      _selectAll(c);
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
      expect(_attr(c, key), value, reason: tooltip);
    }
    _selectAll(c);
    await tester.tap(find.byTooltip('הגדל כתב'));
    await tester.pump();
    expect(_attr(c, 'size'), 18.0);
    _selectAll(c);
    await tester.tap(find.byTooltip('הקטן כתב'));
    await tester.pump();
    expect(_attr(c, 'size'), 16.0);
  });

  testWidgets('כלים מתפריט "עוד" מחילים את העיצוב ומחזירים פוקוס לעורך', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final c = await _pumpBody(tester, width: 300, focusNode: focus);
    expect(focus.hasFocus, isTrue);

    final cases = <(String, String, Object)>[
      ('ציטוט', 'blockquote', true),
      ('כותרת', 'header', 2),
      ('קו חוצה', 'strike', true),
      ('נטוי', 'italic', true),
    ];
    for (final (tooltip, key, value) in cases) {
      _selectAll(c);
      await tester.tap(find.byTooltip(_more).hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text(tooltip));
      await tester.pumpAndSettle();
      expect(_attr(c, key), value, reason: tooltip);
      expect(focus.hasFocus, isTrue, reason: 'אחרי $tooltip הסמן בעורך');
    }

    _selectAll(c);
    await tester.tap(find.byTooltip(_more).hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('הגדל כתב'));
    await tester.pumpAndSettle();
    expect(_attr(c, 'size'), 18.0);
  });
}
