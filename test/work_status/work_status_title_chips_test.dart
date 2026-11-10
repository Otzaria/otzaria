import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library_update/library_update_work_status.dart';
import 'package:otzaria/widgets/controls/status_chip.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:otzaria/work_status/work_status_overlay.dart';
import 'package:otzaria/work_status/work_status_title_chips.dart';

const _collapseAfter = Duration(seconds: 6);

WorkStatusItem _running({double progress = 0.42, bool collapsible = true}) =>
    WorkStatusItem(
      id: kLibraryUpdateWorkStatusId,
      title: 'עדכון ספרייה',
      message: 'מוריד עדכון ספרייה',
      progress: progress,
      chipLabel: collapsible ? 'ספרייה' : null,
      collapseAfter: collapsible ? _collapseAfter : null,
    );

WorkStatusItem _of(WorkStatusKind kind) => WorkStatusItem(
  id: kLibraryUpdateWorkStatusId,
  title: 'עדכון ספרייה',
  message: 'מצב',
  detail: 'בחר כיצד לעדכן',
  kind: kind,
  chipLabel: 'ספרייה',
);

const _indexing = WorkStatusItem(
  id: 'indexing',
  title: 'אינדוקס ספרים',
  message: 'התוכנה בתהליך אינדוקס',
  progress: 0.25,
);

/// pump כפול: ה-BlocBuilder מקבל את ה-state בהמשך ה-microtask.
Future<void> _tick(WidgetTester tester, [Duration? elapsed]) async {
  await tester.pump(elapsed);
  await tester.pump();
}

/// שורת כותרת (גלולות) וכרטיס זה לצד זה, כמו במסך הראשי. הבדיקה מסתיימת
/// בסגירת ה-cubit, כדי שלא יישאר טיימר פתוח.
void _test(
  String name,
  Future<void> Function(WidgetTester tester, WorkStatusCubit cubit) body, {
  bool showCollapsed = false,
  double width = 900,
}) {
  testWidgets(name, (tester) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = WorkStatusCubit();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: Stack(
              children: [
                const Align(
                  alignment: Alignment.topLeft,
                  child: WorkStatusTitleChips(),
                ),
                WorkStatusOverlay(showCollapsed: showCollapsed),
              ],
            ),
          ),
        ),
      ),
    );
    await body(tester, cubit);
    await cubit.close();
  });
}

Finder get _card => find.text('עדכון ספרייה');
Finder get _chip => find.byType(StatusChip);

