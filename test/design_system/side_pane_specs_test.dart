// טבלת הרוחבים של חלוניות הצד (סעיף 13, החלטת הבעלים א): כל מידה של חלונית
// צד חיה ב-`SidePaneSpecs`, והמסכים לא כותבים מספרי רוחב בעצמם.
//
// זו בדיקת `flutter test` ולא כלל ב-`ui_lint`: הכלל דורש הבנה של שמות
// ארגומנטים בקריאה ל-`AdaptiveSidePane` ול-`NavSidePanel` ושל קבועים מקומיים
// ששמם מצביע על רוחב חלונית, והבדיקה הזו אומרת זאת במפורש בלי לשנות את
// מנוע הכללים ובלי baseline נוסף.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/side_pane_specs.dart';

void main() {
  group('הערכים בטבלה הם אלה שהיו בכל מסך לפני האיחוד', () {
    void expectSpec(
      SidePaneSpec spec, {
      required double minMain,
      double minPane = 220,
      double? maxPane,
      double? maxFraction,
      double? fixed,
      double? defaultFraction,
      double? defaultFractionList,
      double? dragLeaves,
    }) {
      expect(spec.minMainContentWidth, minMain);
      expect(spec.minPaneWidth, minPane);
      expect(spec.maxPaneWidth, maxPane);
      expect(spec.maxPaneFraction, maxFraction);
      expect(spec.fixedPaneWidth, fixed);
      expect(spec.defaultPaneFraction, defaultFraction);
      expect(spec.defaultPaneFractionList, defaultFractionList);
      expect(spec.dragLeavesForMain, dragLeaves);
    }

    test('קוראים', () {
      expectSpec(
        SidePaneSpecs.textReaderNav,
        minMain: 520,
        minPane: 200,
        maxPane: 600,
      );
      expectSpec(
        SidePaneSpecs.pdfReaderNav,
        minMain: 200,
        minPane: 200,
        maxPane: 600,
      );
      expectSpec(
        SidePaneSpecs.pdfReaderCommentary,
        minMain: 200,
        minPane: 250,
        maxPane: 600,
      );
      expectSpec(
        SidePaneSpecs.splitView,
        minMain: 200,
        minPane: 280,
        maxFraction: 0.75,
        dragLeaves: 300,
      );
      expectSpec(
        SidePaneSpecs.pageShapeSidebar,
        minMain: 300,
        minPane: 220,
        maxFraction: 0.35,
        defaultFraction: 0.22,
      );
    });

    test('כרטיסיות המפרשים', () {
      expectSpec(
        SidePaneSpecs.textCommentatorsTabNav,
        minMain: 400,
        fixed: 320,
      );
      expectSpec(SidePaneSpecs.pdfCommentatorsTabNav, minMain: 500, fixed: 320);
    });

    test('חיפוש וספרייה', () {
      expectSpec(
        SidePaneSpecs.searchFacets,
        minMain: 300,
        minPane: 220,
        maxPane: 600,
      );
      expectSpec(
        SidePaneSpecs.searchPreview,
        minMain: 300,
        minPane: 280,
        defaultFraction: 0.4,
        dragLeaves: 320,
      );
      expectSpec(
        SidePaneSpecs.libraryPreview,
        minMain: 200,
        minPane: 280,
        defaultFraction: 0.35,
        defaultFractionList: 0.60,
        dragLeaves: 230,
      );
    });

    test('כלים אישיים', () {
      expectSpec(
        SidePaneSpecs.personalNotes,
        minMain: 320,
        minPane: 150,
        maxPane: 500,
      );
      expectSpec(
        SidePaneSpecs.calendar,
        minMain: 500,
        minPane: 280,
        maxPane: 520,
      );
      expectSpec(
        SidePaneSpecs.measurementConverter,
        minMain: 420,
        minPane: 150,
        maxPane: 280,
      );
      expectSpec(
        SidePaneSpecs.shamorZachor,
        minMain: 320,
        minPane: 220,
        maxPane: 420,
      );
    });
  });

  test('קוד מסך אינו כותב מספרי רוחב של חלונית צד, אלא לוקח אותם מהטבלה', () {
    // הרכיבים שמגדירים את הפרמטרים, והטבלה עצמה.
    const exempt = {
      'lib/widgets/layout/adaptive_side_pane.dart',
      'lib/widgets/layout/side_pane_specs.dart',
      'lib/widgets/navigation/nav_side_panel.dart',
    };
    // ארגומנט בשם, או משתנה/קבוע מקומי ששמו הוא מידת חלונית, שערכו מספר.
    final literalWidth = RegExp(
      r'(?:^|[^\w.])(?:_?k?)?(?:'
      r'minMainContentWidth|[mM]inPaneWidth|maxPaneWidth|'
      r'navMinMainContentWidth|NavMinMainContentWidth|NavPaneWidth'
      r')\s*[:=]\s*-?\d',
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (exempt.contains(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (literalWidth.hasMatch(line)) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'מספרי רוחב של חלונית צד שייכים ל-SidePaneSpecs '
          '(lib/widgets/layout/side_pane_specs.dart)',
    );
  });
}
