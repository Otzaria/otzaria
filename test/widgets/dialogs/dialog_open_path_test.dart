// פתיחת חלונות קופצים (פריט 28, theme-dark-07 / CC-09): כל הפתיחות עוברות
// דרך showDialogUntilTornDown, שאינה לוכדת את ה-Theme של לשונית הקריאה.
// showDialog גולמי בלשונית קריאה משאיר דיאלוג שנפתח, ונשאר פתוח בזמן החלפת
// ערכה, בצבעי הערכה הישנה.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';

void main() {
  test('אין פתיחת דיאלוג גולמית ב-lib: הכול דרך showDialogUntilTornDown', () {
    final raw = RegExp(
      r'(?<![A-Za-z0-9_.])'
      r'(showDialog|showAdaptiveDialog|showGeneralDialog|showCupertinoDialog)'
      r'\s*[<(]',
    );
    final rawFiles = <String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (path.endsWith('lib/widgets/dialogs/dialog_teardown.dart')) continue;
      final opens = file.readAsLinesSync().any(
        (line) => !line.trimLeft().startsWith('//') && raw.hasMatch(line),
      );
      if (opens) rawFiles.add(path);
    }
    expect(
      rawFiles,
      isEmpty,
      reason: 'פתיחה גולמית של דיאלוג: להחליף ב-showDialogUntilTornDown',
    );
  });

  testWidgets('ההחשכה: ברירת מחדל מהערכה, ו-barrierColor מבטל אותה', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    final scrim = AppSurfaces.scrim(Theme.of(context).colorScheme);

    Color? barrier() => tester
        .widgetList<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier))
        .last
        .color
        .value;

    showDialogUntilTornDown<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('a')),
    );
    await tester.pumpAndSettle();
    expect(barrier(), scrim);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    showDialogUntilTornDown<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => const AlertDialog(content: Text('b')),
    );
    await tester.pumpAndSettle();
    // בלי החשכה Flutter בונה ModalBarrier פשוט, ולא מונפש וצבוע.
    expect(find.byType(AnimatedModalBarrier), findsNothing);
    expect(
      tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).last.color,
      isNull,
    );
  });
}
