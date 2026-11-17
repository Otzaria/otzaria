import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

/// #3852: מחיקת היקף שמור מציגה הודעה עם "בטל", שמחזירה אותו למקומו.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final change in [
    'none',
    'update',
    'add',
    'remove',
    'same name',
    'unmount',
    'remove preceding',
  ]) {
    testWidgets('מחיקת היקף שמור ניתנת לביטול: $change', (tester) async {
      await SearchScopePreferences.addSavedScope('ראשון', {'/א'});
      await SearchScopePreferences.addSavedScope('שני', {'/ב'});
      final deletedName = change == 'remove preceding' ? 'שני' : 'ראשון';
      final libraryBloc = _MockLibraryBloc();
      whenListen(
        libraryBloc,
        const Stream<LibraryState>.empty(),
        initialState: LibraryState(library: Library(categories: [])),
      );
      addTearDown(() async {
        UiSnack.hide();
        await tester.binding.setSurfaceSize(null);
        await libraryBloc.close();
      });
      await tester.binding.setSurfaceSize(const Size(600, 900));
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: BlocProvider<LibraryBloc>.value(
            value: libraryBloc,
            child: Scaffold(
              body: SearchScopeMenuButton(
                selected: const {'/'},
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final row = find
          .ancestor(
            of: find.descendant(
              of: find.byType(ListView),
              matching: find.text(deletedName),
            ),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.tap(
        find.descendant(of: row, matching: find.byType(IconButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        SearchScopePreferences.loadSavedScopes().map((s) => s.name),
        change == 'remove preceding' ? ['ראשון'] : ['שני'],
      );
      expect(find.text('בטל'), findsOneWidget);

      switch (change) {
        case 'update':
          await SearchScopePreferences.addSavedScope('שני', {'/חדש'});
        case 'add':
          await SearchScopePreferences.addSavedScope('שלישי', {'/ג'});
        case 'remove':
          await SearchScopePreferences.removeSavedScope('שני');
        case 'same name':
          await SearchScopePreferences.addSavedScope('ראשון', {'/חדש'});
        case 'remove preceding':
          await SearchScopePreferences.removeSavedScope('ראשון');
        case 'unmount':
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigatorKey,
              home: const Scaffold(),
            ),
          );
          await tester.pump();
        default:
          break;
      }
      await tester.tap(find.text('בטל'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        SearchScopePreferences.loadSavedScopes().map((s) => s.name),
        switch (change) {
          'add' => ['ראשון', 'שני', 'שלישי'],
          'remove' => ['ראשון'],
          'remove preceding' => ['שני'],
          'same name' => ['שני', 'ראשון'],
          _ => ['ראשון', 'שני'],
        },
      );
      final scopes = SearchScopePreferences.loadSavedScopes();
      expect(
        scopes.singleWhere((s) => s.name == deletedName).facets,
        switch (change) {
          'same name' => {'/חדש'},
          'remove preceding' => {'/ב'},
          _ => {'/א'},
        },
      );
      if (change == 'update') {
        expect(scopes.singleWhere((s) => s.name == 'שני').facets, {'/חדש'});
      }
      if (change == 'add') expect(scopes.last.facets, {'/ג'});
    }, skip: !engineReady);
  }
}
