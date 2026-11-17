// #5202: בכרטיסיית המפרשים כפתור נעיצת החלונית מוצג רק כשלחלונית יש מקום
// להידחק ליד התוכן. בחלון צר הנעיצה אינה עושה דבר.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/view/commentators_tab_top_bar.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

import '../../helpers/memory_settings_cache.dart';

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required bool navPaneOpen,
  required bool canPinNavPane,
  bool navPanePinned = false,
  VoidCallback? onTogglePin,
}) async {
  tester.view.physicalSize = const Size(1600, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = _SettingsBloc();
  final allExpanded = ValueNotifier(false);
  addTearDown(() async {
    allExpanded.dispose();
    await settings.close();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<SettingsBloc>.value(
        value: settings,
        child: Scaffold(
          body: CommentatorsTabTopBar(
            title: 'מפרשים על בראשית',
            prevMajorTooltip: 'הפרק הקודם',
            nextMajorTooltip: 'הפרק הבא',
            navPaneOpen: navPaneOpen,
            navPanePinned: navPanePinned,
            canPinNavPane: canPinNavPane,
            onToggleNavPane: () {},
            onTogglePin: onTogglePin ?? () {},
            onPrevMajor: () {},
            onPrevMinor: () {},
            onNextMinor: () {},
            onNextMajor: () {},
            textDisplayAction: ActionButtonData(
              widget: BarButton.icon(
                tooltip: 'תצוגה',
                icon: Icons.text_fields,
                onPressed: () {},
              ),
              icon: Icons.text_fields,
              tooltip: 'תצוגה',
              actionId: ToolbarActionId.textDisplay,
              onPressed: () {},
            ),
            onPrint: () {},
            onSearch: () {},
            allExpanded: allExpanded,
            onToggleAllExpanded: () {},
            onAddBookmark: () {},
            book: TextBook(title: 'בראשית'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  testWidgets('אין מקום לחלונית ליד התוכן: אין כפתור נעיצה', (tester) async {
    await _pump(tester, navPaneOpen: true, canPinNavPane: false);
    expect(find.byTooltip('נעץ את החלונית'), findsNothing);
    expect(find.byTooltip('בטל נעיצה'), findsNothing);
  });

  testWidgets('אין מקום, אבל נעוצה מהעבר: אפשר לבטל נעיצה', (tester) async {
    await _pump(
      tester,
      navPaneOpen: true,
      navPanePinned: true,
      canPinNavPane: false,
    );
    expect(find.byTooltip('בטל נעיצה'), findsOneWidget);
    expect(find.byTooltip('נעץ את החלונית'), findsNothing);
  });

  testWidgets('יש מקום: כפתור הנעיצה מוצג ופועל', (tester) async {
    var toggles = 0;
    await _pump(
      tester,
      navPaneOpen: true,
      canPinNavPane: true,
      onTogglePin: () => toggles++,
    );
    await tester.tap(find.byTooltip('נעץ את החלונית'));
    expect(toggles, 1);
  });

  testWidgets('חלונית סגורה: אין כפתור נעיצה גם כשיש מקום', (tester) async {
    await _pump(tester, navPaneOpen: false, canPinNavPane: true);
    expect(find.byTooltip('נעץ את החלונית'), findsNothing);
  });
}
