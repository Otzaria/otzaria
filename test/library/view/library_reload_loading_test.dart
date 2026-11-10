// #2164: "טעינה מחדש" מציג מצב טעינה כבר בזמן סריקת התיקיות האישיות.
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
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

final _loadingOverlay = find.text('טוען את הספרייה');

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  // סריקה שלא התחילה מהכפתור (הוספת תיקייה, ייבוא, תוסף) לא חוסמת את הספרייה.
  for (final fromButton in [true, false]) {
    testWidgets(
      fromButton
          ? 'מצב הטעינה מוצג כבר בזמן סריקת התיקיות האישיות'
          : 'סריקה שלא התחילה מ"טעינה מחדש" אינה מציגה מצב טעינה',
      (tester) async {
        final library = Library(categories: []);
        final releaseSync = Completer<FileSyncResult>();
        final libraryBloc = _MockLibraryBloc();
        final settingsBloc = _MockSettingsBloc();
        final navigationBloc = _MockNavigationBloc();
        final libraryUpdateBloc = _MockLibraryUpdateBloc();
        final calendarCubit = _StubCalendarCubit(CalendarState.initial());
        final foldersBloc = CustomFoldersBloc(
          addLibraryEvent: (_) {},
          loadFolders: () => [
            CustomFolder(path: 'C:/a', addedAt: DateTime(2026)),
          ],
          syncFolders: (folders, {String? onlyFolderPath}) =>
              releaseSync.future,
        );

        whenListen(
          libraryBloc,
          const Stream<LibraryState>.empty(),
          initialState: LibraryState(
            library: library,
            currentCategory: library,
          ),
        );
        whenListen(
          settingsBloc,
          const Stream<SettingsState>.empty(),
          initialState: SettingsState.initial().copyWith(
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
        tester.view.physicalSize = const Size(1200, 900);
        addTearDown(() async {
          if (!releaseSync.isCompleted) {
            releaseSync.complete(const FileSyncResult());
          }
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.reset();
          await foldersBloc.close();
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
                BlocProvider<CustomFoldersBloc>.value(value: foldersBloc),
              ],
              child: const Scaffold(body: LibraryBrowser()),
            ),
          ),
        );
        await tester.pump();
        tester.takeException();
        expect(_loadingOverlay, findsNothing);

        if (fromButton) {
          await tester.tap(find.byTooltip('טעינה מחדש'));
        } else {
          foldersBloc.add(const RescanCustomFolders());
        }
        await tester.pump();
        await tester.pump();

        expect(foldersBloc.state.isSyncing, isTrue);
        expect(_loadingOverlay, fromButton ? findsOneWidget : findsNothing);

        releaseSync.complete(const FileSyncResult());
        await tester.pump();
        await tester.pump();
        expect(_loadingOverlay, findsNothing);
      },
    );
  }
}
