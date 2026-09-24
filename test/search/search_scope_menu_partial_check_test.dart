import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
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
  final engineReady = await tryInitSearchEngine();
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

    // רכיב נשלט: הבחירה מוזנת חזרה דרך onChanged, כמו בדיאלוג האמיתי.
    var selection = selected;
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

  /// ה-finder של התיבה שבאותה שורה של [label] בתפריט הפתוח.
  Finder checkboxFinder(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
    matching: find.byType(Checkbox),
  );

  /// התיבה שבאותה שורה של [label] בתפריט הפתוח.
  Checkbox checkboxOf(WidgetTester tester, String label) =>
      tester.widget<Checkbox>(checkboxFinder(label));

  /// כניסה למסך הפנימי של "כל הספרים" (רשימת התיקיות).
  Future<void> drillIntoAllBooks(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('כל הספרים'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('סימן ביניים בתפריט היקף החיפוש', () {
    testWidgets('בחירה חלקית מציגה סימן ביניים על "כל הספרים"', (tester) async {
      await pumpMenu(tester, {'/תנ״ך/תורה/בראשית'});
      expect(checkboxOf(tester, 'כל הספרים').value, isNull);
    });

    testWidgets('ללא צמצום — "כל הספרים" מסומן מלא', (tester) async {
      await pumpMenu(tester, {'/'});
      expect(checkboxOf(tester, 'כל הספרים').value, isTrue);
    });

    testWidgets('תיקיה עם ילד נבחר שומרת על תיבה במצב ביניים', (tester) async {
      await pumpMenu(tester, {'/תנ״ך/תורה/בראשית'});
      // כניסה ל"כל הספרים" ← רמת הקטגוריות; "תנ״ך" חלקית — התיבה חייבת
      // להישאר מוצגת (רגרסיה: check==null פורש כ"אין תיבה").
      await drillIntoAllBooks(tester);
      expect(checkboxOf(tester, 'תנ״ך').value, isNull);
    });

    testWidgets('לחיצה על התיבה של "כל הספרים" מבטלת את הסימון', (
      tester,
    ) async {
      // issue #923: הסימון נשאר מלא לנצח כי גם בחירה ריקה הוצגה כ-וי מלא,
      // בעוד התיקיות במסך הפנימי כבר הוצגו לא מסומנות.
      await pumpMenu(tester, {'/'});
      await tester.tap(checkboxFinder('כל הספרים'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(checkboxOf(tester, 'כל הספרים').value, isFalse);

      await drillIntoAllBooks(tester);
      expect(checkboxOf(tester, 'תנ״ך').value, isFalse);
    });

    testWidgets('בחירה ריקה מוצגת כ"כל הספרים" לא מסומן, ולחיצה מסמנת', (
      tester,
    ) async {
      await pumpMenu(tester, <String>{});
      expect(checkboxOf(tester, 'כל הספרים').value, isFalse);

      await tester.tap(checkboxFinder('כל הספרים'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(checkboxOf(tester, 'כל הספרים').value, isTrue);

      await drillIntoAllBooks(tester);
      expect(checkboxOf(tester, 'תנ״ך').value, isTrue);
    });

    testWidgets('שורת "נקה הכל" נשארת ללא תיבה', (tester) async {
      await pumpMenu(tester, {'/תנ״ך/תורה/בראשית'});
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('נקה הכל'),
            matching: find.byType(InkWell),
          ),
          matching: find.byType(Checkbox),
        ),
        findsNothing,
      );
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}
