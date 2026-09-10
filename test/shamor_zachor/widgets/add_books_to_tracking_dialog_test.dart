import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/add_books_to_tracking_dialog.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

Category _category(String title, {Category? parent}) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [],
    parent: parent,
  );
  parent?.subCategories.add(category);
  return category;
}

Library _buildLibrary() {
  final bavli = _category(DatabaseConstants.talmudBavliFolderName);
  final seder = _category('סדר זרעים', parent: bavli);
  seder.books.add(TextBook(title: 'ברכות', id: 1, category: seder));
  seder.books.add(
    PdfBook(
      title: 'ברכות',
      id: 1,
      externalLibraryId: DatabaseConstants.talmudBavliPdfExternalLibraryId(
        'ברכות',
      ),
      category: seder,
      path: r'C:\books\תלמוד בבלי\ברכות.pdf',
    ),
  );

  final halacha = _category('הלכה');
  halacha.books.add(
    TextBook(title: 'ברכות חיצוני', id: 7, externalLibraryId: 'otzar'),
  );

  return Library(categories: [bavli, halacha]);
}

Future<void> _pumpDialog(WidgetTester tester) async {
  final bloc = _MockLibraryBloc();
  whenListen(
    bloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(library: _buildLibrary()),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<LibraryBloc>.value(
        value: bloc,
        child: AddBooksToTrackingDialog(
          dataProvider: ShamorZachorDataProvider(),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpDialogAndSearch(WidgetTester tester) async {
  await _pumpDialog(tester);
  await tester.enterText(find.byType(TextField), 'ברכות');
  await tester.pumpAndSettle();
}

Future<void> _expandCategory(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pump();
}

void main() {
  testWidgets('מהדורת ה-PDF המצורפת של מסכת בבלי אינה מוצגת ברשימה', (
    tester,
  ) async {
    await _pumpDialogAndSearch(tester);

    expect(find.widgetWithText(CheckboxListTile, 'ברכות'), findsOneWidget);
    final tile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'ברכות'),
    );
    expect(tile.onChanged, isNotNull);
    expect(find.text('ספר חיצוני — לא נתמך במעקב'), findsOneWidget);
  });

  testWidgets('ספר מקטלוג חיצוני אמיתי מוצג עם הנימוק "ספר חיצוני"', (
    tester,
  ) async {
    await _pumpDialogAndSearch(tester);

    final external = find.widgetWithText(CheckboxListTile, 'ברכות חיצוני');
    expect(external, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(external).onChanged, isNull);
    expect(
      find.descendant(
        of: external,
        matching: find.text('ספר חיצוני — לא נתמך במעקב'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('גם בעץ הקטגוריות מוצגת רק מהדורת הטקסט של המסכת', (
    tester,
  ) async {
    await _pumpDialog(tester);

    await _expandCategory(tester, DatabaseConstants.talmudBavliFolderName);
    await _expandCategory(tester, 'סדר זרעים');

    expect(find.widgetWithText(CheckboxListTile, 'ברכות'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'ברכות'),
          )
          .onChanged,
      isNotNull,
    );
  });
}
