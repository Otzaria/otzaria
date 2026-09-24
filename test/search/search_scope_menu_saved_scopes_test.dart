import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import '../support/search_engine_test_init.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

Library _buildLibrary() {
  final torah = Category(
    title: 'תורה',
    description: '',
    shortDescription: '',
    order: 10,
    subCategories: [],
    books: [TextBook(title: 'בראשית', categoryPath: '/תנ״ך/תורה')],
    parent: null,
  );
  final library = Library(categories: [torah]);
  torah.parent = library;
  return library;
}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Set<String> selection;

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  Future<void> pumpMenu(WidgetTester tester, Set<String> selected) async {
    final libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(library: _buildLibrary()),
    );
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await libraryBloc.close();
    });

    selection = selected;
    await tester.binding.setSurfaceSize(const Size(600, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: BlocProvider<LibraryBloc>.value(
          value: libraryBloc,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SearchScopeMenuButton(
                selected: selection,
                onChanged: (next) => setState(() => selection = next),
              ),
            ),
          ),
        ),
      ),
    );
    await openMenu(tester);
  }

  Finder rowOf(String label) => find
      .ancestor(
        of: find.descendant(
          of: find.byType(ListView),
          matching: find.text(label),
        ),
        matching: find.byType(InkWell),
      )
      .first;

  group('היקפים שמורים בתפריט ההיקף (issue #1083)', () {
    testWidgets('בלי צמצום ובלי היקפים — הקטע לא מוצג', (tester) async {
      await pumpMenu(tester, {'/'});

      expect(find.text('היקפים שמורים'), findsNothing);
      expect(find.text('שמור את הבחירה הנוכחית…'), findsNothing);
    });

    testWidgets('שמירת הבחירה הנוכחית בשם ומופעה כמסומנת', (tester) async {
      await pumpMenu(tester, {'/תנ״ך/תורה', '/era/ראשונים'});

      await tester.tap(find.text('שמור את הבחירה הנוכחית…'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'המאגר שלי',
      );
      await tester.tap(find.text('שמור'));
      await tester.pumpAndSettle();

      final saved = SearchScopePreferences.loadSavedScopes();
      expect(saved.single.name, 'המאגר שלי');
      expect(saved.single.facets, {'/תנ״ך/תורה', '/era/ראשונים'});

      await openMenu(tester);
      final checkbox = tester.widget<Checkbox>(
        find.descendant(
          of: rowOf('המאגר שלי'),
          matching: find.byType(Checkbox),
        ),
      );
      expect(checkbox.value, isTrue);
    });

    testWidgets('לחיצה על היקף שמור מחילה אותו, ומחיקה מסירה', (tester) async {
      await SearchScopePreferences.addSavedScope('מאגר', {
        '/ראשונים',
        '/קבלה',
      });
      await pumpMenu(tester, {'/'});

      await tester.tap(rowOf('מאגר'));
      await tester.pump();
      expect(selection, {'/ראשונים', '/קבלה'});

      await tester.tap(
        find.descendant(of: rowOf('מאגר'), matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();

      expect(SearchScopePreferences.loadSavedScopes(), isEmpty);
      expect(find.text('מאגר'), findsNothing);
      // המחיקה אינה משנה את הבחירה שכבר הוחלה.
      expect(selection, {'/ראשונים', '/קבלה'});
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(TextField).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    return value is T ? value : defaultValue;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}
