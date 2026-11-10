// לשונית הקישורים בחלונית סגורה נשארת בעץ: גלילה בספר בזמן שהחלונית סגורה
// אינה בונה את הרשימה, ופתיחתה מציגה את קישורי הקטע הנוכחי.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';

import '../../test_helpers/stub_settings_bloc.dart';

final _first = [_link('ספר א'), _link('ספר ב')];
final _second = [_link('ספר ג')];
final _all = [..._first, ..._second];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Link> shownLinks(WidgetTester tester) =>
      tester.widget<LinksListView>(find.byType(LinksListView)).links;

  testWidgets('חלונית סגורה: גלילה אינה בונה את הרשימה, ופתיחה מציגה את הקטע '
      'הנוכחי', (tester) async {
    final (bloc, setOpen) = await _pump(tester, isPaneOpen: true);
    expect(shownLinks(tester), _first);

    setOpen(false);
    await tester.pump();
    bloc.emitState(_state(_second));
    await tester.pump();
    expect(shownLinks(tester), _first);

    setOpen(true);
    await tester.pump();
    expect(shownLinks(tester), _second);
  });

  testWidgets('חלונית פתוחה: גלילה מעדכנת את הרשימה מיד', (tester) async {
    final (bloc, _) = await _pump(tester, isPaneOpen: true);
    bloc.emitState(_state(_second));
    await tester.pump();
    expect(shownLinks(tester), _second);
    bloc.emitState(_state(_first));
    await tester.pump();
    expect(shownLinks(tester), _first);
  });
}

Future<(_TestTextBookBloc, void Function(bool))> _pump(
  WidgetTester tester, {
  required bool isPaneOpen,
}) async {
  final bloc = _TestTextBookBloc(_state(_first));
  addTearDown(bloc.close);
  final settingsBloc = StubSettingsBloc(SettingsState.initial());
  addTearDown(settingsBloc.close);
  var open = isPaneOpen;
  late StateSetter setOuter;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return SelectedLineLinksView(
                openBookCallback: (_) {},
                fontSize: 18,
                isPaneOpen: open,
              );
            },
          ),
        ),
      ),
    ),
  );
  return (bloc, (bool value) => setOuter(() => open = value));
}

Link _link(String title) => Link(
  heRef: 'הפניה $title',
  index1: 1,
  path2: '/books/$title.txt',
  index2: 1,
  connectionType: LinkTypes.reference,
);

TextBookLoaded _state(List<Link> visibleLinks) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const ['שורה א'],
  fontSize: 18,
  showSplitView: true,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: _all,
  visibleLinks: visibleLinks,
  linksByLine: const {},
  tableOfContents: const [],
  visibleIndices: const [0],
  pinLeftPane: false,
  searchText: '',
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitState(TextBookState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
