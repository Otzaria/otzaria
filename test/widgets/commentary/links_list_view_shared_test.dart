import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';

import '../../helpers/memory_settings_cache.dart';

/// [LinksListView] חולץ מ-`SelectedLineLinksView` כדי שכרטיסיית הטקסט וחלונית
/// ה-PDF יציגו את אותה רשימת קישורים. הטסטים כאן נועלים את התכונה שמאפשרת
/// זאת: הווידג'ט חייב להישאר חסר-תלות ב-`TextBookBloc`.
class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Link _link({
  required String path2,
  required String connectionType,
  int index1 = 5,
  int index2 = 1,
}) => Link(
  heRef: 'הפניה $path2',
  index1: index1,
  path2: path2,
  index2: index2,
  connectionType: connectionType,
);

/// בונה את הרשימה המשותפת **בלי** `BlocProvider<TextBookBloc>` — כך שכל
/// קריאה ל-`read<TextBookBloc>()` בתוכה תיכשל ותיתפס כאן.
Future<Set<String>?> _pumpWithoutTextBookBloc(
  WidgetTester tester, {
  required List<Link> links,
  Set<String> selectedTypes = const {},
}) async {
  Set<String>? lastEmitted;
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<SettingsBloc>.value(
        value: _FakeSettingsBloc(),
        child: Scaffold(
          body: LinksListView(
            links: links,
            chipSourceLinks: links,
            openBookTitle: 'שבת',
            selectedLinkTypes: selectedTypes,
            onSelectedLinkTypesChanged: (types) => lastEmitted = types,
            openBookCallback: (_) {},
            fontSize: 16,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return lastEmitted;
}

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('LinksListView — חסר תלות ב-TextBookBloc', () {
    testWidgets('נבנה ללא BlocProvider<TextBookBloc> ולא זורק', (tester) async {
      await _pumpWithoutTextBookBloc(
        tester,
        links: [
          _link(path2: 'מסורת הש"ס', connectionType: LinkTypes.mesoratHashas),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(LinksListView), findsOneWidget);
    });

    testWidgets('מציג שדה חיפוש', (tester) async {
      await _pumpWithoutTextBookBloc(
        tester,
        links: [_link(path2: 'עין משפט', connectionType: LinkTypes.einMishpat)],
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('רשימה ריקה מציגה את הודעת ברירת המחדל', (tester) async {
      await _pumpWithoutTextBookBloc(tester, links: const []);
      expect(find.text('לא נמצאו קישורים לקטע הנבחר'), findsOneWidget);
    });

    testWidgets('emptyMessage מותאם נכבד', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: _FakeSettingsBloc(),
            child: Scaffold(
              body: LinksListView(
                links: const [],
                chipSourceLinks: const [],
                openBookTitle: 'מכות',
                selectedLinkTypes: const {},
                onSelectedLinkTypesChanged: (_) {},
                openBookCallback: (_) {},
                fontSize: 16,
                emptyMessage: 'לא נמצאו קישורים לדף זה',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('לא נמצאו קישורים לדף זה'), findsOneWidget);
    });

    testWidgets('שני סוגי קישורים שונים מציגים שורת צ׳יפים', (tester) async {
      await _pumpWithoutTextBookBloc(
        tester,
        links: [
          _link(path2: 'מסורת הש"ס', connectionType: LinkTypes.mesoratHashas),
          _link(path2: 'עין משפט', connectionType: LinkTypes.einMishpat),
        ],
      );
      expect(find.byType(FilterChipsSelector<String>), findsWidgets);
    });

    testWidgets('סוג יחיד אינו מציג צ׳יפים', (tester) async {
      await _pumpWithoutTextBookBloc(
        tester,
        links: [
          _link(path2: 'מסורת הש"ס', connectionType: LinkTypes.mesoratHashas),
        ],
      );
      expect(find.byType(FilterChipsSelector<String>), findsNothing);
    });
  });

  group('LinksListView — סינון הסוגים יוצא בקולבק ולא ב-BLoC', () {
    testWidgets('בחירת צ׳יפ מדווחת דרך onSelectedLinkTypesChanged', (
      tester,
    ) async {
      Set<String>? emitted;
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: _FakeSettingsBloc(),
            child: Scaffold(
              body: LinksListView(
                links: [
                  _link(
                    path2: 'מסורת הש"ס',
                    connectionType: LinkTypes.mesoratHashas,
                  ),
                  _link(
                    path2: 'עין משפט',
                    connectionType: LinkTypes.einMishpat,
                  ),
                ],
                chipSourceLinks: [
                  _link(
                    path2: 'מסורת הש"ס',
                    connectionType: LinkTypes.mesoratHashas,
                  ),
                  _link(
                    path2: 'עין משפט',
                    connectionType: LinkTypes.einMishpat,
                  ),
                ],
                openBookTitle: 'שבת',
                selectedLinkTypes: const {},
                onSelectedLinkTypesChanged: (types) => emitted = types,
                openBookCallback: (_) {},
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final chip = find.byType(Chip).first;
      expect(chip, findsOneWidget);
      await tester.tap(chip, warnIfMissed: false);
      await tester.pump();

      expect(
        emitted,
        isNotNull,
        reason: 'הבחירה חייבת לצאת בקולבק — בלעדיו ה-PDF לא יכול לסנן',
      );
    });

    testWidgets('סינון לסוג שאין לו קישור מציג הודעת "מהסוגים שנבחרו"', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: _FakeSettingsBloc(),
            child: Scaffold(
              body: LinksListView(
                links: [
                  _link(
                    path2: 'מסורת הש"ס',
                    connectionType: LinkTypes.mesoratHashas,
                  ),
                ],
                chipSourceLinks: [
                  _link(
                    path2: 'מסורת הש"ס',
                    connectionType: LinkTypes.mesoratHashas,
                  ),
                  _link(
                    path2: 'עין משפט',
                    connectionType: LinkTypes.einMishpat,
                  ),
                ],
                openBookTitle: 'שבת',
                selectedLinkTypes: const {LinkTypes.einMishpat},
                onSelectedLinkTypesChanged: (_) {},
                openBookCallback: (_) {},
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('לא נמצאו קישורים מהסוגים שנבחרו'), findsOneWidget);
    });
  });

  testWidgets('שינוי contentScopeKey מאפס גלילה בלי לפרק את ה-State', (
    tester,
  ) async {
    final links = List.generate(
      30,
      (index) => _link(
        path2: 'ספר-$index',
        connectionType: LinkTypes.mesoratHashas,
      ),
    );
    CommentaryService.seedEraCache({
      for (var index = 0; index < 30; index++)
        'ספר-$index': CommentaryEra.other,
    });

    Widget view(String scopeKey) => MaterialApp(
      home: BlocProvider<SettingsBloc>.value(
        value: _FakeSettingsBloc(),
        child: Scaffold(
          body: LinksListView(
            links: links,
            chipSourceLinks: links,
            openBookTitle: 'שבת',
            selectedLinkTypes: const {},
            onSelectedLinkTypesChanged: (_) {},
            openBookCallback: (_) {},
            fontSize: 16,
            contentScopeKey: scopeKey,
          ),
        ),
      ),
    );

    await tester.pumpWidget(view('עמוד-א'));
    for (var i = 0; i < 20 && find.byType(ListView).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ListView), findsOneWidget);
    final stateBefore = tester.state(find.byType(LinksListView));
    final listBefore = tester.widget<ListView>(find.byType(ListView));
    listBefore.controller!.jumpTo(500);
    await tester.pump();
    expect(listBefore.controller!.offset, greaterThan(0));

    await tester.pumpWidget(view('עמוד-ב'));
    await tester.pump();

    final listAfter = tester.widget<ListView>(find.byType(ListView));
    expect(tester.state(find.byType(LinksListView)), same(stateBefore));
    expect(listAfter.controller!.offset, 0);
  });

  group('מבנה — שני הצדדים צורכים את אותה רשימה', () {
    String read(String path) => File(path).readAsStringSync();

    test('כרטיסיית הטקסט וחלונית ה-PDF מייבאות את LinksListView', () {
      const importRef = 'widgets/commentary/links_list_view.dart';
      expect(
        read('lib/text_book/view/selected_line_links_view.dart'),
        contains(importRef),
      );
      expect(
        read('lib/pdf_book/view/pdf_commentary_panel.dart'),
        contains(importRef),
      );
    });

    test('הווידג\'ט המשותף אינו תלוי ב-TextBookBloc', () {
      final source = read('lib/widgets/commentary/links_list_view.dart');
      // ההערה התיעודית מזכירה את השם; מה שאסור הוא ייבוא או שימוש בקוד.
      expect(source, isNot(contains('text_book_bloc.dart')));
      expect(source, isNot(contains('text_book_state.dart')));
      expect(source, isNot(contains('text_book_event.dart')));
      expect(source, isNot(contains('read<TextBookBloc')));
      expect(source, isNot(contains('TextBookStateBuilder')));
      expect(source, isNot(contains('TextBookLoaded')));
    });

    test('חלונית ה-PDF אינה מחזיקה עוד tile קישורים משלה', () {
      expect(
        read('lib/pdf_book/view/pdf_commentary_panel.dart'),
        isNot(contains('_buildLinkTile')),
      );
    });

    test('המתאם ממשיך לייצא את העזרים הטהורים לצרכני הטקסט', () {
      expect(
        read('lib/text_book/view/selected_line_links_view.dart'),
        contains(
          "export 'package:otzaria/widgets/commentary/"
          "links_list_view.dart';",
        ),
      );
    });
  });
}
