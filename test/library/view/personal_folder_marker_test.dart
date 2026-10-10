// תיקייה אישית בספרייה: אותו סימון ואותה מחיקה שיש לספר אישי (issue #1998).
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:provider/provider.dart';

import '../../helpers/semantics_update_recorder.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Category _category(
  String title, {
  List<Category> subCategories = const [],
  List<Book> books = const [],
}) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 999,
    subCategories: List.of(subCategories),
    books: List.of(books),
    parent: null,
  );
  for (final sub in category.subCategories) {
    sub.parent = category;
  }
  return category;
}

Library _library(List<Category> categories) {
  final library = Library(categories: categories);
  for (final sub in library.subCategories) {
    sub.parent = library;
  }
  return library;
}

TextBook _userBook(String title) =>
    TextBook(title: title, source: BookSource.user, categoryId: 7);

TextBook _officialBook(String title) => TextBook(title: title, categoryId: 1);

TextBook _attachedBook(String title) =>
    TextBook(title: title, source: BookSource.attached('beit'), categoryId: 3);

CustomFolder _folder(String path) =>
    CustomFolder(path: path, addedAt: DateTime(2026));

/// עץ במצב רגיל: התיקייה האישית יושבת תחת "ספרים אישיים".
({Library library, Category folder}) _personalTree({
  String folderTitle = 'מסמכים',
}) {
  final folder = _category(folderTitle, books: [_userBook('חידושים')]);
  final library = _library([
    _category('תנ"ך', books: [_officialBook('בראשית')]),
    _category('ספרים אישיים', subCategories: [folder]),
  ]);
  return (library: library, folder: folder);
}

class _FoldersHarness {
  _FoldersHarness(List<CustomFolder> folders) : _folders = List.of(folders) {
    bloc = CustomFoldersBloc(
      addLibraryEvent: libraryEvents.add,
      loadFolders: () => _folders,
      saveFolders: (folders) async {
        saved.add(folders);
        _folders = folders;
      },
      deleteFolderFromDb: (folder) async => deletedFromDb.add(folder),
    )..add(const LoadCustomFolders());
  }

  List<CustomFolder> _folders;
  late final CustomFoldersBloc bloc;
  final saved = <List<CustomFolder>>[];
  final deletedFromDb = <CustomFolder>[];
  final libraryEvents = <LibraryEvent>[];
}

Future<void> _pumpGridItem(
  WidgetTester tester,
  Category category, {
  CustomFoldersBloc? bloc,
}) async {
  Widget child = MaterialApp(
    navigatorKey: navigatorKey,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        child: Center(
          child: SizedBox(
            width: 280,
            height: 110,
            child: CategoryGridItem(
              category: category,
              onCategoryClickCallback: () {},
            ),
          ),
        ),
      ),
    ),
  );
  if (bloc != null) {
    child = BlocProvider<CustomFoldersBloc>.value(value: bloc, child: child);
  }
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

Finder _badgeIcon(IconData icon) => find.byWidgetPredicate(
  (widget) => widget is Icon && widget.icon == icon && widget.size == 8,
);

