import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {
  @override
  final navigationHistory = LibraryNavigationHistory();
}

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _NavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _LibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class _CalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _CalendarCubit() : super(CalendarState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
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

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final (themeName, seed, brightness) in [
    ('בהיר', AppSeedColors.blue, Brightness.light),
    ('כהה', AppSeedColors.blue, Brightness.dark),
    ('לבן', AppSeedColors.white, Brightness.light),
  ]) {
    for (final width in [360.0, 1200.0]) {
      testWidgets('רענון HebrewBooks ללא תיקיות אישיות: $themeName, $width', (
        tester,
      ) async {
        final library = Library(categories: []);
        final libraryStates = StreamController<LibraryState>();
        final settingsStates = StreamController<SettingsState>();
        final libraryBloc = _LibraryBloc();
        final settingsBloc = _SettingsBloc();
        final navigationBloc = _NavigationBloc();
        final updatesBloc = _LibraryUpdateBloc();
        final calendarCubit = _CalendarCubit();
        final refreshEvents = <LibraryEvent>[];
        final foldersBloc = CustomFoldersBloc(
          addLibraryEvent: refreshEvents.add,
          loadFolders: () => [],
          syncFolders: (_, {String? onlyFolderPath}) async =>
              throw StateError('No personal folders should be synchronized'),
        );
        final initialSettings = SettingsState.initial().copyWith(
          libraryShowPreview: false,
          hebrewBooksPath: '',
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
          settingsStates.stream,
          initialState: initialSettings,
        );
        whenListen(
          navigationBloc,
          const Stream<NavigationState>.empty(),
          initialState: const NavigationState(currentScreen: Screen.library),
        );
        whenListen(
          updatesBloc,
          const Stream<LibraryUpdateState>.empty(),
          initialState: const LibraryUpdateState(),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.reset();
          DataRepository.instance.invalidateHebrewBooksCache();
          await foldersBloc.close();
          await libraryStates.close();
          await settingsStates.close();
          await libraryBloc.close();
          await settingsBloc.close();
          await navigationBloc.close();
          await updatesBloc.close();
          await calendarCubit.close();
        });
        final scheme = AppThemeData.createColorScheme(seed, brightness);
        final theme = brightness == Brightness.light
            ? AppThemeData.light(
                scheme,
                compactMenuMode: false,
                variant: AppThemeVariant.ofSeed(seed),
              )
            : AppThemeData.dark(
                scheme,
                compactMenuMode: false,
                variant: AppThemeVariant.ofSeed(seed),
              );
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('he', 'IL'),
            supportedLocales: const [Locale('he', 'IL')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Rubik'),
              primaryTextTheme: theme.primaryTextTheme.apply(
                fontFamily: 'Rubik',
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: MultiProvider(
              providers: [
                Provider<FocusRepository>.value(value: FocusRepository()),
                BlocProvider<LibraryBloc>.value(value: libraryBloc),
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
                BlocProvider<NavigationBloc>.value(value: navigationBloc),
                BlocProvider<LibraryUpdateBloc>.value(value: updatesBloc),
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

        void expectRefreshAction(bool visible) {
          final bar = tester.widget<ResponsiveActionBar>(
            find.byType(ResponsiveActionBar),
          );
          for (final actions in [bar.actions, bar.originalOrder!]) {
            expect(
              actions.where((action) => action.tooltip == 'טעינה מחדש'),
              visible ? hasLength(1) : isEmpty,
            );
          }
        }

        expectRefreshAction(false);
        for (final path in [
          'C:/missing-hebrewbooks',
          'C:/another-missing-path',
          '',
          'C:/missing-hebrewbooks',
        ]) {
          settingsStates.add(initialSettings.copyWith(hebrewBooksPath: path));
          await tester.pump();
          await tester.pump();
          expectRefreshAction(path.isNotEmpty);
        }
        DataRepository.instance.localHebrewBooksScan = Future.value((
          books: const <Book>[],
          unrecognizedPdfCount: 2,
        ));
        if (find.byTooltip('טעינה מחדש').evaluate().isEmpty) {
          await tester.tap(find.byTooltip('עוד פעולות'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('טעינה מחדש'));
        } else {
          await tester.tap(find.byTooltip('טעינה מחדש'));
        }
        await tester.pump();
        await tester.pump();
        expect(refreshEvents.whereType<RefreshLibrary>(), hasLength(1));
        expect(foldersBloc.state.error, isNull);
        libraryStates
          ..add(LibraryState(library: library, isLoading: true))
          ..add(LibraryState(library: library, currentCategory: library));
        await tester.pump();
        await tester.pump();
        expect(
          find.text(LibraryMessages.unrecognizedHebrewBooksFiles(2)),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 10));
      });
    }
  }
}
