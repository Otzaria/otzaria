// גודל גופן המפרשים ומרווח השורות נשמרים לכל ספר בנפרד כש"שמירת התאמות לכל
// ספר בנפרד" מופעלת (issue #2306). קודם המחוונים בחלונית שמעל הספר שינו תמיד
// את ההגדרה הכללית — כלומר את כל הספרים.

import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/tabs/text_settings_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDataRoot;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDataRoot = await Directory.systemTemp.createTemp('per_book_metrics');
    AppPaths.debugOverrideDataRootPath(tempDataRoot.path);
  });

  tearDown(() async {
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDataRoot.exists()) {
      await tempDataRoot.delete(recursive: true);
    }
  });

  test('השדות החדשים נשמרים בקובץ הספר ונקראים בחזרה', () {
    final json = TextBookPerBookSettings(
      commentatorsFontSize: 30,
      lineHeight: 2.2,
    ).toJson();
    final restored = TextBookPerBookSettings.fromJson(json);
    expect(restored.commentatorsFontSize, 30);
    expect(restored.lineHeight, 2.2);
    expect(TextBookPerBookSettings.fromJson(const {}).lineHeight, isNull);
  });

  Future<TextBookLoaded> load(TextBook book) async {
    final bloc = TextBookBloc(
      repository: _Repository(),
      initialState: TextBookInitial.named(book, 0, false, const []),
    );
    addTearDown(bloc.close);
    addTearDown(PerBookSettings.settle);
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    return await bloc.stream.firstWhere((s) => s is TextBookLoaded)
        as TextBookLoaded;
  }

  for (final enabled in [true, false]) {
    test(
      'פתיחת ספר טוענת את ההתאמות שלו בלבד (שמירה לספר: $enabled)',
      () async {
        await Settings.setValue<bool>(
          SettingsRepository.keyEnablePerBookSettings,
          enabled,
        );
        final bookA = TextBook(title: 'ספר א');
        final bookB = TextBook(title: 'ספר ב');
        await TextBookPerBookSettings.mutate(
          bookA,
          (_) =>
              TextBookPerBookSettings(commentatorsFontSize: 30, lineHeight: 2),
        );

        final a = await load(bookA);
        final b = await load(bookB);

        expect(a.commentatorsFontSize, enabled ? 30 : null);
        expect(a.lineHeight, enabled ? 2 : null);
        expect(b.commentatorsFontSize, isNull);
        expect(b.lineHeight, isNull);
      },
    );
  }

  group('המחוונים בחלונית שמעל הספר', () {
    late _MockSettingsBloc settingsBloc;

    setUpAll(() {
      registerFallbackValue(const UpdateLineHeight(0));
    });

    TextBookLoaded loaded(TextBook book) => TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: const ['שורה א'],
      fontSize: 25,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [0],
      pinLeftPane: false,
      searchText: '',
    );

    final commentarySlider = find.byWidgetPredicate(
      (w) => w is Slider && w.min == 10 && w.max == 40,
    );
    final lineHeightSlider = find.byWidgetPredicate(
      (w) => w is Slider && w.min == 1 && w.max == 3,
    );

    Future<(TextBookBloc, TextBookBloc)> pumpTab(
      WidgetTester tester, {
      required bool perBook,
    }) async {
      settingsBloc = _MockSettingsBloc();
      whenListen(
        settingsBloc,
        const Stream<SettingsState>.empty(),
        initialState: SettingsState.initial().copyWith(
          enablePerBookSettings: perBook,
        ),
      );
      TextBookBloc bloc(String title) {
        final b = TextBookBloc(
          repository: _Repository(),
          initialState: TextBookInitial.named(
            TextBook(title: title),
            0,
            false,
            const [],
          ),
        )..emit(loaded(TextBook(title: title)));
        addTearDown(b.close);
        return b;
      }

      final bookA = bloc('ספר א');
      final bookB = bloc('ספר ב');
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: Scaffold(
              body: PrimaryScrollController.none(
                child: TextSettingsTab(
                  isDialog: true,
                  scope: TextSettingsScope.book,
                  book: bookA,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (bookA, bookB);
    }

    Future<void> tapRight(WidgetTester tester, Finder slider) async {
      await tester.tapAt(tester.getCenter(slider) + const Offset(150, 0));
      await tester.pump();
    }

    testWidgets('כשהשמירה לספר מופעלת — משנים את הספר הזה בלבד', (
      tester,
    ) async {
      final (bookA, bookB) = await pumpTab(tester, perBook: true);
      final global = SettingsState.initial();

      await tapRight(tester, commentarySlider);
      await tapRight(tester, lineHeightSlider);

      verifyNever(
        () => settingsBloc.add(any(that: isA<UpdateCommentatorsFontSize>())),
      );
      verifyNever(() => settingsBloc.add(any(that: isA<UpdateLineHeight>())));
      final a = bookA.state as TextBookLoaded;
      expect(a.commentatorsFontSize, greaterThan(global.commentatorsFontSize));
      expect(a.lineHeight, greaterThan(global.lineHeight));
      final b = bookB.state as TextBookLoaded;
      expect(b.commentatorsFontSize, isNull);
      expect(b.lineHeight, isNull);

      // ונשמר לקובץ של ספר א, כך שייטען בפתיחה הבאה.
      Map<String, dynamic>? saved;
      // הכתיבה האמיתית לקובץ מתקדמת רק בזמן אמת, וההמשכים שלה רק ב-pump.
      for (var i = 0; i < 60 && (i < 10 || saved?['lineHeight'] == null); i++) {
        saved = await tester.runAsync<Map<String, dynamic>?>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return PerBookSettings.loadSettings(PerBookSettings.bookKey(a.book));
        });
        await tester.pump();
      }
      expect(saved?['commentatorsFontSize'], a.commentatorsFontSize);
      expect(saved?['lineHeight'], a.lineHeight);
    });

    testWidgets('כשהשמירה לספר כבויה — משנים את ההגדרה הכללית', (tester) async {
      final (bookA, _) = await pumpTab(tester, perBook: false);

      await tapRight(tester, commentarySlider);
      await tapRight(tester, lineHeightSlider);

      verify(
        () => settingsBloc.add(any(that: isA<UpdateCommentatorsFontSize>())),
      ).called(1);
      verify(
        () => settingsBloc.add(any(that: isA<UpdateLineHeight>())),
      ).called(1);
      expect((bookA.state as TextBookLoaded).commentatorsFontSize, isNull);
    });
  });
}

class _Repository extends TextBookRepository {
  _Repository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async => 'שורה א\nשורה ב';

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
}
