import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  /// HtmlWidget נבנה אסינכרונית; pumpAndSettle עלול להיתקע כשהקובץ רץ ברצף.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// מרימה את תוכן החלונית לקישור עם תוכן ארוך, חתוך ל-4 שורות ברוחב צר.
  /// [alignment] — מיקום התוכן על המסך (ברירת מחדל: מרכז). [path2] — ייחודי
  /// לבדיקה, כי Link.content שומר מטמון סטטי לפי הנתיב.
  Future<void> pumpPreview(
    WidgetTester tester, {
    int index2 = 1,
    AlignmentGeometry alignment = Alignment.center,
    String path2 = 'מפרש א',
  }) async {
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: const {},
      providers: [
        _FakeContentProvider(List.filled(60, 'מילה').join(' ')),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: _TestSettingsBloc(SettingsState.initial()),
          child: Scaffold(
            body: Align(
              alignment: alignment,
              child: SizedBox(
                width: 240,
                child: LinkHoverPreviewContent(
                  link: Link(
                    heRef: '$path2, א',
                    index1: 1,
                    path2: path2,
                    index2: index2,
                    connectionType: 'commentary',
                  ),
                  maxContentLines: 4,
                  compact: true,
                  displayProfile: TextDisplayProfile.defaults,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  testWidgets('תוכן חתוך מציג לחצן "…" ולחיצתו פורשת אותו לתצוגה נגללת', (
    tester,
  ) async {
    await pumpPreview(tester);

    final dots = find.text('…');
    expect(dots, findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);

    await tester.tap(dots);
    await tester.pumpAndSettle();

    // הלחצן נעלם והתוכן המלא נגלל בתוך החלונית.
    expect(find.text('…'), findsNothing);
    expect(find.byType(Scrollable), findsOneWidget);
  });

  testWidgets('פרישה ליד תחתית המסך גדלה כלפי מטה בלבד, עד שולי המסך', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      alignment: Alignment.bottomCenter,
      path2: 'מפרש ד',
    );
    // ראש התוכן החתוך — משם התוכן הפרוש גדל כלפי מטה.
    final contentTop = tester.getTopLeft(find.byType(ClipRect).first).dy;
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    await tester.tap(find.text('…'));
    await pumpFrames(tester);

    final expandedHeight = tester.getSize(find.byType(Scrollable)).height;
    expect(expandedHeight, greaterThan(0));
    expect(
      expandedHeight,
      lessThanOrEqualTo(screenHeight - contentTop - 24),
      reason: 'התוכן הפרוש נעצר לפני שולי המסך ולא דוחף את החלונית למעלה',
    );
    // ובלי המגבלה היה תופס 60% מגובה המסך.
    expect(expandedHeight, lessThan(screenHeight * 0.6));
  });

  /// מרימה את תוכן החלונית לקישור שמחזיר [content] כמות שהוא.
  /// [maxFontSize] — גודל הטקסט שעליו נפתחה החלונית. [letterSpacing] — מרווח
  /// אותיות בסגנון ברירת המחדל שהתוכן יורש.
  Future<void> pumpPreviewWithContent(
    WidgetTester tester,
    String content, {
    required String path2,
    double? maxFontSize,
    double? letterSpacing,
  }) async {
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: const {},
      providers: [_FakeContentProvider(content)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: _TestSettingsBloc(SettingsState.initial()),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: DefaultTextStyle.merge(
                  style: TextStyle(letterSpacing: letterSpacing),
                  child: LinkHoverPreviewContent(
                    link: Link(
                      heRef: '$path2, א',
                      index1: 1,
                      path2: path2,
                      index2: 1,
                      connectionType: 'commentary',
                    ),
                    maxContentLines: 4,
                    compact: true,
                    displayProfile: TextDisplayProfile.defaults,
                    maxFontSize: maxFontSize,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  testWidgets(
    'בחלונית שליד התפריט הכותרת נשארת במקומה בגלילת התוכן (issue #2698)',
    (tester) async {
      addTearDown(LinkPreviewOverlay.dismiss);
      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: const {},
        providers: [
          _FakeContentProvider(List.filled(600, 'מילה').join(' ')),
        ],
      );
      var opened = 0;
      final entry = buildLinkContextMenuEntry(
        link: Link(
          heRef: 'מפרש ח, א',
          index1: 1,
          path2: 'מפרש ח',
          index2: 1,
          connectionType: 'commentary',
        ),
        onTap: () => opened++,
        displayProfile: TextDisplayProfile.defaults,
      );
      late BuildContext hostContext;
      // החלונית יושבת ב-overlay של האפליקציה — הספק חייב להיות מעליה.
      await tester.pumpWidget(
        BlocProvider<SettingsBloc>.value(
          value: _TestSettingsBloc(SettingsState.initial()),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                hostContext = context;
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      LinkPreviewOverlay.showBesideMenuItem(
        hostContext,
        contentBuilder: entry.hoverPreviewBuilder!,
        itemGlobalRect: const Rect.fromLTWH(500, 50, 150, 30),
        minWidth: 200,
      );
      await pumpFrames(tester);

      final title = find.byIcon(FluentIcons.open_24_regular);
      final titleTop = tester.getTopLeft(title).dy;
      // גלילת גלגלת בתוך גוף המפרש, כמו בעכבר.
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(
          tester.getCenter(
            find
                .ancestor(
                  of: find.byType(LinkHoverPreviewContent),
                  matching: find.byType(Material),
                )
                .first,
          ),
        ),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
      await pumpFrames(tester);

      // גוף המפרש הארוך עדיין נגלל בתוך החלונית.
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .pixels,
        greaterThan(0),
      );
      expect(
        tester.getTopLeft(title).dy,
        titleTop,
        reason: 'הכותרת (פתיחת הספר) נגללה יחד עם התוכן אל מחוץ לחלונית',
      );
      await tester.tap(title);
      expect(opened, 1);
    },
  );

  testWidgets('"אין תוכן זמין" היא הודעת ממשק: bodyMedium ולא גודל הקריאה', (
    tester,
  ) async {
    await pumpPreviewWithContent(
      tester,
      ' ',
      path2: 'מפרש ט',
      maxFontSize: 30,
    );

    final message = tester.widget<Text>(find.text('אין תוכן זמין'));
    final theme = Theme.of(tester.element(find.text('אין תוכן זמין')));
    expect(message.style?.fontSize, theme.textTheme.bodyMedium?.fontSize);
    expect(message.style?.color, theme.colorScheme.onSurfaceVariant);
  });

  testWidgets('הטעינה ב-LoadingIndicator.inline', (tester) async {
    Link.clearContentCache();
    final provider = _DeferredContentProvider();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: const {},
      providers: [provider],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: _TestSettingsBloc(SettingsState.initial()),
          child: Scaffold(
            body: SizedBox(
              width: 240,
              child: LinkHoverPreviewContent(
                link: Link(
                  heRef: 'מפרש י, א',
                  index1: 1,
                  path2: 'מפרש י',
                  index2: 1,
                  connectionType: 'LINKER',
                ),
                maxContentLines: 4,
                compact: true,
                displayProfile: TextDisplayProfile.defaults,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final loading = tester.widget<LoadingIndicator>(
      find.byType(LoadingIndicator),
    );
    expect(loading.size, LoadingIndicator.inlineSize);
    provider.pending.complete('תוכן');
    await pumpFrames(tester);
  });

  testWidgets('לחצן "…" בצבע המשטח שעליו נפתחה החלונית', (tester) async {
    addTearDown(LinkPreviewOverlay.dismiss);
    Link.clearContentCache();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: const {},
      providers: [_FakeContentProvider(List.filled(60, 'מילה').join(' '))],
    );
    late BuildContext host;
    await tester.pumpWidget(
      BlocProvider<SettingsBloc>.value(
        value: _TestSettingsBloc(SettingsState.initial()),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    LinkPreviewOverlay.show(
      host,
      link: Link(
        heRef: 'מפרש יא, א',
        index1: 1,
        path2: 'מפרש יא',
        index2: 1,
        connectionType: 'LINKER',
      ),
      globalPosition: const Offset(600, 100),
      displayProfile: TextDisplayProfile.defaults,
    );
    await pumpFrames(tester);

    final dots = find.text('…');
    expect(dots, findsOneWidget);
    final materials = tester
        .widgetList<Material>(
          find.ancestor(of: dots, matching: find.byType(Material)),
        )
        .toList();
    final button = materials.first;
    final panel = materials.last;
    expect(button.color, Theme.of(host).colorScheme.surfaceContainerHigh);
    expect(button.color, panel.color);
  });

  testWidgets('תוכן קצר אינו מציג לחצן פרישה', (tester) async {
    await pumpPreviewWithContent(tester, 'שורה קצרה', path2: 'מפרש ב');

    expect(find.text('…'), findsNothing);
  });

  group('מפרש של ארבע שורות בדיוק (issue #1719)', () {
    // ב-15×1.5 גובה השורה (22.5) מעוגל בפריסה ל-23 פיקסלים; ברוחב 240 נכנסות
    // 3 מילים בשורה. התוכן נשבר בגלישה, כי ברינדור "\n" מתכווץ לרווח.
    testWidgets('ארבע שורות בגודל כתב שגובה שורתו אינו שלם — בלי "…"', (
      tester,
    ) async {
      await pumpPreviewWithContent(
        tester,
        List.filled(12, 'מילה').join(' '),
        path2: 'מפרש ה',
        maxFontSize: 15,
      );

      expect(find.text('…'), findsNothing);
    });

    testWidgets('חמש שורות באותו גודל כתב — מוצג "…"', (tester) async {
      await pumpPreviewWithContent(
        tester,
        List.filled(13, 'מילה').join(' '),
        path2: 'מפרש ו',
        maxFontSize: 15,
      );

      expect(find.text('…'), findsOneWidget);
    });

    // מילה של 10 אותיות ב-22 פיקסלים נכנסת ב-240 בלי מרווח, ונשברת עם מרווח 3.
    testWidgets('מרווח אותיות שהתוכן יורש נכלל במדידה — מוצג "…"', (
      tester,
    ) async {
      await pumpPreviewWithContent(
        tester,
        List.filled(4, 'אבגדהוזחטי').join(' '),
        path2: 'מפרש ז',
        letterSpacing: 3,
      );

      expect(find.text('…'), findsOneWidget);
    });
  });

  testWidgets('גוף הערה מוטמעת אינו מופיע בתצוגה המקדימה, כמו בגוף הספר', (
    tester,
  ) async {
    await pumpPreviewWithContent(
      tester,
      'טקסט הספר<sup class="footnote-marker">א</sup>'
      '<i class="footnote">גוף ההערה הנסתר</i> המשך הטקסט',
      // Link.content שומר מטמון סטטי לפי הנתיב — נתיב ייחודי לבדיקה זו.
      path2: 'מפרש ג',
    );

    final rendered = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .join('\n');
    expect(rendered, contains('טקסט הספר'));
    expect(rendered, contains('המשך הטקסט'));
    expect(rendered, isNot(contains('גוף ההערה הנסתר')));
  });

  group('previewFontSize', () {
    final settings = SettingsState.initial().copyWith(
      commentatorsFontSize: 30,
    );

    test('לא גדול מגודל הטקסט שעליו נפתחה החלונית', () {
      expect(previewFontSize(settings, 22), 22);
    });

    test('מפרשים קטנים מהטקסט — נשאר גודל המפרשים', () {
      expect(previewFontSize(settings, 40), 30);
    });

    test('בלי גודל טקסט — גודל המפרשים', () {
      expect(previewFontSize(settings, null), 30);
    });
  });

  group('compactPreviewTitleFontSize: ×0.85 מגודל התוכן, בין 11 ל-14', () {
    test('בטווח — ×0.85, כמו כותרת מפרש', () {
      expect(compactPreviewTitleFontSize(14), closeTo(11.9, 1e-9));
      expect(compactPreviewTitleFontSize(16), closeTo(13.6, 1e-9));
    });

    test('גודל קריאה גדול — לא יותר מ-14 (titleSmall)', () {
      expect(compactPreviewTitleFontSize(22), 14);
      expect(compactPreviewTitleFontSize(40), 14);
    });

    test('גודל קריאה קטן — לא פחות מ-11 (labelSmall)', () {
      expect(compactPreviewTitleFontSize(10), 11);
    });
  });

  testWidgets('כותרת החלונית הקומפקטית בגודל שנגזר מגודל התוכן', (
    tester,
  ) async {
    await pumpPreviewWithContent(
      tester,
      'תוכן קצר',
      path2: 'מפרש כותרת',
      maxFontSize: 15,
    );

    final title = tester.widget<Text>(find.textContaining('מפרש כותרת').first);
    expect(title.style?.fontSize, closeTo(15 * 0.85, 1e-9));
  });

  group('כותרת ארוכה וגופן גדול בתצוגה המקדימה', () {
    const longTitle =
        'חידושים ומקורים מבעל מנחת חינוך על משנה תורה, '
        'הלכות ביכורים ושאר מתנות כהונה שבגבולין';

    setUpAll(() async {
      final loader = FontLoader('NotoRashiHebrew')
        ..addFont(
          rootBundle.load('fonts/NotoRashiHebrew-VariableFont_wght.ttf'),
        );
      await loader.load();
    });

    for (final sample in [
      (size: const Size(800, 600), scale: 1.0),
      (size: const Size(800, 600), scale: 1.5),
      (size: const Size(420, 400), scale: 1.5),
      (size: const Size(320, 400), scale: 1.5),
    ]) {
      testWidgets('טעינה ותוכן נשארים נגישים: $sample', (tester) async {
        tester.view.physicalSize = sample.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(LinkPreviewOverlay.dismiss);
        Link.clearContentCache();
        final provider = _DeferredContentProvider();
        LibraryProviderManager.instance.seedMappingsForTesting(
          mapping: const {},
          providers: [provider],
        );
        final settings = _TestSettingsBloc(
          SettingsState.initial().copyWith(commentatorsFontSize: 40),
        );
        addTearDown(settings.close);
        var opened = 0;
        final entry = buildLinkContextMenuEntry(
          link: Link(
            heRef: '$longTitle, א, י, א',
            index1: 1,
            path2: longTitle,
            index2: 4,
            connectionType: 'commentary',
          ),
          onTap: () => opened++,
          displayProfile: TextDisplayProfile.defaults,
        );
        late BuildContext host;
        await tester.pumpWidget(
          BlocProvider<SettingsBloc>.value(
            value: settings,
            child: MaterialApp(
              locale: const Locale('he', 'IL'),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('he', 'IL')],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(sample.scale),
                ),
                child: child!,
              ),
              home: Builder(
                builder: (context) {
                  host = context;
                  return const Scaffold();
                },
              ),
            ),
          ),
        );
        LinkPreviewOverlay.showBesideMenuItem(
          host,
          contentBuilder: entry.hoverPreviewBuilder!,
          itemGlobalRect: Rect.fromLTWH(sample.size.width - 180, 50, 150, 30),
          minWidth: 200,
          touchTriggered: sample.size.width < 420,
        );
        await pumpFrames(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          tester.getSize(find.byType(CircularProgressIndicator)).height,
          greaterThan(0),
        );

        provider.pending.complete(
          List.filled(100, 'והבכור מקריבין חלבו ודמו.').join(' '),
        );
        await pumpFrames(tester);
        expect(tester.takeException(), isNull);
        final scrollables = find.descendant(
          of: find.byType(LinkHoverPreviewContent),
          matching: find.byType(Scrollable),
        );
        expect(scrollables, findsNWidgets(2));
        final header = tester
            .state<ScrollableState>(scrollables.first)
            .position;
        final body = tester.state<ScrollableState>(scrollables.last).position;
        expect(header.viewportDimension, greaterThan(0));
        expect(body.viewportDimension, greaterThanOrEqualTo(140));
        expect(body.maxScrollExtent, greaterThan(0));
        final headerTop = tester.getTopLeft(scrollables.first);
        await tester.drag(scrollables.last, const Offset(0, -100));
        await pumpFrames(tester);
        expect(body.pixels, greaterThan(0));
        expect(header.pixels, 0);
        expect(tester.getTopLeft(scrollables.first), headerTop);
        expect(header.maxScrollExtent, greaterThan(0));
        header.jumpTo(header.maxScrollExtent);
        await pumpFrames(tester);
        expect(tester.takeException(), isNull);
        final title = find.descendant(
          of: scrollables.first,
          matching: find.byType(Text),
        );
        expect(title, findsOneWidget);
        expect(tester.widget<Text>(title).data, contains(longTitle));
        final headerBounds = tester.getRect(scrollables.first);
        final textBounds = tester.getRect(title);
        expect(
          textBounds.bottom,
          lessThanOrEqualTo(headerBounds.bottom + 0.01),
        );
        await tester.tapAt(headerBounds.center);
        await tester.pump();
        expect(opened, 1);
      });
    }
  });
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// ספק שמחזיר תוכן קבוע לכל קישור.
class _FakeContentProvider implements LibraryProvider {
  _FakeContentProvider(this.content);

  final String content;

  @override
  Future<String> getLinkContent(Link link) async => content;

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
  Future<void> initialize() async {}
  @override
  Future<Set<String>> getAvailableBookTitles() async => const {};
  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      false;
  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => null;
  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => const [];
  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) => throw UnimplementedError();
  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async => const [];
  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}

class _DeferredContentProvider extends _FakeContentProvider {
  _DeferredContentProvider() : super('');

  final pending = Completer<String>();

  @override
  Future<String> getLinkContent(Link link) => pending.future;
}
