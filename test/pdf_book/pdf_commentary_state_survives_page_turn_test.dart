import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';

import '../helpers/memory_settings_cache.dart';

/// מפתחות הלשוניות של הפאנל נגזרו מהעמוד הנוכחי, מבחירת המפרשים וממצב פאנל
/// הסינון — ולכן כל אחד מאלה פירק את שלוש הלשוניות. הטסטים כאן נועלים את
/// ההפרדה: לשונית אחת אינה מפרקת את שכנותיה, ודפדוף אינו מפרק את ההערות.
///
/// (גלילת רשימת המפרשים *כן* מתאפסת בדפדוף, בכוונה — ראה
/// `_resetScrollIfRangeChanged`. לכן אין כאן טענה על שימור ה-State שלה.)
class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
    : super(
        const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        ),
      ) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Link _link({
  required int index1,
  String path2 = '/books/rashi.txt',
}) => Link(
  heRef: path2,
  index1: index1,
  path2: path2,
  index2: 1,
  connectionType: 'COMMENTARY',
);

PdfBookTab _tab() {
  final tab = PdfBookTab(
    book: PdfBook(title: 'מכות', path: '/books/מכות.pdf'),
    pageNumber: 1,
  );
  tab.currentTextLineNumber = 10;
  tab.currentTextLineNumberEnd = 40;
  tab.links = [_link(index1: 12), _link(index1: 30)];
  tab.activeCommentators = {'rashi'};
  return tab;
}

Widget _wrap(Widget child) => MaterialApp(
  home: MultiBlocProvider(
    providers: [
      BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
      BlocProvider<PersonalNotesBloc>.value(value: _FakePersonalNotesBloc()),
    ],
    child: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('דפדוף אינו מפרק את ה-State של לשונית ההערות', (tester) async {
    final tab = _tab();
    addTearDown(tab.dispose);

    Widget panel() => _wrap(
      PdfCommentaryPanel(
        tab: tab,
        linksCount: tab.links.length,
        linksLoading: false,
        openBookCallback: (_) {},
        fontSize: 16.0,
        initialTabIndex: 2,
      ),
    );

    await tester.pumpWidget(panel());
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester.state(find.byType(PersonalNotesSidebar));

    tab.currentTextLineNumber = 25;
    await tester.pumpWidget(panel());
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.state(find.byType(PersonalNotesSidebar)),
      same(before),
      reason: 'מפתח תלוי-עמוד פירק את ההערות בכל דפדוף, ללא כל צורך',
    );
  });

  testWidgets('דפדוף אינו מפרק את ה-State של לשונית הקישורים', (tester) async {
    final tab = _tab();
    addTearDown(tab.dispose);

    Widget panel() => _wrap(
      PdfCommentaryPanel(
        tab: tab,
        linksCount: tab.links.length,
        linksLoading: false,
        openBookCallback: (_) {},
        fontSize: 16.0,
        initialTabIndex: 1,
      ),
    );

    await tester.pumpWidget(panel());
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester.state(find.byType(LinksListView));

    tab.currentTextLineNumber = 25;
    await tester.pumpWidget(panel());
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.state(find.byType(LinksListView)),
      same(before),
      reason: 'טקסט החיפוש והפתיחות בלשונית הקישורים היו נמחקים בכל דפדוף',
    );
  });

  testWidgets('שינוי בחירת המפרשים אינו מפרק את לשונית ההערות', (tester) async {
    final tab = _tab();
    addTearDown(tab.dispose);

    Widget panel() => _wrap(
      PdfCommentaryPanel(
        tab: tab,
        linksCount: tab.links.length,
        linksLoading: false,
        openBookCallback: (_) {},
        fontSize: 16.0,
        initialTabIndex: 2,
      ),
    );

    await tester.pumpWidget(panel());
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester.state(find.byType(PersonalNotesSidebar));

    tab.activeCommentators = {'rashi', 'tosafot'};
    await tester.pumpWidget(panel());
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.state(find.byType(PersonalNotesSidebar)),
      same(before),
      reason:
          'המפתח הישן כלל את activeCommentators.hashCode ופירק לשוניות זרות',
    );
  });

  testWidgets('ה-State של הפאנל עצמו שורד דפדוף', (tester) async {
    final tab = _tab();
    addTearDown(tab.dispose);

    Widget panel() => _wrap(
      PdfCommentaryPanel(
        tab: tab,
        linksCount: tab.links.length,
        linksLoading: false,
        openBookCallback: (_) {},
        fontSize: 16.0,
      ),
    );

    await tester.pumpWidget(panel());
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester.state(find.byType(PdfCommentaryPanel));

    tab.currentTextLineNumber = 25;
    await tester.pumpWidget(panel());
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.state(find.byType(PdfCommentaryPanel)), same(before));
  });

  testWidgets('מפרשי העמוד הקודם מוסתרים בזמן טעינת העמוד הבא', (
    tester,
  ) async {
    final tab = _tab();
    tab.links = [_link(index1: 12, path2: '/books/old-commentary.txt')];
    tab.activeCommentators = {'old-commentary'};
    addTearDown(tab.dispose);
    final nextPageGroups = Completer<List<LinkGroup>>();

    Future<List<LinkGroup>> loadGroups(List<Link> links) {
      final title = links.first.path2.contains('old-')
          ? 'old-commentary'
          : 'new-commentary';
      if (title == 'new-commentary') return nextPageGroups.future;
      return Future.value([LinkGroup(bookTitle: title, links: links)]);
    }

    Widget panel() => _wrap(
      PdfCommentaryPanel(
        tab: tab,
        linksCount: tab.links.length,
        linksLoading: false,
        openBookCallback: (_) {},
        fontSize: 16.0,
        commentaryGroupsLoader: loadGroups,
      ),
    );

    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    expect(find.text('old-commentary'), findsOneWidget);

    tab.currentTextLineNumber = 100;
    tab.currentTextLineNumberEnd = 130;
    tab.links = [_link(index1: 110, path2: '/books/new-commentary.txt')];
    tab.activeCommentators = {'new-commentary'};

    await tester.pumpWidget(panel());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('old-commentary').hitTestable(), findsNothing);

    nextPageGroups.complete([
      LinkGroup(bookTitle: 'new-commentary', links: tab.links),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('new-commentary'), findsOneWidget);
  });
}
