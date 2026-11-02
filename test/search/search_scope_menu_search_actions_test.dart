import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/scope_tree.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';

import '../support/search_engine_test_init.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

Library _buildLibrary() {
  final torah = Category(
    title: 'תורה',
    description: '',
    shortDescription: '',
    order: 10,
    subCategories: [],
    books: [
      TextBook(title: 'בראשית', categoryPath: '/תנ״ך/תורה'),
      TextBook(title: 'שמות', categoryPath: '/תנ״ך/תורה'),
    ],
    parent: null,
  );
  final tanach = Category(
    title: 'תנ״ך',
    description: '',
    shortDescription: '',
    order: 10,
    subCategories: [torah],
    books: [],
    parent: null,
  );
  torah.parent = tanach;
  final library = Library(categories: [tanach]);
  tanach.parent = library;
  return library;
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ההקלדה בשדה ההיקף עוברת דרך sanitizeQuery של מנוע ה-Rust; כשאין build
  // זמין הקבוצה מדולגת.
  final engineReady = await tryInitSearchEngine();

  /// הבחירה החיה של הרכיב הנשלט — מוזנת חזרה דרך onChanged כמו בדיאלוג.
  late Set<String> selection;

  Future<void> pumpMenu(WidgetTester tester, Set<String> selected) async {
    final libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(library: _buildLibrary()),
    );
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await libraryBloc.close();
    });

    selection = selected;
    await tester.binding.setSurfaceSize(const Size(600, 700));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: BlocProvider<LibraryBloc>.value(
          value: libraryBloc,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SearchScopeMenuButton(
                selected: selection,
                onChanged: (next) => setState(() => selection = next),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// מקליד בשדה ההיקף ומחכה לבניית עץ התוצאות.
  Future<void> typeQuery(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// טקסט בתוך רשימת התפריט בלבד — ולא הטקסט שהוקלד בשדה ההיקף.
  Finder textInList(String label) =>
      find.descendant(of: find.byType(ListView), matching: find.text(label));

  /// שורת התפריט (InkWell) שמכילה את [label].
  Finder rowOf(String label) => find
      .ancestor(of: textInList(label), matching: find.byType(InkWell))
      .first;

  Checkbox checkboxOf(WidgetTester tester, String label) =>
      tester.widget<Checkbox>(
        find.descendant(of: rowOf(label), matching: find.byType(Checkbox)),
      );

  /// מרחף עם עכבר מעל השורה של [label].
  Future<void> hoverOver(WidgetTester tester, String label) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(rowOf(label)));
    await tester.pump();
  }

  group(
    'פעולות בתוצאות סינון ההיקף (issue #933)',
    () {
      testWidgets('"נקה הכל" מוצג בתוצאות ומנקה גם היקף ברירת מחדל', (
        tester,
      ) async {
        await pumpMenu(tester, {'/'});
        await typeQuery(tester, 'בראשית');

        // ברירת המחדל מסמנת את כל התוצאות.
        expect(checkboxOf(tester, 'בראשית').value, isTrue);
        expect(find.text('נקה הכל'), findsOneWidget);

        await tester.tap(find.text('נקה הכל'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(selection, isEmpty);
        expect(checkboxOf(tester, 'בראשית').value, isFalse);
      });

      testWidgets('"נקה הכל" לא מוצג כשאין שום בחירה', (tester) async {
        await pumpMenu(tester, <String>{});
        await typeQuery(tester, 'בראשית');

        expect(textInList('בראשית'), findsOneWidget);
        expect(find.text('נקה הכל'), findsNothing);
      });

      testWidgets('ריחוף חושף "רק", ולחיצה בוחרת את השורה בלבד', (
        tester,
      ) async {
        await pumpMenu(tester, {'/'});
        await typeQuery(tester, 'בראשית');

        // "רק" לפי המצביע בפועל, לא לפי מערכת ההפעלה (MIG-16, DD-31): בלי
        // עכבר מחובר (מגע) הוא מוצג תמיד.
        expect(find.text('רק'), findsOneWidget);

        // עם עכבר: מוצג רק בשורה שמתחת למצביע.
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: tester.getCenter(rowOf('בראשית')));
        addTearDown(mouse.removePointer);
        await tester.pump();
        await mouse.moveBy(const Offset(1, 0));
        await tester.pump();
        expect(find.text('רק'), findsOneWidget);
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        expect(find.text('רק'), findsNothing);

        await mouse.moveTo(tester.getCenter(rowOf('בראשית')));
        await tester.pump();
        expect(find.text('רק'), findsOneWidget);

        await tester.tap(find.text('רק'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // facet של ספר הוא מפתח catalogueOrderKey מורכב — נבנה כמו ברכיב.
        final expectedFacet = FacetHelper.buildBookFacet(
          '/תנ״ך/תורה',
          TextBook(title: 'בראשית', categoryPath: '/תנ״ך/תורה'),
        );
        expect(selection, {expectedFacet});
        expect(checkboxOf(tester, 'בראשית').value, isTrue);
      });

      testWidgets('ריחוף אינו בונה מחדש את התפריט (perf)', (tester) async {
        await pumpMenu(tester, {'/'});
        await typeQuery(tester, 'בראשית');

        // בנייה מחדש של התפריט מריצה שוב את החיפוש בכל העץ, ויוצרת שורות חדשות.
        final labelBefore = tester.widget<Text>(textInList('בראשית'));
        await hoverOver(tester, 'בראשית');

        expect(find.text('רק'), findsOneWidget);
        expect(tester.widget<Text>(textInList('בראשית')), same(labelBefore));
      });

      testWidgets('חיצים וסימון אינם סורקים שוב את העץ לאותה שאילתה (perf)', (
        tester,
      ) async {
        await pumpMenu(tester, <String>{});
        // "תורה" (תיקייה), ואחריה "שמות" ו"בראשית" שבתוכה.
        await typeQuery(tester, 'תורה');
        final scans = ScopeTree.debugSearchScans;

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(selection, {
          FacetHelper.buildBookFacet(
            '/תנ״ך/תורה',
            TextBook(title: 'שמות', categoryPath: '/תנ״ך/תורה'),
          ),
        });
        expect(ScopeTree.debugSearchScans, scans);

        await typeQuery(tester, 'בראשית');
        expect(ScopeTree.debugSearchScans, greaterThan(scans));
        expect(textInList('בראשית'), findsOneWidget);
        expect(textInList('שמות'), findsNothing);
      });
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );
}
