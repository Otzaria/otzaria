import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_settings_bloc.dart';

/// חלונית המפרשים ב-PDF ננעלה על `removeNikud: false` כי המסך לא העביר אותו
/// כלל, ולכן הפרה בשקט את הגדרת התצוגה של המשתמש. הטסטים כאן נועלים את
/// המסלול: הדגלים חייבים להגיע מהפאנל אל תוכן המפרש.

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

Link _commentaryLink({required int index1}) => Link(
  heRef: 'רש"י',
  index1: index1,
  path2: '/books/rashi.txt',
  index2: 1,
  connectionType: 'COMMENTARY',
);

PdfBookTab _tab() {
  final tab = PdfBookTab(
    book: PdfBook(title: 'מכות', path: '/books/מכות.pdf'),
    pageNumber: 1,
  );
  tab.currentTextLineNumber = 10;
  tab.currentTextLineNumberEnd = 20;
  tab.links = [_commentaryLink(index1: 10)];
  tab.activeCommentators = {'rashi'};
  return tab;
}

Future<List<CommentaryContent>> _pumpPanel(
  WidgetTester tester, {
  required bool removeNikud,
  required bool removePunctuation,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(
            value: StubSettingsBloc(SettingsState.initial()),
          ),
          BlocProvider<PersonalNotesBloc>.value(
            value: _FakePersonalNotesBloc(),
          ),
        ],
        child: Scaffold(
          body: PdfCommentaryPanel(
            tab: _tab(),
            linksCount: 1,
            linksLoading: false,
            openBookCallback: (_) {},
            fontSize: 16.0,
            displayProfile: TextDisplayProfile(
              nikud: removeNikud ? MarkVisibility.hide : MarkVisibility.show,
              punctuation: removePunctuation
                  ? MarkVisibility.hide
                  : MarkVisibility.show,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return tester
      .widgetList<CommentaryContent>(find.byType(CommentaryContent))
      .toList();
}

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('PdfCommentaryPanel — העברת דגלי ניקוד/פיסוק לתוכן המפרש', () {
    testWidgets('removeNikud=true מגיע אל CommentaryContent', (tester) async {
      final contents = await _pumpPanel(
        tester,
        removeNikud: true,
        removePunctuation: false,
      );
      expect(contents, isNotEmpty, reason: 'צריך להיבנות לפחות מפרש אחד');
      expect(contents.every((c) => c.displayProfile.removeNikud), isTrue);
    });

    testWidgets('removeNikud=false מגיע אל CommentaryContent', (tester) async {
      final contents = await _pumpPanel(
        tester,
        removeNikud: false,
        removePunctuation: false,
      );
      expect(contents, isNotEmpty);
      expect(contents.every((c) => c.displayProfile.removeNikud), isFalse);
    });

    testWidgets('removePunctuation=true מגיע אל CommentaryContent', (
      tester,
    ) async {
      final contents = await _pumpPanel(
        tester,
        removeNikud: false,
        removePunctuation: true,
      );
      expect(contents, isNotEmpty);
      expect(contents.every((c) => c.displayProfile.removePunctuation), isTrue);
    });
  });
}
