import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/widgets/notes_search_header.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

import '../../test_helpers/stub_personal_notes_bloc.dart';

void main() {
  testWidgets('שדה "חפש בהערות" נושא את אייקון חיפוש בהערות', (tester) async {
    final bloc = StubPersonalNotesBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<PersonalNotesBloc>.value(
            value: bloc,
            child: const NotesSearchHeader(
              bookId: 'ספר',
              visibleLineIndices: [0, 1],
            ),
          ),
        ),
      ),
    );

    expect(
      find.byIcon(OtzariaIcons.search_in_notes_24_regular),
      findsOneWidget,
    );
  });
}
