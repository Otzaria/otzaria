import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';
import 'package:otzaria/theme/app_theme_data.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _TestTextBookBloc textBookBloc;
  late _TestSettingsBloc settingsBloc;
  late Directory backupDir;

  setUp(() async {
    backupDir = await Directory.systemTemp.createTemp('commentary_toolbar_');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(
      SettingsRepository.keyBackupPath,
      backupDir.path,
    );
    await Settings.setValue<bool>(SettingsRepository.keyCompactMenuMode, true);
    final settings = BackupService.backupSettingsFromKeys([
      SettingsRepository.keyCompactMenuMode,
    ]);
    expect(
      BackupService.isPortableSettingKey(SettingsRepository.keyCompactMenuMode),
      true,
    );
    await Settings.setValue<bool>(SettingsRepository.keyCompactMenuMode, false);
    final backup = File('${backupDir.path}/desktop.json');
    await backup.writeAsString(
      jsonEncode({
        'version': '2.0',
        'includes': {'settings': true},
        'settings': settings,
      }),
    );
    await BackupService.restoreFromBackup(backup.path);
    expect(SettingsRepository().readSettings()['compactMenuMode'], true);
    LibraryProviderManager.instance.resetForTesting();
    final provider = _FakeLibraryProvider();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): provider,
      },
      providers: [provider],
    );
    textBookBloc = _TestTextBookBloc(_loadedState());
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
  });

  tearDown(() async {
    await textBookBloc.close();
    await settingsBloc.close();
    LibraryProviderManager.instance.resetForTesting();
    await backupDir.delete(recursive: true);
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    required bool compact,
    required bool pdf,
    TextDirection direction = TextDirection.rtl,
    double scale = 1,
    bool empty = false,
    bool fullScreen = true,
    VoidCallback? onClose,
  }) async {
    if (!compact) {
      await Settings.setValue<bool>(
        SettingsRepository.keyCompactMenuMode,
        false,
      );
    }
    final persisted =
        SettingsRepository().readSettings()['compactMenuMode'] as bool;
    expect(persisted, compact);
    settingsBloc.emitStateForTest(
      settingsBloc.state.copyWith(compactMenuMode: persisted),
    );
    final notes = _FakePersonalNotesBloc();
    addTearDown(notes.close);
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: '/tmp/test.pdf'),
      pageNumber: 1,
    );
    tab.currentTextLineNumber = 1;
    tab.links = _loadedState().links;
    if (!empty) tab.activeCommentators = {'מפרש בדיקה'};
    addTearDown(tab.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
    });
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
        ],
        child: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, state) => MaterialApp(
            theme: AppThemeData.light(
              ColorScheme.fromSeed(seedColor: Colors.blue),
              compactMenuMode: state.compactMenuMode,
            ),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('he', 'IL')],
            locale: const Locale('he', 'IL'),
            builder: (context, child) => Directionality(
              textDirection: direction,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: pdf
                  ? PdfCommentaryPanel(
                      tab: tab,
                      linksCount: tab.links.length,
                      isFullScreen: fullScreen,
                      openBookCallback: _noopOpenBook,
                      fontSize: 18,
                      onClose: onClose,
                    )
                  : CommentaryListBase(
                      openBookCallback: _noopOpenBook,
                      fontSize: 18,
                      showSearch: true,
                      shrinkWrap: false,
                      selectedCommentatorsOverride: empty ? const [] : null,
                      onClosePane: onClose,
                      onOpenInNewTab: () {},
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const platforms = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  });
  bool mobile(WidgetTester tester) {
    final platform = Theme.of(tester.element(find.byTooltip('חיפוש'))).platform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  for (final pdf in [false, true]) {
    for (final compact in [false, true]) {
      for (final direction in TextDirection.values) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'סרגל ${pdf ? 'PDF' : 'טקסט'} compact=$compact $direction scale=$scale',
            (tester) async {
              await pumpPanel(
                tester,
                compact: compact,
                pdf: pdf,
                direction: direction,
                scale: scale,
                onClose: () {},
              );
              final search = find.byTooltip('חיפוש');
              final isMobile = mobile(tester);
              final visualHeight = isMobile
                  ? 40.0
                  : compact
                  ? 36.0
                  : 40.0;
              final targetHeight = isMobile ? 48.0 : visualHeight;
              final searchRowHeight = !pdf && isMobile
                  ? 48.0
                  : compact
                  ? 36.0
                  : 48.0;
              final content = find.textContaining('זהו פירוש לבדיקה');
              expect(content, findsOneWidget);
              final before = tester.getTopLeft(content).dy;
              expect(Directionality.of(tester.element(search)), direction);
              for (final tooltip in [
                'חיפוש',
                'בחירת מפרשים',
                'כווץ את כל המפרשים',
                'פתח כרטסיית מפרשים',
              ]) {
                final finder = find.byTooltip(tooltip);
                expect(
                  tester
                      .getSize(
                        find.ancestor(
                          of: finder,
                          matching: find.byType(IconButton),
                        ),
                      )
                      .height,
                  targetHeight,
                );
              }
              expect(tester.getSize(search).height, visualHeight);
              final style = IconButtonTheme.of(tester.element(search)).style!;
              final appStyle = Theme.of(
                tester.element(search),
              ).iconButtonTheme.style!;
              expect(style.shape, appStyle.shape);
              expect(style.overlayColor, appStyle.overlayColor);
              expect(style.foregroundColor, appStyle.foregroundColor);
              expect(style.padding, appStyle.padding);
              await tester.tap(search);
              await tester.pumpAndSettle();
              expect(
                tester.getSize(find.byType(OtzariaSearchField)).height,
                compact ? 36 : 48,
              );
              expect(
                tester
                    .widget<TextField>(find.byType(TextField))
                    .focusNode!
                    .hasFocus,
                true,
              );
              expect(
                tester.getTopLeft(content).dy - before,
                searchRowHeight - targetHeight,
              );
              await tester.tap(find.byTooltip('סגור חיפוש'));
              await tester.pumpAndSettle();
              expect(find.byType(TextField), findsNothing);
              expect(tester.getTopLeft(content).dy, before);
              expect(tester.takeException(), isNull);
            },
            variant: platforms,
          );
        }
      }
    }
    testWidgets('שינוי הגדרה חי ${pdf ? 'PDF' : 'טקסט'}', (tester) async {
      await pumpPanel(tester, compact: false, pdf: pdf);
      final isMobile = mobile(tester);
      expect(tester.getSize(find.byTooltip('חיפוש')).height, 40);
      settingsBloc.emitStateForTest(
        settingsBloc.state.copyWith(compactMenuMode: true),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byTooltip('חיפוש')).height,
        isMobile ? 40 : 36,
      );
      await tester.tap(find.byTooltip('חיפוש'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(OtzariaSearchField)).height, 36);
      settingsBloc.emitStateForTest(
        settingsBloc.state.copyWith(compactMenuMode: false),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(OtzariaSearchField)).height, 48);
      await tester.tap(find.byTooltip('סגור חיפוש'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byTooltip('חיפוש')).height, 40);
      expect(tester.takeException(), isNull);
    }, variant: platforms);
    testWidgets('בחירת מפרשים וסגירת חלונית ${pdf ? 'PDF' : 'טקסט'}', (
      tester,
    ) async {
      var closed = 0;
      await pumpPanel(
        tester,
        compact: true,
        pdf: pdf,
        fullScreen: false,
        onClose: () => closed++,
      );
      await tester.tap(find.byTooltip('בחירת מפרשים'));
      await tester.pumpAndSettle();
      expect(find.text('בחירת מפרשים'), findsOneWidget);
      await tester.tap(find.byTooltip('חזרה למפרשים'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('חיפוש'), findsOneWidget);
      await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(tester.takeException(), isNull);
    }, variant: platforms);
    testWidgets('ללא בחירת מפרשים ${pdf ? 'PDF' : 'טקסט'}', (tester) async {
      await pumpPanel(tester, compact: true, pdf: pdf, empty: true);
      expect(find.text('בחירת מפרשים'), findsOneWidget);
      expect(find.byTooltip('חיפוש'), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: platforms);
  }
}

void _noopOpenBook(dynamic _) {}

TextBookLoaded _loadedState() {
  final link = Link(
    heRef: 'בראשית א',
    index1: 1,
    path2: 'מפרש בדיקה.txt',
    index2: 1,
    connectionType: 'COMMENTARY',
    targetCategoryId: 1,
    targetFileType: 'txt',
  );

  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א', 'שורה ב'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const ['מפרש בדיקה'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה'],
    links: [link],
    visibleLinks: const [],
    linksByLine: {
      1: [link],
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitStateForTest(TextBookState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  void emitStateForTest(SettingsState state) => emit(state);
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibraryProvider implements LibraryProvider {
  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'T';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    return const [];
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    return {'מפרש בדיקה|1|txt'};
  }

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async {
    return 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    return title == 'מפרש בדיקה';
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return const {};
  }
}

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
    : super(
        const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        ),
      ) {
    on<PersonalNotesEvent>((_, _) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
