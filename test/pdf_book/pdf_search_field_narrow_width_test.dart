import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// חלונית החיפוש בתוך PDF (`PdfBookSearchView`) בנויה מ-[SearchPaneBase] בתוך
/// חלונית הניווט של מסך ה-PDF, מתחת לסרגל העליון. השדה יושב בחלונית בכל רוחב,
/// ולא בסרגל — שם הוא חלק את הרוחב עם הכותרת והפעולות ונדחס בטלפון.
class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpPdfSearchPane(WidgetTester tester, Size screen) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final settingsBloc = _TestSettingsBloc(SettingsState.initial());
  addTearDown(settingsBloc.close);

  final host = NavPanelSearchHost();
  addTearDown(host.dispose);
  final controller = TextEditingController(text: 'בראשית');
  addTearDown(controller.dispose);
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);

  // רוחב החלונית: במסך צר היא נפרשת כמעט על כל הרוחב, במסך רחב היא קבועה.
  final paneWidth = screen.width < 600 ? screen.width - 20 : 300.0;

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: Column(
              children: [
                AppTopBar(
                  minCenterWidth: ReaderNavCenter.minTitleWidth,
                  leadingItems: [
                    AppTopBarItem(
                      widget: const SizedBox(width: 40, height: 40),
                    ),
                  ],
                  center: const Text('שם הספר'),
                  trailingItems: [
                    AppTopBarItem(
                      flexible: true,
                      widget: const SizedBox(width: 120, height: 40),
                    ),
                  ],
                ),
                Expanded(
                  child: NavPanelSearchScope(
                    host: host,
                    child: NavPanelSearchSlot(
                      index: 0,
                      child: SizedBox(
                        width: paneWidth,
                        child: SearchPaneBase(
                          searchController: controller,
                          focusNode: focusNode,
                          resultsWidget: const SizedBox(),
                          isNoResults: false,
                          resetSearchCallback: () {},
                          hintText: 'חפש כאן...',
                          onAdvancedSearch: () {},
                          searchFieldActions: [
                            OtzariaSearchAction.icon(
                              iconData: Icons.abc,
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _editableWidth(WidgetTester tester) =>
    tester.getSize(find.byType(EditableText)).width;

void main() {
  group('שדה החיפוש בתוך PDF', () {
    testWidgets('ברוחב טלפון: שדה אחד בלבד, בתוך החלונית, ורחב דיו לטקסט', (
      tester,
    ) async {
      await _pumpPdfSearchPane(tester, const Size(412, 915));

      expect(find.byType(OtzariaSearchField), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppTopBar),
          matching: find.byType(OtzariaSearchField),
        ),
        findsNothing,
      );
      expect(
        _editableWidth(tester),
        greaterThan(150),
        reason: 'שדה צר מזה חותך את התווית ומסתיר את הטקסט שהוקלד',
      );
    });

    testWidgets('ברוחב שולחני השדה בחלונית, לא בסרגל העליון', (tester) async {
      await _pumpPdfSearchPane(tester, const Size(1400, 900));

      expect(find.byType(OtzariaSearchField), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NavPanelSearchScope),
          matching: find.byType(OtzariaSearchField),
        ),
        findsOneWidget,
      );
    });
  });
}
