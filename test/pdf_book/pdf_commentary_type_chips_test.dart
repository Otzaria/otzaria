import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/utils/commentary_type_filter.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';

import '../helpers/memory_settings_cache.dart';

/// צ׳יפי סינון סוג המפרש היו קיימים בכרטיסיית הטקסט בלבד. הטסטים כאן נועלים
/// את החיווט המקביל בחלונית ה-PDF: הצ׳יפים נבנים מהקטע הנראה, והסינון עצמו
/// חייב לצמצם את הרשימה בפועל (ולא רק לצבוע צ׳יפ).
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
  required String path2,
  required String connectionType,
  int index1 = 10,
  int index2 = 1,
}) => Link(
  heRef: 'הפניה',
  index1: index1,
  path2: path2,
  index2: index2,
  connectionType: connectionType,
);

PdfBookTab _tab(List<Link> links, Set<String> commentators) {
  final tab = PdfBookTab(
    book: PdfBook(title: 'בראשית', path: '/books/בראשית.pdf'),
    pageNumber: 1,
  );
  tab.currentTextLineNumber = 10;
  tab.currentTextLineNumberEnd = 20;
  tab.links = List.of(links);
  tab.activeCommentators = Set.of(commentators);
  return tab;
}

Future<void> _pump(
  WidgetTester tester,
  PdfBookTab tab, {
  CommentaryTypeSelection? typeSelection,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
          BlocProvider<PersonalNotesBloc>.value(
            value: _FakePersonalNotesBloc(),
          ),
        ],
        child: Scaffold(
          body: PdfCommentaryPanel(
            tab: tab,
            linksCount: tab.links.length,
            linksLoading: false,
            openBookCallback: (_) {},
            fontSize: 16.0,
            typeSelection: typeSelection,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('CommentaryTypeFilter — הבסיס המשותף לצ׳יפים', () {
    test('צ׳יפ נבנה רק לסוג שקיים בקישורים', () {
      final keys = CommentaryTypeFilter.chipKeys([
        _link(path2: 'אונקלוס', connectionType: LinkTypes.targum),
        _link(path2: 'רש"י', connectionType: LinkTypes.parshanut),
      ]);
      expect(keys, containsAll([LinkTypes.targum, LinkTypes.parshanut]));
      expect(keys, isNot(contains(LinkTypes.midrash)));
    });

    test('סוג שאינו סוג-סינון אינו מקבל צ׳יפ', () {
      final keys = CommentaryTypeFilter.chipKeys([
        _link(path2: 'ספר', connectionType: 'COMMENTARY'),
      ]);
      expect(keys, isEmpty);
    });

    test('הסדר קבוע לפי commentaryFilterTypes ולא לפי סדר הקישורים', () {
      final keys = CommentaryTypeFilter.chipKeys([
        _link(path2: 'רש"י', connectionType: LinkTypes.parshanut),
        _link(path2: 'אונקלוס', connectionType: LinkTypes.targum),
      ]);
      final expectedOrder = LinkTypes.commentaryFilterTypes
          .where(keys.contains)
          .toList();
      expect(keys, equals(expectedOrder));
    });

    test('בחירה ריקה = הצג הכל', () {
      expect(
        CommentaryTypeFilter.effectiveTypes(
          selectedTypes: const {},
          availableKeys: const [LinkTypes.targum],
        ),
        isEmpty,
      );
    });

    test('בחירה שאין לה צ׳יפ קיים מתנקזת לריקה — לא מסתירה הכל', () {
      expect(
        CommentaryTypeFilter.effectiveTypes(
          selectedTypes: const {LinkTypes.midrash},
          availableKeys: const [LinkTypes.targum],
        ),
        isEmpty,
      );
    });

    test('סוג יחיד אינו מציג צ׳יפים (אינו מסנן כלום)', () {
      expect(
        CommentaryTypeFilter.visibleChipKeys(
          chipKeys: const [LinkTypes.targum],
          effectiveTypes: const {},
        ),
        isEmpty,
      );
    });

    test('סוג יחיד כן מוצג כשהוא הנבחר — אחרת אין דרך לבטל', () {
      expect(
        CommentaryTypeFilter.visibleChipKeys(
          chipKeys: const [LinkTypes.targum],
          effectiveTypes: const {LinkTypes.targum},
        ),
        equals(const [LinkTypes.targum]),
      );
    });

    test('commentatorsByType ממפה סוג לשמות המפרשים', () {
      final byType = CommentaryTypeFilter.commentatorsByType([
        _link(path2: 'אונקלוס', connectionType: LinkTypes.targum),
        _link(path2: 'רש"י', connectionType: LinkTypes.parshanut),
      ]);
      expect(byType[LinkTypes.targum], contains('אונקלוס'));
      expect(byType[LinkTypes.parshanut], contains('רש"י'));
    });
  });

  group('pdfVisibleContentCacheKey — סינון הסוגים נכלל במפתח', () {
    String key({Set<String> types = const {}}) => pdfVisibleContentCacheKey(
      startLine: 10,
      endLine: 20,
      extraLineIndices: null,
      activeCommentators: const ['רש"י'],
      linksIdentity: 7,
      commentaryTypes: types,
    );

    test('שינוי בחירת הסוגים מבטל את המטמון', () {
      expect(key(), isNot(key(types: const {LinkTypes.targum})));
    });

    test('סדר הסוגים אינו משנה את המפתח', () {
      expect(
        key(types: {LinkTypes.parshanut, LinkTypes.targum}),
        key(types: {LinkTypes.targum, LinkTypes.parshanut}),
      );
    });

    test('ברירת המחדל (ללא סוגים) יציבה', () {
      expect(key(), key(types: const {}));
    });
  });

  group('PdfCommentaryPanel — הסינון מצמצם את הרשימה בפועל', () {
    testWidgets('מטמון דורות קר אינו חוסם הצגת כמה מפרשים', (tester) async {
      CommentaryService.clearEraCache();
      final tab = _tab(
        [
          _link(path2: 'אונקלוס', connectionType: LinkTypes.targum),
          _link(path2: 'רש"י', connectionType: LinkTypes.parshanut),
        ],
        {'אונקלוס', 'רש"י'},
      );
      await _pump(tester, tab);
      expect(find.byType(CommentaryContent), findsNWidgets(2));
    });

    testWidgets('מפרש שסוגו אינו סוג-סינון אינו נעלם מהרשימה', (tester) async {
      final tab = _tab(
        [_link(path2: 'ספר', connectionType: 'COMMENTARY')],
        {'ספר'},
      );
      await _pump(tester, tab);
      expect(find.byType(CommentaryContent), findsOneWidget);
    });

    testWidgets('בחירת סוג מצמצמת בפועל — נשאר רק המפרש מאותו סוג', (
      tester,
    ) async {
      final tab = _tab(
        [
          _link(path2: 'אונקלוס', connectionType: LinkTypes.targum),
          _link(path2: 'רש"י', connectionType: LinkTypes.parshanut),
        ],
        {'אונקלוס', 'רש"י'},
      );
      await _pump(
        tester,
        tab,
        typeSelection: CommentaryTypeSelection()..value = {LinkTypes.targum},
      );
      expect(find.byType(CommentaryContent), findsOneWidget);
    });

    testWidgets('בחירת שני סוגים מותירה את שניהם', (tester) async {
      final tab = _tab(
        [
          _link(path2: 'אונקלוס', connectionType: LinkTypes.targum),
          _link(path2: 'רש"י', connectionType: LinkTypes.parshanut),
        ],
        {'אונקלוס', 'רש"י'},
      );
      await _pump(
        tester,
        tab,
        typeSelection: CommentaryTypeSelection()
          ..value = {LinkTypes.targum, LinkTypes.parshanut},
      );
      expect(find.byType(CommentaryContent), findsNWidgets(2));
    });

    testWidgets('בחירת סוג שאין לו מפרש בקטע אינה מסתירה הכול', (tester) async {
      // effectiveTypes מקצץ לבחירה ריקה = הצג הכל, אחרת המשתמש היה נתקע.
      final tab = _tab(
        [_link(path2: 'רש"י', connectionType: LinkTypes.parshanut)],
        {'רש"י'},
      );
      await _pump(
        tester,
        tab,
        typeSelection: CommentaryTypeSelection()..value = {LinkTypes.midrash},
      );
      expect(find.byType(CommentaryContent), findsOneWidget);
    });
  });
}
