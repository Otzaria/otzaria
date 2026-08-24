import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import '../helpers/memory_settings_cache.dart';
import '../unit/mocks/mock_settings_repository.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsBloc', () {
    late SettingsBloc settingsBloc;
    late MockSettingsRepository mockRepository;

    setUp(() {
      mockRepository = MockSettingsRepository();
      settingsBloc = SettingsBloc(repository: mockRepository);
    });

    tearDown(() {
      settingsBloc.close();
    });

    test('initial state is correct', () {
      expect(settingsBloc.state, equals(SettingsState.initial()));
    });

    group('LoadSettings', () {
      final mockSettings = {
        'isDarkMode': true,
        'followSystemTheme': false,
        'seedColor': Colors.blue,
        'darkSeedColor': const Color(0xFFCE93D8),
        'textMaxWidth': 800.0,
        'fontSize': 18.0,
        'fontFamily': 'Rubik',
        'commentatorsFontFamily': 'NotoRashiHebrew',
        // issue #849 — נטען בעליית התוכנה כדי שגופן מערכת לא יתאפס ל-fallback.
        'pageShapeBottomFont': 'NotoSerifHebrew',
        'commentatorsFontSize': 22.0,
        'lineHeight': 1.5,
        'showOtzarHachochma': true,
        'showHebrewBooks': true,
        'showExternalBooks': true,
        'showTeamim': false,
        'replaceHolyNames': false,
        'autoUpdateIndex': false,
        'defaultRemoveNikud': true,
        'removeNikudFromTanach': true,
        'defaultRemovePunctuation': true,
        'defaultContinuousReadingMode': true,
        'defaultSidebarOpen': true,
        'defaultCommentaryOpen': true,
        'pinSidebar': true,
        'sidebarWidth': 300.0,
        'facetFilteringWidth': 235.0,
        'commentaryPaneWidth': 400.0,
        'copyWithHeaders': 'none',
        'copyHeaderFormat': 'same_line_after_brackets',
        'isFullscreen': false,
        'libraryViewMode': 'grid',
        'libraryShowPreview': true,
        'searchShowPreview': true,
        'enablePerBookSettings': true,
        'pdfBookViewByDefault': false,
        'shortcuts': <String, String>{},
        'isOfflineMode': false,
        'softwareAndBookUpdatesEnabled': true,
        'personalNotesCollapsedByDefault': true,
      };

      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when LoadSettings is added',
        build: () {
          when(
            mockRepository.loadSettings(),
          ).thenAnswer((_) async => mockSettings);
          when(mockRepository.hasProtectedModePassword()).thenReturn(false);
          return settingsBloc;
        },
        act: (bloc) => bloc.add(LoadSettings()),
        expect: () => [
          SettingsState(
            isDarkMode: mockSettings['isDarkMode'] as bool,
            followSystemTheme:
                mockSettings['followSystemTheme'] as bool? ?? false,
            seedColor: mockSettings['seedColor'] as Color,
            darkSeedColor: mockSettings['darkSeedColor'] as Color,
            textMaxWidth: mockSettings['textMaxWidth'] as double,
            fontSize: mockSettings['fontSize'] as double,
            fontFamily: mockSettings['fontFamily'] as String,
            commentatorsFontFamily:
                mockSettings['commentatorsFontFamily'] as String? ??
                'NotoRashiHebrew',
            commentatorsFontSize:
                mockSettings['commentatorsFontSize'] as double? ?? 22.0,
            lineHeight: mockSettings['lineHeight'] as double? ?? 1.5,
            showOtzarHachochma: mockSettings['showOtzarHachochma'] as bool,
            showHebrewBooks: mockSettings['showHebrewBooks'] as bool,
            showExternalBooks: mockSettings['showExternalBooks'] as bool,
            showTeamim: mockSettings['showTeamim'] as bool,
            replaceHolyNames: mockSettings['replaceHolyNames'] as bool,
            autoUpdateIndex: mockSettings['autoUpdateIndex'] as bool,
            defaultRemoveNikud: mockSettings['defaultRemoveNikud'] as bool,
            removeNikudFromTanach:
                mockSettings['removeNikudFromTanach'] as bool,
            defaultRemovePunctuation:
                mockSettings['defaultRemovePunctuation'] as bool,
            defaultContinuousReadingMode:
                mockSettings['defaultContinuousReadingMode'] as bool,
            defaultSidebarOpen: mockSettings['defaultSidebarOpen'] as bool,
            defaultCommentaryOpen:
                mockSettings['defaultCommentaryOpen'] as bool,
            pinSidebar: mockSettings['pinSidebar'] as bool,
            sidebarWidth: mockSettings['sidebarWidth'] as double,
            facetFilteringWidth: mockSettings['facetFilteringWidth'] as double,
            externalResultsFirst:
                mockSettings['externalResultsFirst'] as bool? ?? false,
            commentaryPaneWidth: mockSettings['commentaryPaneWidth'] as double,
            copyWithHeaders: mockSettings['copyWithHeaders'] as String,
            copyHeaderFormat: mockSettings['copyHeaderFormat'] as String,
            isFullscreen: mockSettings['isFullscreen'] as bool,
            libraryViewMode: mockSettings['libraryViewMode'] as String,
            libraryShowPreview: mockSettings['libraryShowPreview'] as bool,
            searchShowPreview: mockSettings['searchShowPreview'] as bool,
            shortcuts: const {},
            enablePerBookSettings:
                mockSettings['enablePerBookSettings'] as bool,
            pdfBookViewByDefault:
                mockSettings['pdfBookViewByDefault'] as bool? ?? false,
            talmudBavliOpenFormat:
                mockSettings['talmudBavliOpenFormat'] as String? ?? 'text',
            isOfflineMode: mockSettings['isOfflineMode'] as bool? ?? false,
            softwareAndBookUpdatesEnabled:
                mockSettings['softwareAndBookUpdatesEnabled'] as bool? ?? true,
            enableHtmlLinks: mockSettings['enableHtmlLinks'] as bool? ?? true,
            personalNotesCollapsedByDefault:
                mockSettings['personalNotesCollapsedByDefault'] as bool? ??
                true,
            protectedModeEnabled:
                mockSettings['protectedModeEnabled'] as bool? ?? false,
          ),
        ],
        verify: (_) {
          verify(mockRepository.loadSettings()).called(1);
        },
      );
    });

    group('UpdateDarkMode', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateDarkMode is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateDarkMode(true)),
        expect: () => [
          settingsBloc.state.copyWith(isDarkMode: true),
        ],
        verify: (_) {
          verify(mockRepository.updateDarkMode(true)).called(1);
        },
      );
    });

    group('UpdateFollowSystemTheme', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateFollowSystemTheme is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateFollowSystemTheme(true)),
        expect: () => [
          settingsBloc.state.copyWith(followSystemTheme: true),
        ],
        verify: (_) {
          verify(mockRepository.updateFollowSystemTheme(true)).called(1);
        },
      );
    });

    group('UpdateSeedColor', () {
      const newColor = Colors.red;

      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateSeedColor is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(UpdateSeedColor(newColor)),
        expect: () => [
          settingsBloc.state.copyWith(seedColor: newColor),
        ],
        verify: (_) {
          verify(mockRepository.updateSeedColor(newColor)).called(1);
        },
      );
    });

    group('UpdateFontSize', () {
      const newFontSize = 20.0;

      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateFontSize is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateFontSize(newFontSize)),
        expect: () => [
          settingsBloc.state.copyWith(fontSize: newFontSize),
        ],
        verify: (_) {
          verify(mockRepository.updateFontSize(newFontSize)).called(1);
        },
      );
    });

    group('UpdateTalmudBavliOpenFormat', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateTalmudBavliOpenFormat is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateTalmudBavliOpenFormat('pdf')),
        expect: () => [
          settingsBloc.state.copyWith(talmudBavliOpenFormat: 'pdf'),
        ],
        verify: (_) {
          verify(mockRepository.updateTalmudBavliOpenFormat('pdf')).called(1);
        },
      );
    });

    group('UpdateFontFamily', () {
      const newFontFamily = 'NotoSerifHebrew';

      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateFontFamily is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateFontFamily(newFontFamily)),
        expect: () => [
          settingsBloc.state.copyWith(fontFamily: newFontFamily),
        ],
        verify: (_) {
          verify(mockRepository.updateFontFamily(newFontFamily)).called(1);
        },
      );
    });

    group('UpdateDefaultRemoveNikud', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateDefaultRemoveNikud is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateDefaultRemoveNikud(true)),
        expect: () => [
          settingsBloc.state.copyWith(defaultRemoveNikud: true),
        ],
        verify: (_) {
          verify(mockRepository.updateDefaultRemoveNikud(true)).called(1);
        },
      );
    });

    group('UpdateRemoveNikudFromTanach', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateRemoveNikudFromTanach is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateRemoveNikudFromTanach(true)),
        expect: () => [
          settingsBloc.state.copyWith(removeNikudFromTanach: true),
        ],
        verify: (_) {
          verify(mockRepository.updateRemoveNikudFromTanach(true)).called(1);
        },
      );
    });

    group('UpdateDefaultContinuousReadingMode', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateDefaultContinuousReadingMode is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateDefaultContinuousReadingMode(true)),
        expect: () => [
          settingsBloc.state.copyWith(defaultContinuousReadingMode: true),
        ],
        verify: (_) {
          verify(
            mockRepository.updateDefaultContinuousReadingMode(true),
          ).called(1);
        },
      );
    });

    group('UpdateDefaultSidebarOpen', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateDefaultSidebarOpen is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateDefaultSidebarOpen(true)),
        expect: () => [
          settingsBloc.state.copyWith(defaultSidebarOpen: true),
        ],
        verify: (_) {
          verify(mockRepository.updateDefaultSidebarOpen(true)).called(1);
        },
      );
    });

    group('UpdateDefaultCommentaryOpen', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateDefaultCommentaryOpen is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateDefaultCommentaryOpen(true)),
        expect: () => [
          settingsBloc.state.copyWith(defaultCommentaryOpen: true),
        ],
        verify: (_) {
          verify(mockRepository.updateDefaultCommentaryOpen(true)).called(1);
        },
      );
    });

    group('UpdatePinSidebar', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdatePinSidebar is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdatePinSidebar(true)),
        expect: () => [
          settingsBloc.state.copyWith(pinSidebar: true),
        ],
        verify: (_) {
          verify(mockRepository.updatePinSidebar(true)).called(1);
        },
      );
    });
    group('UpdateSidebarWidth', () {
      const newWidth = 350.0;

      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateSidebarWidth is added',
        build: () => settingsBloc,
        act: (bloc) => bloc.add(const UpdateSidebarWidth(newWidth)),
        expect: () => [
          settingsBloc.state.copyWith(sidebarWidth: newWidth),
        ],
        verify: (_) {
          verify(mockRepository.updateSidebarWidth(newWidth)).called(1);
        },
      );
    });

    group('UpdateProtectedModePassword', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits protectedModePasswordSet=true ושומר ב-repository',
        build: () {
          when(
            mockRepository.updateProtectedModePassword('1234'),
          ).thenAnswer((_) async {});
          return settingsBloc;
        },
        act: (bloc) => bloc.add(const UpdateProtectedModePassword('1234')),
        expect: () => [
          settingsBloc.state.copyWith(protectedModePasswordSet: true),
        ],
        verify: (_) {
          verify(mockRepository.updateProtectedModePassword('1234')).called(1);
        },
      );
    });

    group('ClearProtectedModePassword', () {
      blocTest<SettingsBloc, SettingsState>(
        'כשמצב סייפר כבוי: מוחק את הסיסמה ב-repository ומעדכן protectedModePasswordSet=false',
        build: () {
          when(
            mockRepository.clearProtectedModePassword(),
          ).thenAnswer((_) async {});
          return settingsBloc;
        },
        seed: () => SettingsState.initial().copyWith(
          protectedModeEnabled: false,
          protectedModePasswordSet: true,
        ),
        act: (bloc) => bloc.add(const ClearProtectedModePassword()),
        expect: () => [
          isA<SettingsState>().having(
            (s) => s.protectedModePasswordSet,
            'protectedModePasswordSet',
            isFalse,
          ),
        ],
        verify: (_) {
          verify(mockRepository.clearProtectedModePassword()).called(1);
        },
      );

      blocTest<SettingsBloc, SettingsState>(
        'כשמצב סייפר פעיל: לא מוחק את הסיסמה ולא פולט state חדש',
        build: () => settingsBloc,
        seed: () => SettingsState.initial().copyWith(
          protectedModeEnabled: true,
          protectedModePasswordSet: true,
        ),
        act: (bloc) => bloc.add(const ClearProtectedModePassword()),
        expect: () => <SettingsState>[],
        verify: (_) {
          verifyNever(mockRepository.clearProtectedModePassword());
        },
      );
    });

    group('UpdateMergeUserBooksIntoLibrary', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits state עם mergeUserBooksIntoLibrary=true ושומר ב-repository',
        build: () {
          when(
            mockRepository.updateMergeUserBooksIntoLibrary(true),
          ).thenAnswer((_) async {});
          return settingsBloc;
        },
        act: (bloc) => bloc.add(const UpdateMergeUserBooksIntoLibrary(true)),
        expect: () => [
          settingsBloc.state.copyWith(mergeUserBooksIntoLibrary: true),
        ],
        verify: (_) {
          verify(
            mockRepository.updateMergeUserBooksIntoLibrary(true),
          ).called(1);
        },
      );

      test('initial state defaults to false', () {
        expect(settingsBloc.state.mergeUserBooksIntoLibrary, isFalse);
      });
    });

    group('UpdateSoftwareAndBookUpdatesEnabled', () {
      blocTest<SettingsBloc, SettingsState>(
        'emits updated state when UpdateSoftwareAndBookUpdatesEnabled is added',
        build: () {
          when(
            mockRepository.updateSoftwareAndBookUpdatesEnabled(false),
          ).thenAnswer((_) async {});
          return settingsBloc;
        },
        act: (bloc) =>
            bloc.add(const UpdateSoftwareAndBookUpdatesEnabled(false)),
        expect: () => [
          settingsBloc.state.copyWith(softwareAndBookUpdatesEnabled: false),
        ],
        verify: (_) {
          verify(
            mockRepository.updateSoftwareAndBookUpdatesEnabled(false),
          ).called(1);
        },
      );
    });

    group('UpdateHiddenBuiltInToolIds', () {
      blocTest<SettingsBloc, SettingsState>(
        'persists the new set and emits state with updated hiddenBuiltInToolIds',
        build: () {
          when(
            mockRepository.updateHiddenBuiltInToolIds(const {
              'builtin.calendar',
              'builtin.gematria',
            }),
          ).thenAnswer((_) async {});
          return settingsBloc;
        },
        act: (bloc) => bloc.add(
          const UpdateHiddenBuiltInToolIds(
            {'builtin.calendar', 'builtin.gematria'},
          ),
        ),
        expect: () => [
          settingsBloc.state.copyWith(
            hiddenBuiltInToolIds: const {
              'builtin.calendar',
              'builtin.gematria',
            },
          ),
        ],
        verify: (_) {
          verify(
            mockRepository.updateHiddenBuiltInToolIds(
              {'builtin.calendar', 'builtin.gematria'},
            ),
          ).called(1);
        },
      );

      blocTest<SettingsBloc, SettingsState>(
        'empty set clears all hidden tools',
        build: () {
          when(
            mockRepository.updateHiddenBuiltInToolIds(<String>{}),
          ).thenAnswer((_) async {});
          return settingsBloc;
        },
        seed: () => SettingsState.initial().copyWith(
          hiddenBuiltInToolIds: const {'builtin.calendar'},
        ),
        act: (bloc) => bloc.add(const UpdateHiddenBuiltInToolIds(<String>{})),
        expect: () => [
          isA<SettingsState>().having(
            (s) => s.hiddenBuiltInToolIds,
            'hiddenBuiltInToolIds',
            isEmpty,
          ),
        ],
      );
    });

    group('UpdateBuiltInToolsPinnedToNavRail', () {
      blocTest<SettingsBloc, SettingsState>(
        'persists the new set and emits state with updated pinned set',
        build: () {
          when(
            mockRepository.updateBuiltInToolsPinnedToNavRail(const {
              'builtin.calendar',
            }),
          ).thenAnswer((_) async {});
          return settingsBloc;
        },
        act: (bloc) => bloc.add(
          const UpdateBuiltInToolsPinnedToNavRail({'builtin.calendar'}),
        ),
        expect: () => [
          settingsBloc.state.copyWith(
            builtInToolsPinnedToNavRail: const {'builtin.calendar'},
          ),
        ],
        verify: (_) {
          verify(
            mockRepository.updateBuiltInToolsPinnedToNavRail(
              {'builtin.calendar'},
            ),
          ).called(1);
        },
      );
    });

    group('UpdateBuiltInToolsOrder', () {
      const order = ['builtin.gematria', 'builtin.calendar'];

      blocTest<SettingsBloc, SettingsState>(
        'persists the order and emits state with the new order',
        build: () {
          when(
            mockRepository.updateBuiltInToolsOrder(order),
          ).thenAnswer((_) async {});
          return settingsBloc;
        },
        act: (bloc) => bloc.add(const UpdateBuiltInToolsOrder(order)),
        expect: () => [
          settingsBloc.state.copyWith(builtInToolsOrder: order),
        ],
        verify: (_) {
          verify(mockRepository.updateBuiltInToolsOrder(order)).called(1);
        },
      );

      blocTest<SettingsBloc, SettingsState>(
        'initial state has no custom order',
        build: () => settingsBloc,
        verify: (bloc) => expect(bloc.state.builtInToolsOrder, isEmpty),
      );

      test('שומר הזזות מהירות לפי סדר הבקשות', () async {
        const firstOrder = ['builtin.calendar', 'builtin.gematria'];
        const secondOrder = ['builtin.gematria', 'builtin.calendar'];
        final firstWrite = Completer<void>();
        final secondWrite = Completer<void>();
        when(
          mockRepository.updateBuiltInToolsOrder(firstOrder),
        ).thenAnswer((_) => firstWrite.future);
        when(
          mockRepository.updateBuiltInToolsOrder(secondOrder),
        ).thenAnswer((_) => secondWrite.future);
        final secondStarted = untilCalled(
          mockRepository.updateBuiltInToolsOrder(secondOrder),
        );

        settingsBloc.add(const UpdateBuiltInToolsOrder(firstOrder));
        settingsBloc.add(const UpdateBuiltInToolsOrder(secondOrder));
        await Future<void>.delayed(Duration.zero);
        verify(mockRepository.updateBuiltInToolsOrder(firstOrder)).called(1);
        verifyNever(mockRepository.updateBuiltInToolsOrder(secondOrder));

        firstWrite.complete();
        await secondStarted;
        secondWrite.complete();
        await Future<void>.delayed(Duration.zero);

        expect(settingsBloc.state.builtInToolsOrder, secondOrder);
      });

      // הסדר משמעותי — שתי רשימות באותם מזהים בסדר שונה הן מצבים שונים.
      test('state equality is order sensitive', () {
        final a = SettingsState.initial().copyWith(
          builtInToolsOrder: const ['a', 'b'],
        );
        final b = SettingsState.initial().copyWith(
          builtInToolsOrder: const ['b', 'a'],
        );
        expect(a, isNot(b));
        expect(
          a,
          SettingsState.initial().copyWith(builtInToolsOrder: const ['a', 'b']),
        );
      });
    });

    // חייב לרוץ אחרון: Settings.init גלובלי, והקבוצות הקודמות מסתמכות על
    // כך שהניקוי נכשל בשקט כש-Settings לא מאותחל.
    group('ניקוי פר-ספר בעקבות שינוי ברירת מחדל', () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('bloc_cleanup');
        AppPaths.debugOverrideDataRootPath(tempDir.path);
        // splited-view לא נקבע => ברירת המחדל בפועל: מפרשים בצד (true).
        await Settings.init(cacheProvider: MemorySettingsCache());
      });

      tearDown(() async {
        AppPaths.debugOverrideDataRootPath(null);
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      test(
        'שינוי ברירת מחדל קריאה רציפה אינו מוחק override של פריסת מפרשים',
        () async {
          // הבאג שתוקן: defaultShowSplitView הועבר כ-false קבוע, ולכן
          // commentatorsBelow=true (override אמיתי) זוהה כמיותר ונמחק.
          const overrideKey = 'o__1__בראשית';
          const redundantKey = 'o__2__שמות';
          await PerBookSettings.saveSettings(overrideKey, {
            'commentatorsBelow': true,
          });
          await PerBookSettings.saveSettings(redundantKey, {
            'continuousReadingMode': true,
          });

          settingsBloc.add(const UpdateDefaultContinuousReadingMode(true));

          // הניקוי רץ ללא await; מחיקת הקובץ שהפך מיותר מוכיחה שהוא רץ וסיים.
          var cleaned = false;
          for (var i = 0; i < 100 && !cleaned; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            cleaned = await PerBookSettings.loadSettings(redundantKey) == null;
          }
          expect(cleaned, isTrue, reason: 'הניקוי לא רץ בזמן סביר');
          await Future<void>.delayed(const Duration(milliseconds: 50));

          final overrideJson = await PerBookSettings.loadSettings(overrideKey);
          expect(overrideJson?['commentatorsBelow'], isTrue);
        },
      );
    });
  });
}
