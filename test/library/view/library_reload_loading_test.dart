// #2164: "טעינה מחדש" מציג מצב טעינה כבר בזמן סריקת התיקיות האישיות.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/models/library_navigation_history.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {
  @override
  final navigationHistory = LibraryNavigationHistory();
}

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
const _sidecarError = 'מגילה_links.json: ספר היעד "ספר חסר" לא נמצא';

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final family = entry['family'] as String;
      if (family == 'Rubik' ||
          family.contains('FluentSystemIcons') ||
          family.contains('OtzariaIcons')) {
        final loader = FontLoader(family);
        for (final font in (entry['fonts'] as List).cast<Map>()) {
          loader.addFont(rootBundle.load(font['asset'] as String));
        }
        await loader.load();
      }
    }
  });

  // סריקה שלא התחילה מהכפתור (הוספת תיקייה, ייבוא, תוסף) לא חוסמת את הספרייה.
  // תוצאות של סריקה לא קשורה נשארות ללא toast בספרייה.
  for (final (fromButton, unrecognized, scanFails, hasSidecarError) in [
    (true, 2, false, false),
    (false, 2, false, false),
    (true, 0, false, false),
    (true, 2, true, false),
    (true, 2, false, true),
    (false, 2, false, true),
  ]) {
    testWidgets(
      '${fromButton ? 'מצב הטעינה מוצג כבר בזמן סריקת התיקיות האישיות' : 'סריקה שלא התחילה מ"טעינה מחדש" אינה מציגה מצב טעינה'}'
      ' ($unrecognized קבצי היברובוקס לא מזוהים${scanFails ? ', הסריקה נכשלה' : ''}${hasSidecarError ? ', שגיאת קובץ קישורים' : ''})',
      (tester) async {
        final library = Library(categories: []);
        final releaseSync = Completer<FileSyncResult>();
        final libraryStates = StreamController<LibraryState>();
        final libraryBloc = _MockLibraryBloc();
        DataRepository.instance.localHebrewBooksScan = Future.value((
          books: const <Book>[],
          unrecognizedPdfCount: unrecognized,
        ));
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
          libraryStates.stream,
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
            hebrewBooksPath: 'C:/hebrewbooks',
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
        final capturePair =
            Platform.environment['OTZARIA_CAPTURE_UI'] == '1' &&
            fromButton &&
            hasSidecarError;
        final expectScanErrors =
            Platform.environment['OTZARIA_EXPECT_SCAN_ERRORS'] != '0';
        addTearDown(() async {
          if (!releaseSync.isCompleted) {
            releaseSync.complete(const FileSyncResult());
          }
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.reset();
          DataRepository.instance.invalidateHebrewBooksCache();
          await foldersBloc.close();
          await libraryStates.close();
          await libraryBloc.close();
          await settingsBloc.close();
          await navigationBloc.close();
          await libraryUpdateBloc.close();
          await calendarCubit.close();
        });

        final theme =
            AppThemeData.light(
              AppThemeData.createColorScheme(
                AppSeedColors.blue,
                Brightness.light,
              ),
              compactMenuMode: false,
              variant: AppThemeVariant.ofSeed(AppSeedColors.blue),
            ).copyWith(
              textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Rubik'),
              primaryTextTheme: ThemeData.light().primaryTextTheme.apply(
                fontFamily: 'Rubik',
              ),
            );
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('he', 'IL'),
            supportedLocales: const [Locale('he', 'IL')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme,
            builder: (context, child) => RepaintBoundary(
              key: const ValueKey('library-reload-capture-root'),
              child: child!,
            ),
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
        expect(
          Directionality.of(tester.element(find.byType(LibraryBrowser))),
          TextDirection.rtl,
        );
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

        if (scanFails) {
          releaseSync.completeError(Exception('scan failed'));
        } else {
          releaseSync.complete(
            FileSyncResult(
              errors: hasSidecarError ? const [_sidecarError] : const [],
            ),
          );
        }
        await tester.pump();
        await tester.pump();
        expect(_loadingOverlay, findsNothing);
        expect(
          find.textContaining('מגילה_links.json'),
          fromButton && hasSidecarError && expectScanErrors
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          find.textContaining('ספר היעד "ספר חסר" לא נמצא'),
          fromButton && hasSidecarError && expectScanErrors
              ? findsOneWidget
              : findsNothing,
        );
        if (scanFails) {
          expect(
            find.textContaining('סנכרון התיקיות האישיות נכשל'),
            fromButton ? findsOneWidget : findsNothing,
          );
          expect(find.textContaining('scan failed'), findsNothing);
        }

        // #2964: קבצים לא מזוהים בתיקיית היברובוקס מדווחים רק אחרי "טעינה מחדש".
        libraryStates
          ..add(LibraryState(library: library, isLoading: true))
          ..add(LibraryState(library: library, currentCategory: library));
        await tester.pump();
        await tester.pump();
        expect(
          find.text(LibraryMessages.unrecognizedHebrewBooksFiles(unrecognized)),
          fromButton &&
                  unrecognized > 0 &&
                  !scanFails &&
                  (!hasSidecarError || !expectScanErrors)
              ? findsOneWidget
              : findsNothing,
        );
        if (capturePair) {
          await tester.pump(const Duration(milliseconds: 200));
          await expectLater(
            find.byKey(const ValueKey('library-reload-capture-root')),
            matchesGoldenFile('library_reload_sidecar_error_after.png'),
          );
        }
        await tester.pump(const Duration(seconds: 10));
      },
    );
  }
}
