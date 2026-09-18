import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/bloc/attached_libraries_bloc.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/view/attached_libraries_panel.dart';
import 'package:otzaria/library/bloc/library_event.dart';

import '../helpers/memory_settings_cache.dart';

/// Fake בזיכרון — IO אמיתי בתוך testWidgets נתקע באזור ה-FakeAsync;
/// הלוגיקה האמיתית מכוסה ב-attached_libraries_repository_test.
class _FakeRepository extends AttachedLibrariesRepository {
  _FakeRepository(this.items) : super(copyByDefault: false);

  List<AttachedLibrary> items;
  final removed = <AttachedLibrary>[];
  final _controller = StreamController<void>.broadcast();

  @override
  List<AttachedLibrary> get libraries => items;

  @override
  List<String> get folders => const [r'D:\מסדים'];

  @override
  Stream<void> get changes => _controller.stream;

  @override
  Future<void> remove(AttachedLibrary library, {bool deleteCopy = true}) async {
    removed.add(library);
    items = [
      for (final other in items)
        if (other.path != library.path) other,
    ];
    _controller.add(null);
  }
}

AttachedLibrary _library(
  String name, {
  AttachedLibraryMode mode = AttachedLibraryMode.link,
  AttachedLibraryStatus status = AttachedLibraryStatus.ok,
  bool hidden = false,
}) => AttachedLibrary(
  slug: name,
  displayName: name,
  path: 'C:/dbs/$name.db',
  mode: mode,
  status: status,
  hidden: hidden,
  bookCount: 12,
  capabilities: const {AttachedLibraryCapability.toc},
  addedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<LibraryEvent> libraryEvents;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() => libraryEvents = []);

  Future<AttachedLibrariesBloc> pumpPanel(
    WidgetTester tester,
    _FakeRepository repository,
  ) async {
    final bloc = AttachedLibrariesBloc(
      addLibraryEvent: libraryEvents.add,
      repository: repository,
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<AttachedLibrariesBloc>.value(
            value: bloc,
            child: const SingleChildScrollView(
              child: AttachedLibrariesPanel(supportsLinking: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return bloc;
  }

  testWidgets('מציג מסדים עם מצב, מספר ספרים ויכולות, ותיקיית מסדים', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      _FakeRepository([
        _library('ראשון'),
        _library('נשלף', status: AttachedLibraryStatus.unreachable),
        _library('מוסתר', hidden: true),
      ]),
    );

    expect(find.text('מסדי ספרים אישיים'), findsOneWidget);
    expect(find.text('3 מסדים'), findsOneWidget);
    expect(find.text('ראשון  •  12 ספרים'), findsOneWidget);
    expect(find.text('מוסתר  •  12 ספרים  •  מוסתר'), findsOneWidget);
    expect(find.text('זמין'), findsNWidgets(2));
    expect(find.text('לא זמין'), findsOneWidget);
    expect(find.text('תוכן עניינים'), findsNWidgets(2));
    expect(find.text('תיקיית מסדים'), findsOneWidget);
    expect(find.text('ייבא קובץ מסד'), findsOneWidget);
    expect(find.text('הוסף תיקיית מסדים'), findsOneWidget);
    // מסד לא נגיש אינו מציע בחירת מיקום בעץ.
    expect(find.text('בנפרד'), findsNWidgets(2));
  });

  testWidgets('בלי קישור (מובייל) — אין הוספת תיקייה', (tester) async {
    final bloc = AttachedLibrariesBloc(
      addLibraryEvent: libraryEvents.add,
      repository: _FakeRepository(const []),
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<AttachedLibrariesBloc>.value(
            value: bloc,
            child: const SingleChildScrollView(
              child: AttachedLibrariesPanel(supportsLinking: false),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('לא צורפו מסדים'), findsOneWidget);
    expect(find.text('הוסף תיקיית מסדים'), findsNothing);
  });

  testWidgets('הסרת מסד מקושר: אזהרה שהקובץ לא יימחק, ורענון הספרייה', (
    tester,
  ) async {
    final repository = _FakeRepository([_library('ראשון')]);
    await pumpPanel(tester, repository);

    await tester.tap(find.byTooltip('אפשרויות').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('הסר מסד'));
    await tester.pumpAndSettle();

    expect(
      find.text('המסד "ראשון" יוסר מהספרייה. הקובץ עצמו לא יימחק.'),
      findsOneWidget,
    );
    await tester.tap(find.text('הסר'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.removed.single.displayName, 'ראשון');
    expect(find.text('ראשון  •  12 ספרים'), findsNothing);
    expect(
      libraryEvents.whereType<RefreshLibrary>().map((e) => e.source),
      contains(RefreshSource.attachedLibraries),
    );
  });

  testWidgets('הסרת עותק מזהירה שהעותק יימחק; ביטול לא מסיר', (
    tester,
  ) async {
    final repository = _FakeRepository([
      _library('עותק', mode: AttachedLibraryMode.copy),
    ]);
    await pumpPanel(tester, repository);

    await tester.tap(find.byTooltip('אפשרויות').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('הסר מסד'));
    await tester.pumpAndSettle();

    expect(
      find.text('המסד "עותק" יוסר מהספרייה, והעותק שלו בתוכנה יימחק.'),
      findsOneWidget,
    );
    expect(find.text('שים לב שלא ניתן לבטל פעולה זו'), findsOneWidget);
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(repository.removed, isEmpty);
  });
}
