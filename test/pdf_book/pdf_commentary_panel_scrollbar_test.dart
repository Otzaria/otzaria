// בדיקת רגרסיה לבאג מפורום https://otzaria.org/forum/topic/736:
// פס גלילה חסר בפאנל המפרשים בתצוגת PDF. תוקן בקומיט 12d6ab65c ע"י הסרת
// ScrollConfiguration(scrollbars: false) שעטף את ה-ScrollablePositionedList
// וכיבה את פס הגלילה המובנה של Flutter בפלטפורמות דסקטופ.

import 'package:flutter/foundation.dart';
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
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import '../helpers/memory_settings_cache.dart';

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

PdfBook _book() => PdfBook(title: 'מכות', path: '/books/מכות.pdf');

PdfBookTab _tab({int? currentLine, int? currentLineEnd, List<Link> links = const []}) {
  final tab = PdfBookTab(book: _book(), pageNumber: 1);
  tab.currentTextLineNumber = currentLine;
  tab.currentTextLineNumberEnd = currentLineEnd;
  tab.links = List.of(links);
  return tab;
}

Link _commentaryLink({required int index1}) => Link(
  heRef: 'רש"י',
  index1: index1,
  path2: '/books/rashi.txt',
  index2: 0,
  connectionType: 'COMMENTARY',
);

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

  testWidgets(
    'רשימת המפרשים עטופה ב-Scrollbar (רגרסיה לבאג פורום 736 - אין פס גלילה)',
    (tester) async {
      // הפס נבנה דרך ScrollBehavior שמוסיף Scrollbar רק בדסקטופ — כופים פלטפורמה.
      // try/finally מבטיח איפוס גם אם pumpWidget/expect יזרקו (לא addTearDown -
      // הוא רץ אחרי בדיקת ה-invariant של foundation).
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final tab = _tab(
          currentLine: 10,
          currentLineEnd: 15,
          links: [_commentaryLink(index1: 12)],
        );
        addTearDown(tab.dispose);

        await tester.pumpWidget(
          _wrap(
            PdfCommentaryPanel(
              tab: tab,
              linksCount: tab.links.length,
              linksLoading: false,
              openBookCallback: (_) {},
              fontSize: 16.0,
              initialTabIndex: 0,
              isFullScreen: true,
              enableInternalFilter: false,
            ),
          ),
        );
        await tester.pump();

        // ודא שיש תוכן מפרשים בפועל (לא הודעת "לא נמצאו")
        expect(find.textContaining('לא נמצאו מפרשים'), findsNothing);

        // פס הגלילה של Flutter (ScrollBehavior) עוטף כל Scrollable בדסקטופ,
        // אלא אם כן ScrollConfiguration(scrollbars: false) מכבה אותו במפורש.
        expect(
          find.byType(Scrollbar),
          findsWidgets,
          reason:
              'רשימת המפרשים חייבת להיות עטופה ב-Scrollbar (ScrollBehavior כברירת מחדל). '
              'אם נעלם - כנראה חזר ScrollConfiguration(scrollbars: false) סביב '
              'ה-ScrollablePositionedList, שגורם להיעדר פס גלילה בתצוגת PDF.',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
