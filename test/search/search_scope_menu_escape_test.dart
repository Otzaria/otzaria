import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';

import '../support/search_engine_test_init.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

Future<void> main() async {
  // הפאנל מנקה את טקסט הסינון דרך מנוע ה-Rust.
  final engineReady = await tryInitSearchEngine();

  testWidgets(
    'Escape סוגר את תפריט ההיקף ורק Escape נוסף סוגר את הדיאלוג (#2528)',
    (tester) async {
      final libraryBloc = _MockLibraryBloc();
      whenListen(
        libraryBloc,
        const Stream<LibraryState>.empty(),
        initialState: LibraryState(library: Library(categories: [])),
      );
      addTearDown(libraryBloc.close);

      await tester.pumpWidget(
        BlocProvider<LibraryBloc>.value(
          value: libraryBloc,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: SearchScopeMenuButton(
                        selected: const {'/'},
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      final panel = find.byType(ListView);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing, reason: 'התפריט נסגר');
      expect(find.byType(SearchScopeMenuButton), findsOneWidget);

      // לחיצה חוזרת על השדה פותחת את התפריט מחדש.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SearchScopeMenuButton), findsNothing);
    },
    skip: !engineReady,
  );
}
