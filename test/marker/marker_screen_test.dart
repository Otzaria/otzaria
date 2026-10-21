import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/storage/marker_changes.dart';
import 'package:otzaria/marker/storage/marker_database.dart';
import 'package:otzaria/marker/view/marker_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

import '../helpers/memory_settings_cache.dart';
import 'marker_test_helpers.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _line = 'בראשית ברא אלהים את השמים ואת הארץ';

void main() {
  late MarkerDatabase db;
  late MarkerRepository repository;
  late _FakeSettingsBloc settingsBloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    MarkerSettings.instance.reload();
    // המסך מאזין לזרם השינויים הגלובלי, כמו באפליקציה.
    db = openTestMarkerStore().db;
    repository = MarkerRepository(
      database: db,
      changes: MarkerChanges.instance,
    );
    settingsBloc = _FakeSettingsBloc();
  });

  tearDown(() async {
    await settingsBloc.close();
    db.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he'),
        home: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: MarkerScreen(repository: repository)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty store explains how to start', (tester) async {
    await pumpScreen(tester);
    expect(find.text('עדיין אין סימונים'), findsOneWidget);
  });

  testWidgets('lists the marks with their place, note and tags', (
    tester,
  ) async {
    await repository.importHighlights([
      highlightFor(
        'a',
        [segmentFor(0, _line, 'אלהים')],
        text: 'אלהים',
        tags: ['עיון'],
        note: const MarkerNote(content: 'הערה חשובה', plain: 'הערה חשובה'),
      ),
      highlightFor(
        'b',
        [segmentFor(2, _line, 'הארץ')],
        text: 'הארץ',
        book: 'שמות',
        uid: 'id:2',
        colorId: 'green',
        createdAt: DateTime.utc(2026, 2, 1),
      ),
    ]);
    await pumpScreen(tester);

    expect(find.text('2 סימונים'), findsOneWidget);
    expect(find.text('אלהים'), findsOneWidget);
    expect(find.text('הערה חשובה', findRichText: true), findsOneWidget);
    expect(find.text('עיון'), findsOneWidget);
    expect(find.textContaining('שמות'), findsWidgets);

    await tester.tap(find.text('ירוק · 1'));
    await tester.pumpAndSettle();
    expect(find.text('סימון אחד מתוך 2'), findsOneWidget);
    expect(find.text('אלהים'), findsNothing);
    expect(find.text('הארץ'), findsOneWidget);
  });

  testWidgets('Ctrl+A selects the list, but not inside the search field', (
    tester,
  ) async {
    await repository.importHighlights([
      highlightFor('a', [segmentFor(0, _line, 'אלהים')], text: 'אלהים'),
      highlightFor('b', [segmentFor(1, _line, 'הארץ')], text: 'הארץ'),
    ]);
    await pumpScreen(tester);

    Future<void> selectAll() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await selectAll();
    expect(find.text('נבחרו 2 סימונים'), findsNothing);

    Focus.of(tester.element(find.text('אלהים'))).requestFocus();
    await tester.pump();
    await selectAll();
    expect(find.text('נבחרו 2 סימונים'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('נבחרו 2 סימונים'), findsNothing);
  });

  testWidgets('the filter row scrolls sideways on a phone', (tester) async {
    await repository.importHighlights([
      highlightFor('a', [segmentFor(0, _line, 'אלהים')], text: 'אלהים'),
    ]);
    tester.view
      ..physicalSize = const Size(360, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: MarkerScreen(repository: repository)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('אלהים'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('הכול'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a change made elsewhere refreshes the list', (tester) async {
    await pumpScreen(tester);
    await repository.create(
      draftFor([segmentFor(0, _line, 'השמים')], text: 'השמים'),
      colorOf('blue'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('השמים'), findsOneWidget);
    expect(find.text('סימון אחד'), findsOneWidget);
  });
}
