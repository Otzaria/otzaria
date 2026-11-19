import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_book/view/toc_navigator_screen.dart';
import 'package:otzaria/text_display/models/text_display_policy.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

TextDisplayPolicy _policy({required bool replaceHolyNames}) =>
    TextDisplayPolicy.fromLegacy(
      defaultRemoveNikud: false,
      removeNikudFromTanach: false,
      defaultRemovePunctuation: false,
      showTeamim: true,
      replaceHolyNames: replaceHolyNames,
      holyNameStyle: HolyNameStyle.kufKuf,
    );

TextBookLoaded _state({required bool replaceHolyNames}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: true,
  content: const ['ברכת יהוה', 'שורה'],
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: [TocEntry(text: 'ברכת יהוה', index: 0, level: 1)],
  removeNikud: false,
  visibleIndices: const [1],
  pinLeftPane: false,
  searchText: '',
  displayPolicy: _policy(replaceHolyNames: replaceHolyNames),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('הסתרת שם השם חלה גם על תוכן העניינים (#3543)', (tester) async {
    final bloc = EmittingStubTextBookBloc(
      _state(replaceHolyNames: false),
    );
    addTearDown(bloc.close);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: BlocProvider<TextBookBloc>.value(
              value: bloc,
              child: TocViewer(
                lines: LineScrollController(),
                closeLeftPaneCallback: () {},
                focusNode: focusNode,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ברכת יהוה'), findsOneWidget);

    // שינוי ההגדרה בזמן שהספר פתוח מתעדכן גם בעץ שכבר נבנה.
    bloc.emitState(_state(replaceHolyNames: true));
    await tester.pumpAndSettle();
    expect(find.text('ברכת יהוה'), findsNothing);
    expect(find.text('ברכת יקוק'), findsOneWidget);
  });
}