void main() {
  SemanticsRecordingBinding.ensure();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('תיקייה אישית: סימון ומחיקה כמו לספר אישי (issue #1998)', () {
    group('Category.personalSource', () {
      test('תיקייה שכל ספריה אישיים, גם בתת-תיקייה, היא אישית', () {
        final folder = _category(
          'מסמכים',
          books: [_userBook('א')],
          subCategories: [
            _category('שיעורים', books: [_userBook('ב')]),
          ],
        );
        expect(folder.personalSource, BookSource.user);
      });

      test('תיקייה רשמית, מעורבת או ריקה אינה אישית', () {
        expect(
          _category('תנ"ך', books: [_officialBook('בראשית')]).personalSource,
          isNull,
        );
        // מצב מיזוג: תיקייה אישית שהתמזגה לתיקייה רשמית בשם זהה.
        expect(
          _category(
            'הלכה',
            books: [_userBook('חידושים')],
            subCategories: [
              _category('שולחן ערוך', books: [_officialBook('אורח חיים')]),
            ],
          ).personalSource,
          isNull,
        );
        expect(_category('ריקה').personalSource, isNull);
      });

      test('תיקייה ממסד מצורף מסומנת במקור המסד', () {
        final source = _category(
          'בית המדרש',
          books: [_attachedBook('קובץ')],
        ).personalSource;
        expect(source?.isAttached, isTrue);
      });
    });

    group('סימון בכרטיס התיקייה', () {
      testWidgets('תיקייה אישית מקבלת את תג "אישי" של הספר', (tester) async {
        final tree = _personalTree();
        // לכרטיס יש גם Tooltip תיאור — ריחוף על התג לא ישלח צומת נגישות יתום.
        tree.folder.description = 'תיאור';
        final handle = tester.ensureSemantics();
        SemanticsRecordingBinding.recorder.reset();
        await _pumpGridItem(
          tester,
          tree.folder,
          bloc: _FoldersHarness(const []).bloc,
        );

        expect(_badgeIcon(FluentIcons.person_24_regular), findsOneWidget);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.byTooltip('תיקייה אישית')));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('תיקייה אישית'), findsOneWidget);
        expect(SemanticsRecordingBinding.recorder.violations, isEmpty);
        handle.dispose();
      });

      testWidgets('תיקייה רשמית ותיקייה מעורבת אינן מסומנות', (tester) async {
        final official = _category('תנ"ך', books: [_officialBook('בראשית')]);
        await _pumpGridItem(tester, official);
        expect(find.byTooltip('תיקייה אישית'), findsNothing);
        expect(_badgeIcon(FluentIcons.person_24_regular), findsNothing);

        final mixed = _category(
          'הלכה',
          books: [_userBook('חידושים'), _officialBook('משנה ברורה')],
        );
        await _pumpGridItem(tester, mixed);
        expect(find.byTooltip('תיקייה אישית'), findsNothing);
      });

      testWidgets('תיקייה ממסד מצורף מקבלת את תג המסד של הספר', (tester) async {
        final attached = _category('בית המדרש', books: [_attachedBook('קובץ')]);
        await _pumpGridItem(tester, attached);

        expect(find.byTooltip('ממסד ספרים אישי'), findsOneWidget);
        expect(_badgeIcon(FluentIcons.database_24_regular), findsOneWidget);
      });
    });

    group('מחיקה מהספרייה', () {
      tearDown(UiSnack.hide);
      for (final duringDialog in [false, true]) {
        testWidgets(
          duringDialog
              ? 'סריקה שמתחילה בזמן הדיאלוג מונעת הסרה באישור'
              : 'סריקה פעילה משביתה את תפריט ההסרה',
          (tester) async {
            final folder = _folder('/personal/מסמכים');
            final sync = Completer<FileSyncResult>();
            var deletes = 0;
            var saves = 0;
            final bloc = CustomFoldersBloc(
              addLibraryEvent: (_) {},
              loadFolders: () => [folder],
              saveFolders: (_) async => saves++,
              syncFolders: (_, {String? onlyFolderPath}) => sync.future,
              deleteFolderFromDb: (_) async => deletes++,
            )..add(const LoadCustomFolders());
            addTearDown(() async {
              if (!sync.isCompleted) sync.complete(const FileSyncResult());
              UiSnack.hide();
              await tester.pumpAndSettle();
              await tester.runAsync(bloc.close);
            });
            await _pumpGridItem(tester, _personalTree().folder, bloc: bloc);
            if (duringDialog) {
              await tester.tap(find.byTooltip('אפשרויות נוספות'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('מחק מהספרייה'));
              await tester.pumpAndSettle();
            }
            bloc.add(const RescanCustomFolders());
            await tester.pumpAndSettle();
            if (duringDialog) {
              await tester.tap(find.text('מחק'));
            } else {
              await tester.tap(find.byTooltip('אפשרויות נוספות'));
            }
            await tester.pumpAndSettle();
            expect(find.text('מחק מהספרייה'), findsNothing);
            if (duringDialog) {
              expect(
                find.text(LibraryMessages.folderRemovalBusy),
                findsOneWidget,
              );
            }
            expect(saves, 0);
            expect(deletes, 0);
            UiSnack.hide();
            await tester.pumpAndSettle();
          },
        );
      }

      testWidgets('תור מסד הנתונים משבית את תפריט ההסרה', (tester) async {
        final harness = _FoldersHarness([_folder('/personal/מסמכים')]);
        await _pumpGridItem(tester, _personalTree().folder, bloc: harness.bloc);
        final busyCount = DatabaseLibraryProvider.operationQueue.busyCount;
        busyCount.value++;
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('אפשרויות נוספות'));
        await tester.pumpAndSettle();
        expect(find.text('מחק מהספרייה'), findsNothing);
        busyCount.value--;
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(harness.bloc.close);
      });

      testWidgets('סיום סריקה אחרת לא מסתיר כשל הסרה מאוחר', (tester) async {
        var folders = [_folder('/personal/מסמכים')];
        final deletion = Completer<void>();
        final sync = Completer<FileSyncResult>();
        final bloc = CustomFoldersBloc(
          addLibraryEvent: (_) {},
          loadFolders: () => folders,
          saveFolders: (saved) async => folders = saved,
          syncFolders: (_, {String? onlyFolderPath}) => sync.future,
          deleteFolderFromDb: (_) => deletion.future,
        )..add(const LoadCustomFolders());
        addTearDown(() async {
          if (!sync.isCompleted) sync.complete(const FileSyncResult());
          if (!deletion.isCompleted) deletion.complete();
          UiSnack.hide();
          await tester.pumpAndSettle();
          await tester.runAsync(bloc.close);
        });
        await _pumpGridItem(tester, _personalTree().folder, bloc: bloc);
        await tester.tap(find.byTooltip('אפשרויות נוספות'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('מחק מהספרייה'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('מחק'));
        await tester.pumpAndSettle();
        bloc.add(const RescanCustomFolders());
        await tester.pump();
        sync.complete(const FileSyncResult(addedBooks: 1));
        await tester.pumpAndSettle();
        expect(find.text('התיקייה "מסמכים" הוסרה מהספרייה'), findsNothing);
        deletion.completeError(StateError('delete-db-failed'));
        await tester.pumpAndSettle();
        expect(find.textContaining('delete-db-failed'), findsOneWidget);
        expect(find.text('התיקייה "מסמכים" הוסרה מהספרייה'), findsNothing);
        UiSnack.hide();
        await tester.pumpAndSettle();
      });

      testWidgets(
        'תיקייה אישית מוגדרת: "מחק מהספרייה" עם אישור מסיר אותה דרך שירות התיקיות',
        (tester) async {
          final tree = _personalTree();
          final docs = _folder(r'C:\Users\me\מסמכים');
          final other = _folder(r'C:\Users\me\הורדות');
          final harness = _FoldersHarness([docs, other]);
          await _pumpGridItem(tester, tree.folder, bloc: harness.bloc);

          await tester.tap(find.byTooltip('אפשרויות נוספות'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('מחק מהספרייה'));
          await tester.pumpAndSettle();

          expect(find.text('למחוק את התיקייה?'), findsOneWidget);
          expect(harness.deletedFromDb, isEmpty);

          await tester.tap(find.text('מחק'));
          await tester.pumpAndSettle();

          expect(harness.deletedFromDb, [docs]);
          expect(harness.saved.last, [other]);
          expect(harness.libraryEvents.whereType<RefreshLibrary>(), isNotEmpty);
          UiSnack.hide();
          await tester.pumpAndSettle();
        },
      );

      testWidgets('ביטול בדיאלוג אינו מוחק דבר', (tester) async {
        final tree = _personalTree();
        final harness = _FoldersHarness([_folder(r'C:\Users\me\מסמכים')]);
        await _pumpGridItem(tester, tree.folder, bloc: harness.bloc);

        await tester.tap(find.byTooltip('אפשרויות נוספות'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('מחק מהספרייה'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ביטול'));
        await tester.pumpAndSettle();

        expect(harness.deletedFromDb, isEmpty);
        expect(harness.saved, isEmpty);
      });

      testWidgets('אין פעולת מחיקה לתיקייה רשמית', (tester) async {
        final official = _category('תנ"ך', books: [_officialBook('בראשית')]);
        _library([official]);
        await _pumpGridItem(tester, official);

        expect(find.byTooltip('אפשרויות נוספות'), findsNothing);
      });

      testWidgets(
        'אין פעולת מחיקה לתיקייה אישית שאינה תיקייה מוגדרת אחת בדיוק',
        (tester) async {
          // תת-תיקייה, ותיקייה ממוזגת בשורש — אינן תיקייה שהמשתמש הוסיף.
          final sub = _category('שיעורים', books: [_userBook('ב')]);
          final folder = _category(
            'מסמכים',
            books: [_userBook('א')],
            subCategories: [sub],
          );
          final merged = _category('חידושי תורה', books: [_userBook('ג')]);
          final attachedRoot = _category(
            'בית המדרש',
            books: [_attachedBook('קובץ')],
          );
          final unknown = _category('לא מוגדרת', books: [_userBook('ד')]);
          _library([
            merged,
            _category(
              'ספרים אישיים',
              subCategories: [folder, attachedRoot, unknown],
            ),
          ]);
          final harness = _FoldersHarness([
            _folder(r'C:\a\מסמכים'),
            _folder(r'C:\a\שיעורים'),
            _folder(r'C:\a\חידושי תורה'),
            _folder(r'C:\a\בית המדרש'),
          ]);

          for (final category in [sub, merged, attachedRoot, unknown]) {
            await _pumpGridItem(tester, category, bloc: harness.bloc);
            expect(
              find.byTooltip('אפשרויות נוספות'),
              findsNothing,
              reason: category.title,
            );
          }

          // שתי תיקיות באותו שם מוצגות כקטגוריה אחת — לא ברור מה למחוק.
          final twins = _FoldersHarness([
            _folder(r'C:\a\מסמכים'),
            _folder(r'D:\b\מסמכים'),
          ]);
          await _pumpGridItem(tester, folder, bloc: twins.bloc);
          expect(find.byTooltip('אפשרויות נוספות'), findsNothing);
        },
      );

      testWidgets('גם בתצוגת הרשימה שורת התיקייה האישית מציעה מחיקה', (
        tester,
      ) async {
        final tree = _personalTree();
        final harness = _FoldersHarness([_folder(r'C:\Users\me\מסמכים')]);
        final libraryBloc = _MockLibraryBloc();
        final settingsBloc = _MockSettingsBloc();
        final navigationBloc = _MockNavigationBloc();
        final libraryUpdateBloc = _MockLibraryUpdateBloc();
        final calendarCubit = _StubCalendarCubit(CalendarState.initial());
        final personalRoot = tree.library.subCategories.last;

        whenListen(
          libraryBloc,
          const Stream<LibraryState>.empty(),
          initialState: LibraryState(
            library: tree.library,
            currentCategory: personalRoot,
          ),
        );
        whenListen(
          settingsBloc,
          const Stream<SettingsState>.empty(),
          initialState: SettingsState.initial().copyWith(
            libraryViewMode: 'list',
            libraryShowPreview: false,
          ),
        );
        whenListen(
          navigationBloc,
          const Stream<NavigationState>.empty(),
          initialState: const NavigationState(currentScreen: Screen.library),
        );
        whenListen(
          libraryUpdateBloc,
          const Stream<LibraryUpdateState>.empty(),
          initialState: const LibraryUpdateState(),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 700);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.reset();
          await libraryBloc.close();
          await settingsBloc.close();
          await navigationBloc.close();
          await libraryUpdateBloc.close();
          await calendarCubit.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('he', 'IL'),
            home: MultiProvider(
              providers: [
                Provider<FocusRepository>.value(value: FocusRepository()),
                BlocProvider<LibraryBloc>.value(value: libraryBloc),
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
                BlocProvider<NavigationBloc>.value(value: navigationBloc),
                BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdateBloc),
                BlocProvider<CalendarCubit>.value(value: calendarCubit),
                BlocProvider<CustomFoldersBloc>.value(value: harness.bloc),
              ],
              child: const Scaffold(body: LibraryBrowser()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('מסמכים'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(CategoryActionsMenuButton),
            matching: find.byTooltip('אפשרויות נוספות'),
          ),
          findsOneWidget,
        );
      });
    });
  });
}
