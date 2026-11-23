import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/reading_toc.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';
import '../../../test_helpers/stub_text_book_bloc.dart';

// #5498: עדכון עץ הנגישות של מסך הקריאה עלה שניות כשגשר הנגישות דלוק. הגבול
// תופס עטיפת Semantics או צומת לכל שורה שנוספים בלי כוונה.
final _lines = [
  for (var i = 0; i < 300; i++)
    '<b>פרק $i</b> ויאמר אלהים יהי אור <a href="otzaria://book/x">קישור</a> '
        'וירא אלהים את האור כי טוב <i>ויבדל</i> אלהים בין האור ובין החשך',
];
const _bookTitle = 'ספר בדיקה';

({int count, int depth, String text}) _treeSize(SemanticsNode root) {
  var count = 0;
  var depth = 0;
  final text = StringBuffer();
  void visit(SemanticsNode node, int level) {
    count++;
    text.write(node.label);
    if (level > depth) depth = level;
    node.visitChildren((child) {
      visit(child, level + 1);
      return true;
    });
  }

  visit(root, 0);
  return (count: count, depth: depth, text: text.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  // מדוד: 97 צמתים בעומק 9 בתצוגה רגילה, 410 בעומק 9 ברציפה (פסקה אחת).
  for (final (continuous, maxNodes) in [(false, 200), (true, 600)]) {
    testWidgets(
      'עץ הנגישות של הקורא קטן ורדוד (רציפה: $continuous)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpView(tester, continuous);
        await tester.pumpAndSettle();

        final size = _treeSize(
          tester
              .binding
              .renderViews
              .first
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        expect(size.depth, lessThanOrEqualTo(10));
        expect(size.count, lessThanOrEqualTo(maxNodes));
        expect(size.text, contains('פרק 0'), reason: 'טקסט הספר נשאר נגיש');
        handle.dispose();
      },
    );
  }
}

Future<void> _pumpView(WidgetTester tester, bool continuous) async {
  final book = TextBook(title: _bookTitle);
  final bloc = StubTextBookBloc(
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: _lines,
      fontSize: 18,
      showSplitView: false,
      showPageShapeView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: headerToc(_lines),
      removeNikud: false,
      visibleIndices: List.generate(_lines.length, (index) => index),
      selectedIndex: null,
      selectedIndices: const {},
      continuousReadingMode: continuous,
      supportsContinuousReadingMode: true,
      pinLeftPane: false,
      searchText: '',
    ),
  );
  final settingsBloc = StubSettingsBloc(SettingsState.initial());
  final notesBloc = StubPersonalNotesBloc(const PersonalNotesState.initial());
  final tab = TextBookTab(book: book, index: 0);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    tab.dispose();
    await bloc.close();
    await settingsBloc.close();
    await notesBloc.close();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: CombinedView(
            data: _lines,
            openBookCallback: (_) {},
            openLeftPaneTab: (_, {searchText}) {},
            textSize: 18,
            showCommentaryAsExpansionTiles: true,
            onOpenPersonalNotes: () {},
            tab: tab,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
