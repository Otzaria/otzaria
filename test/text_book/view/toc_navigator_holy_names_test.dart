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

TextDisplayPolicy _policy({
  required bool replaceHolyNames,
  HolyNameStyle style = HolyNameStyle.kufKuf,
}) => TextDisplayPolicy.fromLegacy(
  defaultRemoveNikud: false,
  removeNikudFromTanach: false,
  defaultRemovePunctuation: false,
  showTeamim: true,
  replaceHolyNames: replaceHolyNames,
  holyNameStyle: style,
);

TextBookLoaded _state({required bool replaceHolyNames}) => TextBookLoaded(
  book: TextBook(title: 'ספר יהוה'),
  showLeftPane: true,
  content: const ['מבוא', 'ברכת יהוה'],
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: [
    TocEntry(text: 'מבוא', index: 0, level: 1),
    TocEntry(text: 'ברכת יהוה', index: 1, level: 1),
  ],
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
    final loaded = _state(replaceHolyNames: false);
    final bloc = EmittingStubTextBookBloc(loaded);
    final navigatedLines = <int>[];
    final lines = LineScrollController()
      ..externalNavigator = (line) async => navigatedLines.add(line);
    addTearDown(lines.dispose);
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
                lines: lines,
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
    expect(find.text('ספר יהוה'), findsOneWidget);

    // שינוי ההגדרה בזמן שהספר פתוח מתעדכן גם בעץ שכבר נבנה.
    bloc.emitState(
      loaded.copyWith(displayPolicy: _policy(replaceHolyNames: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('ברכת יהוה'), findsNothing);
    expect(find.text('ברכת יקוק'), findsOneWidget);
    expect(find.text('ספר יקוק'), findsOneWidget);
    expect(find.text('ספר יהוה'), findsNothing);

    await tester.enterText(find.byType(TextField), 'ברכת יהוה');
    await tester.pump(const Duration(milliseconds: 221));
    await tester.pumpAndSettle();
    bloc.emitState(
      loaded.copyWith(
        displayPolicy: _policy(
          replaceHolyNames: true,
          style: HolyNameStyle.daletDalet,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ספר ידוד'), findsOneWidget);
    expect(find.text('ברכת ידוד'), findsOneWidget);
    expect(loaded.tableOfContents.last.text, 'ברכת יהוה');
    await tester.tap(find.text('ברכת ידוד'));
    await tester.pumpAndSettle();
    expect(navigatedLines, [1]);
  });
}
