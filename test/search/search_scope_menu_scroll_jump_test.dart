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

/// קפיצה לסוף תוצאות החיפוש בתפריט ההיקף (issue #4766): ListView בונה בקפיצה
/// כל שורה שבדרך, גם עם shrinkWrap.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ההקלדה בשדה ההיקף עוברת דרך sanitizeQuery של מנוע ה-Rust.
  final engineReady = await tryInitSearchEngine();

  testWidgets(
    'קפיצה לסוף אלפי תוצאות בתפריט ההיקף בונה רק את שורות היעד '
    '(issue #4766)',
    (tester) async {
      final folder = Category(
        title: 'תיקייה',
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: [],
        books: [
          for (var i = 0; i < 3000; i++)
            TextBook(
              id: i + 1,
              title: 'ספר $i',
              categoryPath: '/תיקייה',
              order: i,
            ),
        ],
        parent: null,
      );
      final library = Library(categories: [folder]);
      folder.parent = library;

      final libraryBloc = _MockLibraryBloc();
      whenListen(
        libraryBloc,
        const Stream<LibraryState>.empty(),
        initialState: LibraryState(library: library),
      );
      addTearDown(libraryBloc.close);
      await tester.binding.setSurfaceSize(const Size(600, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var selection = <String>{'/'};
      await tester.pumpWidget(
        MaterialApp(
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
      await tester.enterText(find.byType(TextField), 'ספר');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      var rowBuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is Checkbox) rowBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(Scaffold),
                  matching: find.byType(Scrollable),
                )
                .last,
          )
          .position;
      expect(position.maxScrollExtent, greaterThan(50000));
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(rowBuilds, lessThan(200));
    },
    skip: !engineReady,
  );
}