void main() {
  _test('מופיע ככרטיס, בלי גלולה', (tester, cubit) async {
    cubit.upsert(_running());
    await _tick(tester);

    expect(_card, findsOneWidget);
    expect(_chip, findsNothing);
  });

  _test('אחרי הזמן הכרטיס מצטמצם לגלולה עם אחוזים', (tester, cubit) async {
    cubit.upsert(_running());
    await _tick(tester, _collapseAfter - const Duration(seconds: 1));
    expect(_card, findsOneWidget);

    await _tick(tester, const Duration(seconds: 1));
    expect(_card, findsNothing);
    expect(_chip, findsOneWidget);
    expect(find.text('ספרייה 42%'), findsOneWidget);
  });

  _test('עדכוני התקדמות לא מאפסים את הספירה', (tester, cubit) async {
    cubit.upsert(_running());
    await _tick(tester, const Duration(seconds: 5));
    cubit.upsert(_running(progress: 0.6));
    await _tick(tester, const Duration(seconds: 1));

    expect(_card, findsNothing);
    expect(find.text('ספרייה 60%'), findsOneWidget);
  });

  _test('לחיצה על הגלולה פותחת את הכרטיס והוא לא מצטמצם שוב', (
    tester,
    cubit,
  ) async {
    cubit.upsert(_running());
    await _tick(tester, _collapseAfter);
    await tester.tap(_chip);
    await _tick(tester);

    expect(_card, findsOneWidget);
    expect(_chip, findsNothing);

    await _tick(tester, _collapseAfter * 3);
    expect(_card, findsOneWidget);
  });

  _test('כפתור הסגירה מצמצם לגלולה במקום להעלים', (tester, cubit) async {
    cubit.upsert(_running());
    await _tick(tester);
    await tester.tap(find.byTooltip('כווץ לשורת הכותרת'));
    await _tick(tester);

    expect(_card, findsNothing);
    expect(_chip, findsOneWidget);

    await tester.tap(_chip);
    await _tick(tester);
    expect(_card, findsOneWidget);
  });

  for (final kind in [WorkStatusKind.awaitingInput, WorkStatusKind.failed]) {
    final chipText = kind == WorkStatusKind.failed
        ? 'ספרייה · נכשל'
        : 'ספרייה · ממתין';

    _test('$kind נשאר כרטיס פתוח ולא מצטמצם מעצמו', (tester, cubit) async {
      cubit.upsert(_of(kind));
      await _tick(tester, _collapseAfter * 10);

      expect(_card, findsOneWidget);
      expect(_chip, findsNothing);
    });

    _test('$kind אחרי סגירה ידנית: גלולה, ולחיצה פותחת', (tester, cubit) async {
      cubit.upsert(_of(kind));
      await _tick(tester);
      await tester.tap(find.byTooltip('כווץ לשורת הכותרת'));
      await _tick(tester);

      expect(_card, findsNothing);
      expect(find.text(chipText), findsOneWidget);
      await tester.tap(_chip);
      await _tick(tester);
      expect(_card, findsOneWidget);
    });

    _test('$kind אחרי שהכרטיס כבר מצומצם פותח אותו מחדש', (
      tester,
      cubit,
    ) async {
      cubit.upsert(_running());
      await _tick(tester, _collapseAfter);
      expect(_card, findsNothing);

      cubit.upsert(_of(kind));
      await _tick(tester);

      expect(_card, findsOneWidget);
      expect(_chip, findsNothing);
    });
  }

  _test('אחרי בחירה בהמתנה להחלטה הספירה מתחילה מחדש', (tester, cubit) async {
    cubit.upsert(_of(WorkStatusKind.awaitingInput));
    await _tick(tester, _collapseAfter * 2);
    cubit.upsert(_running());
    await _tick(tester, _collapseAfter - const Duration(seconds: 1));
    expect(_card, findsOneWidget);

    await _tick(tester, const Duration(seconds: 1));
    expect(_card, findsNothing);
    expect(_chip, findsOneWidget);
  });

  _test('פריט בלי chipLabel אינו מצטמצם וכפתור הסגירה מסתיר כמו קודם', (
    tester,
    cubit,
  ) async {
    cubit.upsert(_running(collapsible: false));
    await _tick(tester, _collapseAfter * 3);
    expect(_card, findsOneWidget);

    await tester.tap(find.byTooltip('סגור'));
    await _tick(tester);
    expect(_card, findsNothing);
    expect(_chip, findsNothing);
  });

  _test('עבודה נוספת נשארת בכרטיס כשהספרייה מצטמצמת', (tester, cubit) async {
    cubit
      ..upsert(_indexing)
      ..upsert(_running());
    await _tick(tester, _collapseAfter);

    expect(find.text('אינדוקס ספרים'), findsOneWidget);
    expect(_card, findsNothing);
    expect(find.text('ספרייה 42%'), findsOneWidget);
  });

  _test('סיום העבודה מסיר גם את הגלולה', (tester, cubit) async {
    cubit.upsert(_running());
    await _tick(tester, _collapseAfter);
    cubit.remove(kLibraryUpdateWorkStatusId);
    await _tick(tester);
    expect(_chip, findsNothing);

    cubit.upsert(_running());
    await _tick(tester);
    expect(_card, findsOneWidget);
  });

  _test(
    'בלי שורת כותרת (showCollapsed) הפריט המצומצם נשאר בכרטיס',
    (tester, cubit) async {
      cubit.upsert(_running());
      await _tick(tester, _collapseAfter);

      expect(_card, findsOneWidget);
    },
    showCollapsed: true,
  );

  // כמו ב-MainWindowScreen: בחלון צר הכרטיס מציג גם פריט מצומצם.
  _test(
    'חלון צר: אין גלולה בשורת הכותרת והפריט נשאר בכרטיס',
    (tester, cubit) async {
      cubit.upsert(_running());
      await _tick(tester, _collapseAfter);

      expect(_chip, findsNothing);
      expect(_card, findsOneWidget);
    },
    showCollapsed: true,
    width: 360,
  );
}
