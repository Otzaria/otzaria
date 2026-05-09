import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// הטריגר של AppDropdownField אמור להיות תמיד AppSelectionField (לא DropdownMenu),
/// בין אם enableSearch=false ובין אם true. enableSearch משפיע רק על תוכן ה-popup.
void main() {
  Future<void> pumpDropdown<T>(
    WidgetTester tester, {
    required List<AppMenuEntry<T>> entries,
    required T? value,
    required ValueChanged<T?>? onSelected,
    bool enableSearch = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: AppDropdownField<T>(
                value: value,
                entries: entries,
                onSelected: onSelected,
                enableSearch: enableSearch,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('AppDropdownField - טריגר אחיד', () {
    testWidgets('משתמש ב-AppSelectionField גם כש-enableSearch=false',
        (tester) async {
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
          AppMenuEntry<String>(value: 'b', label: 'בית'),
        ],
        onSelected: (_) {},
        enableSearch: false,
      );

      expect(find.byType(AppSelectionField), findsOneWidget);
      expect(find.byType(DropdownMenu<String>), findsNothing,
          reason: 'הטריגר לא צריך להיות DropdownMenu של Material 3');
    });

    testWidgets('משתמש ב-AppSelectionField גם כש-enableSearch=true',
        (tester) async {
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
          AppMenuEntry<String>(value: 'b', label: 'בית'),
        ],
        onSelected: (_) {},
        enableSearch: true,
      );

      expect(find.byType(AppSelectionField), findsOneWidget);
      expect(find.byType(DropdownMenu<String>), findsNothing,
          reason: 'גם עם enableSearch הטריגר נשאר נקי כ-AppSelectionField');
    });
  });

  group('AppDropdownField - תווית הערך הנבחר', () {
    testWidgets('מציג את label של ה-entry הנבחר', (tester) async {
      await pumpDropdown<String>(
        tester,
        value: 'b',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
          AppMenuEntry<String>(value: 'b', label: 'בית'),
        ],
        onSelected: (_) {},
      );

      expect(find.text('בית'), findsOneWidget);
    });

    testWidgets('כש-value הוא null מציג טקסט ריק', (tester) async {
      await pumpDropdown<String>(
        tester,
        value: null,
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
        ],
        onSelected: (_) {},
      );

      expect(find.byType(AppSelectionField), findsOneWidget);
      expect(find.text('אבא'), findsNothing);
    });
  });

  group('AppDropdownField - פתיחת תפריט', () {
    testWidgets('לחיצה פותחת תפריט עם הפריטים', (tester) async {
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
          AppMenuEntry<String>(value: 'b', label: 'בית'),
          AppMenuEntry<String>(value: 'c', label: 'גמל'),
        ],
        onSelected: (_) {},
      );

      await tester.tap(find.byType(AppSelectionField));
      await tester.pumpAndSettle();

      // הפריטים מופיעים בתפריט (ב-PopupMenu של Flutter)
      expect(find.text('בית'), findsOneWidget);
      expect(find.text('גמל'), findsOneWidget);
    });

    testWidgets('בחירת פריט קוראת ל-onSelected עם הערך', (tester) async {
      String? selected;
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
          AppMenuEntry<String>(value: 'b', label: 'בית'),
        ],
        onSelected: (v) => selected = v,
      );

      await tester.tap(find.byType(AppSelectionField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('בית').last);
      await tester.pumpAndSettle();

      expect(selected, 'b');
    });
  });

  group('AppDropdownField - מצב מושבת', () {
    testWidgets('רשימה ריקה לא פותחת תפריט', (tester) async {
      bool selected = false;
      await pumpDropdown<String>(
        tester,
        value: null,
        entries: const [],
        onSelected: (_) => selected = true,
      );

      await tester.tap(find.byType(AppSelectionField));
      await tester.pumpAndSettle();

      expect(selected, isFalse,
          reason: 'אין פריטים לבחור, ולכן onSelected לא נקרא');
    });

    testWidgets('onSelected=null משאיר את השדה כמושבת', (tester) async {
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
        ],
        onSelected: null,
      );

      // לחיצה לא אמורה להפיל בעיות
      await tester.tap(find.byType(AppSelectionField));
      await tester.pumpAndSettle();

      // אין פעולה — לא קורה כלום
      expect(find.byType(AppSelectionField), findsOneWidget);
    });
  });
}
