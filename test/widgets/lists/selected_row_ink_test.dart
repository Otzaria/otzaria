import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

import '../../design_system/contracts/contract_harness.dart';

/// InkWell מצייר ריחוף ולחיצה על שכבת ה-ink של ה-Material הקרוב, מתחת לילדי
/// ה-Material. רקע "נבחר" אטום שמצויר בתוך ה-InkWell מסתיר אותם; הרקע צריך
/// להיות של ה-Material עצמו.
void main() {
  Finder rowInkWell(Finder row) =>
      find.descendant(of: row, matching: find.byType(InkWell)).first;

  Future<void> hover(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
  }

  /// ה-Material שה-InkWell מצייר עליו הוא בצבע [selected], ושום דבר
  /// בתוך ה-InkWell לא צובע אותו צבע מעל הריחוף. אחרי ריחוף, שכבת ה-ink של
  /// אותו Material מציירת את צבע הריחוף.
  Future<void> expectInkOverSelected(
    WidgetTester tester,
    Finder row, {
    required Color hoverColor,
  }) async {
    final inkWell = rowInkWell(row);
    final cs = Theme.of(tester.element(inkWell)).colorScheme;
    final selected = AppSurfaces.selectedRow(cs);

    final material = tester.widget<Material>(
      find.ancestor(of: inkWell, matching: find.byType(Material)).first,
    );
    expect(material.color, selected, reason: 'הרקע צריך להיות של ה-Material');

    final cover = find.descendant(
      of: inkWell,
      matching: find.byWidgetPredicate(
        (w) =>
            (w is ColoredBox && w.color == selected) ||
            (w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color == selected),
      ),
    );
    // קופסת אייקון קטנה באותו צבע אינה מסתירה את השורה; רקע ברוחב השורה כן.
    final rowWidth = tester.getSize(inkWell).width;
    expect(
      cover.evaluate().where(
        (e) => tester.getSize(find.byWidget(e.widget)).width >= rowWidth - 1,
      ),
      isEmpty,
      reason: 'רקע אטום בתוך ה-InkWell מסתיר את ה-ink',
    );

    await hover(tester, inkWell);
    final ink = Material.of(tester.element(inkWell)) as RenderObject;
    expect(
      ink,
      paints..something((method, args) {
        if (method != #drawRect && method != #drawRRect) return false;
        final paint = args.last as Paint;
        return paint.color.a > 0 &&
            (paint.color.toARGB32() & 0xFFFFFF) ==
                (hoverColor.toARGB32() & 0xFFFFFF);
      }),
      reason: 'צבע הריחוף מצויר על ה-Material של השורה',
    );
  }

  for (final brightness in Brightness.values) {
    group('$brightness', () {
      testWidgets('NavTreeTile נבחר: הריחוף נראה מעל רקע הבחירה', (
        tester,
      ) async {
        await pumpInApp(
          tester,
          NavTreeGroupCard(
            isGroupStart: true,
            isGroupEnd: true,
            child: NavTreeTile.book(
              title: 'שולחן ערוך',
              level: 0,
              isSelected: true,
              onTap: () {},
            ),
          ),
          brightness: brightness,
        );
        final cs = Theme.of(
          tester.element(find.byType(NavTreeTile)),
        ).colorScheme;
        await expectInkOverSelected(
          tester,
          find.byType(NavTreeTile),
          hoverColor: AppSurfaces.hoverRow(cs),
        );
      });

      testWidgets('NavTreeContentRow נבחר: הריחוף נראה מעל רקע הבחירה', (
        tester,
      ) async {
        await pumpInApp(
          tester,
          NavTreeContentRow(
            isSelected: true,
            onTap: () {},
            child: const Text('סימן א'),
          ),
          brightness: brightness,
        );
        final cs = Theme.of(
          tester.element(find.byType(NavTreeContentRow)),
        ).colorScheme;
        await expectInkOverSelected(
          tester,
          find.byType(NavTreeContentRow),
          hoverColor: AppSurfaces.hoverRow(cs),
        );
      });

      testWidgets('AppCard נבחר ולחיץ: הריחוף נראה מעל רקע הבחירה', (
        tester,
      ) async {
        await pumpInApp(
          tester,
          AppCard(
            selected: true,
            onTap: () {},
            child: const SizedBox(width: 200, height: 60),
          ),
          brightness: brightness,
        );
        final theme = Theme.of(tester.element(find.byType(AppCard)));
        // InkWell בלי hoverColor: צבע הריחוף של ערכת הנושא.
        await expectInkOverSelected(
          tester,
          find.byType(AppCard),
          hoverColor: theme.hoverColor,
        );
      });
    });
  }

  testWidgets('NavTreeContentRow שומר על סגנון הטקסט שהוא יורש', (
    tester,
  ) async {
    await pumpInApp(
      tester,
      DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w300),
        child: NavTreeContentRow(
          isSelected: true,
          onTap: () {},
          child: const Text('סימן א'),
        ),
      ),
    );
    final style = DefaultTextStyle.of(
      tester.element(find.text('סימן א')),
    ).style;
    expect(style.fontSize, 21);
    expect(style.fontWeight, FontWeight.w300);
  });
}
