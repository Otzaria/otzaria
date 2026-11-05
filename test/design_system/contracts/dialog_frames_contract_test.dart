import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/dialogs/list_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

import 'contract_harness.dart';

Material _dialogSurface(WidgetTester tester) =>
    firstMaterialIn(tester, find.byType(Dialog));

void main() {
  group('דיאלוג רשימה (AppDialogFrame large + ListDialogCounter)', () {
    Widget frame() => AppDialogFrame(
      icon: FluentIcons.book_24_regular,
      title: 'ספרים',
      trailing: const ListDialogCounter('12 ספרים'),
      size: AppDialogSize.large,
      padding: AppTokens.dialogPadding.copyWith(top: 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          SizedBox(key: Key('row'), height: 40, child: Text('שורה')),
        ],
      ),
    );

    testWidgets('דסקטופ: רוחב 720, גובה לפי התוכן', (tester) async {
      await showInApp<void>(tester, frame());
      final size = tester.getSize(find.byWidget(_dialogSurface(tester)));
      expect(size.width, 720);
      expect(size.height, lessThan(200));
    });

    testWidgets('רשימה ארוכה נעצרת ב-85% מגובה החלון', (tester) async {
      await showInApp<void>(
        tester,
        AppDialogFrame(
          icon: FluentIcons.book_24_regular,
          title: 'ספרים',
          size: AppDialogSize.large,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < 100; i++)
                const SizedBox(height: 40, child: Text('שורה')),
            ],
          ),
        ),
      );
      expect(
        tester.getSize(find.byWidget(_dialogSurface(tester))).height,
        800 * 0.85,
      );
    });

    testWidgets('משטח הדיאלוג של התמה, מונה ב-bodyMedium onSurfaceVariant', (
      tester,
    ) async {
      await showInApp<void>(tester, frame());
      final context = tester.element(find.byType(AppDialogFrame));
      final theme = Theme.of(context);
      final surface = _dialogSurface(tester);
      expect(surface.color, theme.colorScheme.surfaceContainerHigh);
      expect(surface.shape, AppTokens.roundedShape);

      final counter = tester.widget<Text>(find.text('12 ספרים'));
      expect(counter.style?.fontSize, theme.textTheme.bodyMedium?.fontSize);
      expect(counter.style?.color, theme.colorScheme.onSurfaceVariant);
      final header = tester.widget<AppDialogHeader>(
        find.byType(AppDialogHeader),
      );
      expect(header.compact, isTrue);
    });

    testWidgets('גוף הרשימה בריפוד 24 מהצדדים ו-16 מלמטה', (tester) async {
      await showInApp<void>(tester, frame());
      final surface = tester.getRect(find.byWidget(_dialogSurface(tester)));
      final row = tester.getRect(find.byKey(const Key('row')));
      expect(row.right, surface.right - 24);
      expect(surface.bottom - row.bottom, 16);
    });
  });
}
