import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/reading_toc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

// מבנה בסגנון מסכת שבת: כותרת לכל עמוד ושורות גמרא אחריה.
const int _firstDaf = 2;
const int _lastDaf = 157;
const int _linesPerAmud = 8;
final List<String> _gemara = [
  for (var daf = _firstDaf; daf <= _lastDaf; daf++)
    for (final amud in const ['.', ':']) ...[
      '<h2>דף $daf$amud</h2>',
      for (var line = 1; line <= _linesPerAmud; line++)
        'גמרא דף $daf$amud שורה $line: תנו רבנן כל כתבי הקודש מצילין '
            'אותן מפני הדליקה בין שקורין בהן ובין שאין קורין בהן',
    ],
];
int _amudHeading(int daf, {bool b = false}) =>
    ((daf - _firstDaf) * 2 + (b ? 1 : 0)) * (_linesPerAmud + 1);
final int _target = _amudHeading(122);

List<bool> _window(int start, int end) => [
  for (var i = 0; i < _gemara.length; i++) i >= start && i <= end,
];

TextBookLoaded _state(List<bool> loaded, {required bool continuous}) {
  return TextBookLoaded(
    book: TextBook(title: 'שבת'),
    showLeftPane: false,
    content: [
      for (var i = 0; i < _gemara.length; i++) loaded[i] ? _gemara[i] : '',
    ],
    contentVersion: loaded.where((f) => f).length,
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: true,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: headerToc(_gemara),
    removeNikud: false,
    visibleIndices: [_target],
    selectedIndex: _target,
    pinLeftPane: false,
    searchText: '',
    supportsContinuousReadingMode: true,
    continuousReadingMode: continuous,
    loadedLineFlags: loaded,
  );
}

Future<void> _openAtDafAndWarm(WidgetTester tester, bool continuous) async {
  // חלון הפתיחה של ה-bloc: 80 שורות לפני היעד ו-180 אחריו.
  final partial = _state(
    _window(_target - 80, _target + 180),
    continuous: continuous,
  );
  final bloc = _TestTextBookBloc(partial);
  final notes = _TestPersonalNotesBloc(const PersonalNotesState.initial());
  final settings = StubSettingsBloc(SettingsState.initial());
  // מסך שאינו הקריאה: התצוגה לא מבקשת פוקוס ואינה נזקקת ל-TabsBloc.
  final navigation = _TestNavigationBloc(
    const NavigationState(currentScreen: Screen.library),
  );
  addTearDown(navigation.close);
  final tab = TextBookTab(book: partial.book, index: _target);
  addTearDown(bloc.close);
  addTearDown(notes.close);
  addTearDown(settings.close);
  addTearDown(tab.dispose);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<NavigationBloc>.value(value: navigation),
        ],
        child: Scaffold(
          body: BlocBuilder<TextBookBloc, TextBookState>(
            builder: (context, state) => SimpleTextViewer(
              content: (state as TextBookLoaded).content,
              fontSize: 18,
              openBookCallback: (_) {},
              isMainText: true,
              lines: tab.lines,
              tab: tab,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tab.index, inInclusiveRange(_target, _target + 2));
  expect(
    find.textContaining('גמרא דף 122. שורה 1', findRichText: true),
    findsWidgets,
  );

  // שלוש החלות של חימום הרקע: לפני החלון, תחילת הספר, ואחרי החלון.
  for (final loaded in [
    _window(_target - 80 - 640 * 2, _target + 180),
    _window(0, _target + 180),
    _window(0, _gemara.length - 1),
  ]) {
    bloc.emitForTest(
      _state(loaded, continuous: continuous).copyWith(
        visibleIndices: [tab.index, tab.index + 1],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tab.index,
      inInclusiveRange(_target, _target + 2),
      reason: 'צורת הדף קפצה מדף קכב. אחרי החלת תוכן ברקע',
    );
    expect(
      find.textContaining('גמרא דף 122. שורה 1', findRichText: true),
      findsWidgets,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final continuous in [false, true]) {
    testWidgets(
      'צורת הדף נשארת בדף היעד כשהתוכן נטען ברקע, רציף=$continuous',
      (tester) => _openAtDafAndWarm(tester, continuous),
    );
  }
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }
  void emitForTest(TextBookState state) => emit(state);

  @override
  final TextBookRepository repository = _NoLinksTextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoLinksTextBookRepository extends TextBookRepository {
  _NoLinksTextBookRepository() : super(fileSystem: FileSystemData());

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState) {
    on<NavigationEvent>((event, emit) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
