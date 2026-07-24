import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildSelectedLinkRenderSettings', () {
    test('passes removeNikud through to link content rendering', () {
      final settings = SettingsState.initial();

      final renderSettings = buildSelectedLinkRenderSettings(
        settingsState: settings,
        removeNikud: true,
        searchText: '',
      );

      expect(renderSettings.removeNikud, isTrue);
    });

    test('follows teamim visibility setting for link content rendering', () {
      final settings = SettingsState.initial().copyWith(showTeamim: false);

      final renderSettings = buildSelectedLinkRenderSettings(
        settingsState: settings,
        removeNikud: false,
        searchText: 'שלום',
      );

      expect(renderSettings.removeTeamim, isTrue);
      expect(renderSettings.searchText, 'שלום');
    });

    test('justifies link content rendering', () {
      final settings = SettingsState.initial();

      final renderSettings = buildSelectedLinkRenderSettings(
        settingsState: settings,
        removeNikud: false,
        searchText: '',
      );

      expect(renderSettings.justifyText, isTrue);
    });
  });

  group('normalizeSelectedLinkText', () {
    test('collapses tabs into a single space', () {
      expect(
        normalizeSelectedLinkText('ודר\t\t\tשאל'),
        'ודר שאל',
      );
    });

    test('collapses nbsp and repeated spaces', () {
      expect(
        normalizeSelectedLinkText('ודר&nbsp;  שאל'),
        'ודר שאל',
      );
    });
  });

  group('buildSelectedLinksSearchKey', () {
    test(
      'changes when the links change even if the list length stays the same',
      () {
        final firstLinks = [
          Link(
            heRef: 'א',
            index1: 1,
            path2: '/books/alpha.txt',
            index2: 1,
            connectionType: 'reference',
          ),
        ];
        final secondLinks = [
          Link(
            heRef: 'ב',
            index1: 1,
            path2: '/books/beta.txt',
            index2: 1,
            connectionType: 'reference',
          ),
        ];

        final firstKey = buildSelectedLinksSearchKey(
          searchQuery: 'חיפוש',
          searchInContent: false,
          links: firstLinks,
        );
        final secondKey = buildSelectedLinksSearchKey(
          searchQuery: 'חיפוש',
          searchInContent: false,
          links: secondLinks,
        );

        expect(firstKey, isNot(secondKey));
      },
    );

    test('changes for the same target when source line changes', () {
      final firstLinks = [
        Link(
          heRef: 'אותו יעד',
          index1: 1,
          path2: '/books/alpha.txt',
          index2: 372,
          connectionType: 'reference',
        ),
      ];
      final secondLinks = [
        Link(
          heRef: 'אותו יעד',
          index1: 2,
          path2: '/books/alpha.txt',
          index2: 372,
          connectionType: 'reference',
        ),
      ];

      final firstKey = buildSelectedLinksSearchKey(
        searchQuery: 'חיפוש',
        searchInContent: false,
        links: firstLinks,
      );
      final secondKey = buildSelectedLinksSearchKey(
        searchQuery: 'חיפוש',
        searchInContent: false,
        links: secondLinks,
      );

      expect(firstKey, isNot(secondKey));
    });

    test('changes when the link type filter changes', () {
      final links = [
        Link(
          heRef: 'א',
          index1: 1,
          path2: '/books/alpha.txt',
          index2: 1,
          connectionType: 'reference',
        ),
      ];

      final noFilter = buildSelectedLinksSearchKey(
        searchQuery: '',
        searchInContent: false,
        links: links,
      );
      final withFilter = buildSelectedLinksSearchKey(
        searchQuery: '',
        searchInContent: false,
        links: links,
        selectedLinkTypes: const {'REFERENCE'},
      );
      final otherFilter = buildSelectedLinksSearchKey(
        searchQuery: '',
        searchInContent: false,
        links: links,
        selectedLinkTypes: const {'QUOTATION'},
      );

      expect(noFilter, isNot(withFilter));
      expect(withFilter, isNot(otherFilter));
    });

    test('משתנה כשבחירת הדור משתנה', () {
      final links = [
        Link(
          heRef: 'א',
          index1: 1,
          path2: '/books/alpha.txt',
          index2: 1,
          connectionType: 'reference',
        ),
      ];

      String keyFor(Set<String> types) => buildSelectedLinksSearchKey(
        searchQuery: '',
        searchInContent: false,
        links: links,
        selectedLinkTypes: types,
      );

      expect(keyFor(const {}), isNot(keyFor(const {'ERA:RISHONIM'})));
      expect(
        keyFor(const {'ERA:RISHONIM'}),
        isNot(keyFor(const {'ERA:ACHARONIM'})),
      );
      expect(
        keyFor(const {'ERA:RISHONIM'}),
        isNot(keyFor(const {'EIN_MISHPAT'})),
      );
    });

    test('is stable regardless of the filter set iteration order', () {
      final links = [
        Link(
          heRef: 'א',
          index1: 1,
          path2: '/books/alpha.txt',
          index2: 1,
          connectionType: 'reference',
        ),
      ];

      final first = buildSelectedLinksSearchKey(
        searchQuery: '',
        searchInContent: false,
        links: links,
        selectedLinkTypes: {'QUOTATION', 'REFERENCE'},
      );
      final second = buildSelectedLinksSearchKey(
        searchQuery: '',
        searchInContent: false,
        links: links,
        selectedLinkTypes: {'REFERENCE', 'QUOTATION'},
      );

      expect(first, second);
    });
  });

  group('buildSelectedLinkInstanceKey', () {
    test('differs for repeated target links from different source lines', () {
      final firstLink = Link(
        heRef: 'אותו יעד',
        index1: 1,
        path2: '/books/alpha.txt',
        index2: 372,
        connectionType: 'reference',
      );
      final secondLink = Link(
        heRef: 'אותו יעד',
        index1: 2,
        path2: '/books/alpha.txt',
        index2: 372,
        connectionType: 'reference',
      );

      expect(
        buildSelectedLinkInstanceKey(firstLink),
        isNot(buildSelectedLinkInstanceKey(secondLink)),
      );
      expect(
        buildSelectedLinkContentKey(firstLink),
        buildSelectedLinkContentKey(secondLink),
      );
    });
  });

  group('buildLinkChipKeys', () {
    setUp(_seedEras);
    tearDown(CommentaryService.clearEraCache);

    test('סוג ייעודי מקבל צ׳יפ אחד לכל הווריאנטים שלו', () {
      final keys = buildLinkChipKeys([
        _link(title: 'ראשונים א', type: 'QUOTATION'),
        _link(title: 'ראשונים ב', type: 'quotation auto'),
        _link(title: 'ראשונים ג', type: 'QUOTATION_AUTO_TANAKH'),
        _link(title: 'ראשונים ד', type: 'EIN_MISHPAT'),
      ]);

      expect(keys, ['EIN_MISHPAT', 'QUOTATION']);
    });

    test('סוגים חסרי משמעות מקובצים לפי דור ספר היעד', () {
      final keys = buildLinkChipKeys([
        _link(title: 'בראשית', type: 'REFERENCE'),
        _link(title: 'ראשונים א', type: 'other'),
        _link(title: 'ראשונים ב', type: 'RELATED'),
        _link(title: 'אחרונים א', type: 'NONE'),
      ]);

      expect(keys, [
        'ERA:TORAHSHEBICHTAV',
        'ERA:RISHONIM',
        'ERA:ACHARONIM',
      ]);
    });

    test('סוגים ייעודיים מוצגים לפני הדורות, והדורות לפי order', () {
      final keys = buildLinkChipKeys([
        _link(title: 'זמננו א', type: 'REFERENCE'),
        _link(title: 'ראשונים א', type: 'OTHER'),
        _link(title: 'חז"ל א', type: 'RELATED'),
        _link(title: 'בראשית', type: 'REFERENCE'),
        _link(title: 'ראשונים ב', type: 'ALLUSION'),
        _link(title: 'ראשונים ג', type: 'EIN_MISHPAT'),
      ]);

      expect(keys, [
        'EIN_MISHPAT',
        'ALLUSION',
        'ERA:TORAHSHEBICHTAV',
        'ERA:CHAZAL',
        'ERA:RISHONIM',
        'ERA:MODERN',
      ]);
    });

    test('סוג לא-מוכר מוצג אחרי הסוגים הייעודיים ולפני הדורות', () {
      final keys = buildLinkChipKeys([
        _link(title: 'ראשונים א', type: 'REFERENCE'),
        _link(title: 'ראשונים ב', type: 'MYSTERY_TYPE'),
        _link(title: 'ראשונים ג', type: 'EIN_MISHPAT'),
      ]);

      expect(keys, [
        'EIN_MISHPAT',
        'MYSTERY_TYPE',
        'ERA:RISHONIM',
      ]);
    });

    test('מטמון דורות קר — הכל נופל ל"ספרים נוספים" ללא קריסה', () {
      CommentaryService.clearEraCache();

      final keys = buildLinkChipKeys([
        _link(title: 'בראשית', type: 'REFERENCE'),
        _link(title: 'ראשונים א', type: 'OTHER'),
      ]);

      expect(keys, ['ERA:OTHER']);
      expect(CommentaryService.chipKeyLabel(keys.single), 'ספרים נוספים');
    });

    test('SOURCE מקבל צ׳יפ "מקור" ראשון, לפני כל סוג ייעודי אחר', () {
      final keys = buildLinkChipKeys([
        _link(title: 'ראשונים א', type: 'ALLUSION'),
        _link(title: 'ראשונים ב', type: 'EIN_MISHPAT'),
        _link(title: 'ראשונים ג', type: 'SOURCE'),
        _link(title: 'ראשונים ד', type: 'REFERENCE'),
      ]);

      expect(CommentaryService.chipKeyLabel(keys.first), 'מקור');
      expect(keys, [
        'SOURCE',
        'EIN_MISHPAT',
        'ALLUSION',
        'ERA:RISHONIM',
      ]);
    });

    test('SOURCE אינו מקובץ לפי דור אלא נשאר סוג ייעודי', () {
      expect(
        CommentaryService.linkChipKey(_link(title: 'בראשית', type: 'source')),
        'SOURCE',
      );
    });

    test('סדר הצ׳יפים הייעודיים כולו', () {
      final keys = buildLinkChipKeys([
        for (final type in const [
          'ALT_TOC',
          'ALLUSION',
          'FOOTNOTES',
          'SUMMARY',
          'LITURGY',
          'LAW',
          'QUOTATION',
          'MISHNAH_IN_TALMUD',
          'MESORAT_HASHAS',
          'SIFREI_MITSVOT',
          'EIN_MISHPAT',
          'SOURCE',
        ])
          _link(title: 'ראשונים א', type: type),
      ]);

      expect(keys, [
        'SOURCE',
        'EIN_MISHPAT',
        'SIFREI_MITSVOT',
        'MESORAT_HASHAS',
        'MISHNAH_IN_TALMUD',
        'QUOTATION',
        'LAW',
        'LITURGY',
        'SUMMARY',
        'FOOTNOTES',
        'ALLUSION',
        'ALT_TOC',
      ]);
    });

    test('סוגים מובחנים נשארים צ׳יפים נפרדים', () {
      final keys = buildLinkChipKeys([
        _link(title: 'ראשונים א', type: 'ALLUSION'),
        _link(title: 'ראשונים ב', type: 'LAW'),
        _link(title: 'ראשונים ג', type: 'FOOTNOTES'),
      ]);

      expect(keys.length, 3);
    });
  });

  group('effectiveSelectedLinkTypes', () {
    const availableKeys = ['EIN_MISHPAT', 'ERA:RISHONIM'];

    test('בחירה ריקה נשארת ריקה', () {
      expect(
        effectiveSelectedLinkTypes(
          selectedTypes: const {},
          availableKeys: availableKeys,
        ),
        isEmpty,
      );
    });

    test('משאירה רק מפתחות שקיימים בצ׳יפים', () {
      expect(
        effectiveSelectedLinkTypes(
          selectedTypes: const {'ERA:RISHONIM', 'MESORAT_HASHAS'},
          availableKeys: availableKeys,
        ),
        {'ERA:RISHONIM'},
      );
    });

    test('בחירה שכולה מיושנת מתאפסת = הצג הכל', () {
      expect(
        effectiveSelectedLinkTypes(
          selectedTypes: const {'REFERENCE', 'QUOTATION_AUTO'},
          availableKeys: availableKeys,
        ),
        isEmpty,
      );
    });
  });

  group('applyChipSelectionDelta', () {
    test('הוספת צ׳יפ משמרת מפתחות שאינם בקטע הנוכחי', () {
      expect(
        applyChipSelectionDelta(
          savedTypes: const {'ERA:RISHONIM', 'EIN_MISHPAT'},
          effectiveTypes: const {'EIN_MISHPAT'},
          newSelection: const {'EIN_MISHPAT', 'QUOTATION'},
        ),
        {'ERA:RISHONIM', 'EIN_MISHPAT', 'QUOTATION'},
      );
    });

    test('הסרת צ׳יפ מסירה רק אותו', () {
      expect(
        applyChipSelectionDelta(
          savedTypes: const {'ERA:RISHONIM', 'EIN_MISHPAT'},
          effectiveTypes: const {'EIN_MISHPAT'},
          newSelection: const {},
        ),
        {'ERA:RISHONIM'},
      );
    });

    test('לחיצה ראשונה כשהבחירה ריקה בוחרת רק את הנלחץ', () {
      expect(
        applyChipSelectionDelta(
          savedTypes: const {},
          effectiveTypes: const {},
          newSelection: const {'QUOTATION'},
        ),
        {'QUOTATION'},
      );
    });
  });

  group('CommentaryService.linkChipKey', () {
    setUp(_seedEras);
    tearDown(CommentaryService.clearEraCache);

    test('קישור לבראשית מקובץ תחת "תורה שבכתב" ולא תחת "לא מסווג"', () {
      final key = CommentaryService.linkChipKey(
        _link(title: 'בראשית', type: 'REFERENCE'),
      );

      expect(key, 'ERA:TORAHSHEBICHTAV');
      expect(CommentaryService.chipKeyLabel(key), 'תורה שבכתב');
    });

    test('סוג ייעודי אינו מושפע מדור ספר היעד', () {
      expect(
        CommentaryService.linkChipKey(
          _link(title: 'בראשית', type: 'EIN_MISHPAT'),
        ),
        'EIN_MISHPAT',
      );
    });
  });

  group('buildEraPreloadSignature', () {
    test('עולה בכל ניקוי מטמון', () {
      final before = CommentaryService.eraCacheVersion;
      CommentaryService.clearEraCache();
      expect(CommentaryService.eraCacheVersion, before + 1);
    });

    test('אותן כותרות אחרי clearEraCache מקבלות חתימה שונה', () {
      const titles = {'בראשית', 'ראשונים א'};
      final before = buildEraPreloadSignature(titles);
      CommentaryService.clearEraCache();
      expect(buildEraPreloadSignature(titles), isNot(before));
    });

    test('אותן כותרות בסדר שונה מקבלות חתימה זהה', () {
      expect(
        buildEraPreloadSignature({'ב', 'א'}),
        buildEraPreloadSignature({'א', 'ב'}),
      );
    });
  });

  group('CommentaryService.chipKeyLabel', () {
    test('מתרגם מפתחות דור וסוגי קישור כאחד, ללא מספרים', () {
      expect(CommentaryService.chipKeyLabel('ERA:RISHONIM'), 'ראשונים');
      expect(CommentaryService.chipKeyLabel('ERA:ACHARONIM'), 'אחרונים');
      expect(CommentaryService.chipKeyLabel('ERA:MODERN'), 'מחברי זמננו');
      expect(CommentaryService.chipKeyLabel('EIN_MISHPAT'), 'עין משפט');
      expect(CommentaryService.chipKeyLabel('MYSTERY_TYPE'), 'MYSTERY_TYPE');
    });

    test('מפתח דור לא-מוכר אינו קורס ונופל לתווית הגולמית', () {
      expect(CommentaryService.chipKeyLabel('ERA:BOGUS'), 'ERA:BOGUS');
    });

    test('דור "other" נקרא "ספרים נוספים" בפאנל הקישורים', () {
      expect(CommentaryService.chipKeyLabel('ERA:OTHER'), 'ספרים נוספים');
      expect(CommentaryEra.other.linkPanelName, 'ספרים נוספים');
    });

    test('פאנל המפרשים ממשיך להשתמש ב"שאר מפרשים"', () {
      expect(CommentaryEra.other.hebrewName, 'שאר מפרשים');
      for (final era in CommentaryEra.values) {
        if (era == CommentaryEra.other) continue;
        expect(era.linkPanelName, era.hebrewName, reason: era.name);
      }
    });
  });

  group('סינון סוגי קישורים - צ׳יפים', () {
    setUp(_seedEras);
    tearDown(CommentaryService.clearEraCache);

    testWidgets('בונה צ׳יפ לכל סוג ייעודי קיים', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'EIN_MISHPAT'),
          _link(title: 'ראשונים ב', type: 'EIN_MISHPAT'),
          _link(title: 'ראשונים ג', type: 'QUOTATION'),
        ],
      );

      expect(find.widgetWithText(Chip, 'עין משפט'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'ציטוט'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(2));
    });

    testWidgets('קישור לספר בראשית מקבל צ׳יפ "תורה שבכתב"', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'בראשית', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'REFERENCE'),
        ],
      );

      expect(find.widgetWithText(Chip, 'תורה שבכתב'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'עיון'), findsNothing);
      expect(find.widgetWithText(Chip, 'לא מסווג'), findsNothing);
    });

    testWidgets('REFERENCE/OTHER לספר ראשונים מקבל צ׳יפ "ראשונים"', (
      tester,
    ) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'אחרונים א', type: 'OTHER'),
        ],
      );

      expect(find.widgetWithText(Chip, 'ראשונים'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'אחרונים'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'עיון'), findsNothing);
      expect(find.widgetWithText(Chip, 'לא מסווג'), findsNothing);
    });

    testWidgets('צ׳יפ יחיד - שורת הצ׳יפים לא מוצגת', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'OTHER'),
        ],
      );

      expect(find.byType(Chip), findsNothing);
    });

    testWidgets('case מעורב מקובץ לצ׳יפ אחד ולא כפול', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'ein mishpat'),
          _link(title: 'ראשונים ב', type: 'EIN_MISHPAT'),
          _link(title: 'ראשונים ג', type: 'quotation'),
        ],
      );

      expect(find.widgetWithText(Chip, 'עין משפט'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(2));
    });

    testWidgets('סוג לא מוכר מוצג עם הערך עצמו כתווית', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'MYSTERY_TYPE'),
        ],
      );

      expect(find.widgetWithText(Chip, 'MYSTERY_TYPE'), findsOneWidget);
      expect(find.text('ראשונים א'), findsOneWidget);
      expect(find.text('ראשונים ב'), findsOneWidget);
    });

    testWidgets('הצ׳יפ הוא Chip ללא סימן וי — לא FilterChip', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
      );

      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(Chip), findsNWidgets(2));
    });

    testWidgets('סוגים ממוזגים מוצגים כצ׳יפ אחד', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'QUOTATION'),
          _link(title: 'ראשונים ב', type: 'quotation auto'),
          _link(title: 'ראשונים ג', type: 'REFERENCE'),
        ],
      );

      expect(find.widgetWithText(Chip, 'ציטוט'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(2));
    });

    testWidgets('לחיצה על צ׳יפ סוג שולחת UpdateLinkTypeFilter עם מפתח הסוג', (
      tester,
    ) async {
      final bloc = await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
      );

      await tester.tap(find.widgetWithText(Chip, 'ציטוט'));
      await tester.pumpAndSettle();

      expect(
        bloc.receivedEvents.whereType<UpdateLinkTypeFilter>().last.linkTypes,
        {'QUOTATION'},
      );
    });

    testWidgets('לחיצה על צ׳יפ דור שולחת את מפתח הדור', (tester) async {
      final bloc = await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
      );

      await tester.tap(find.widgetWithText(Chip, 'ראשונים'));
      await tester.pumpAndSettle();

      expect(
        bloc.receivedEvents.whereType<UpdateLinkTypeFilter>().last.linkTypes,
        {'ERA:RISHONIM'},
      );
    });

    testWidgets('לחיצה על צ׳יפ מסומן מסירה אותו מהבחירה', (tester) async {
      final bloc = await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        selectedLinkTypes: const {'QUOTATION'},
      );

      await tester.tap(find.widgetWithText(Chip, 'ציטוט'));
      await tester.pumpAndSettle();

      expect(
        bloc.receivedEvents.whereType<UpdateLinkTypeFilter>().last.linkTypes,
        isEmpty,
      );
    });

    testWidgets('לחיצה על צ׳יפ משמרת מפתח שמור שאינו קיים בקטע הנוכחי', (
      tester,
    ) async {
      final bloc = await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'EIN_MISHPAT'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        // ERA:RISHONIM נבחר בקטע קודם ואין לו צ׳יפ כאן.
        selectedLinkTypes: const {'ERA:RISHONIM', 'EIN_MISHPAT'},
      );

      await tester.tap(find.widgetWithText(Chip, 'ציטוט'));
      await tester.pumpAndSettle();

      expect(
        bloc.receivedEvents.whereType<UpdateLinkTypeFilter>().last.linkTypes,
        {'ERA:RISHONIM', 'EIN_MISHPAT', 'QUOTATION'},
      );
    });

    testWidgets('הסרת צ׳יפ אינה מוחקת מפתח שמור שאינו בקטע', (tester) async {
      final bloc = await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'EIN_MISHPAT'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        selectedLinkTypes: const {'ERA:RISHONIM', 'EIN_MISHPAT'},
      );

      await tester.tap(find.widgetWithText(Chip, 'עין משפט'));
      await tester.pumpAndSettle();

      expect(
        bloc.receivedEvents.whereType<UpdateLinkTypeFilter>().last.linkTypes,
        {'ERA:RISHONIM'},
      );
    });
  });

  group('סינון סוגי קישורים - הרשימה', () {
    setUp(_seedEras);
    tearDown(CommentaryService.clearEraCache);

    testWidgets('בחירה ריקה מציגה את כל הקישורים', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
      );

      expect(find.text('ראשונים א'), findsOneWidget);
      expect(find.text('ראשונים ב'), findsOneWidget);
    });

    testWidgets('סינון לפי צ׳יפ סוג מציג רק את הסוג הנבחר', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        selectedLinkTypes: const {'QUOTATION'},
      );

      expect(find.text('ראשונים א'), findsNothing);
      expect(find.text('ראשונים ב'), findsOneWidget);
    });

    testWidgets('סינון לפי צ׳יפ דור מחזיר בדיוק את קישורי אותו דור', (
      tester,
    ) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'other'),
          _link(title: 'אחרונים א', type: 'RELATED'),
          _link(title: 'בראשית', type: 'REFERENCE'),
          // סוג ייעודי לספר ראשונים — לא נכנס לצ׳יפ הדור.
          _link(title: 'ראשונים ג', type: 'EIN_MISHPAT'),
        ],
        selectedLinkTypes: const {'ERA:RISHONIM'},
      );

      expect(find.text('ראשונים א'), findsOneWidget);
      expect(find.text('ראשונים ב'), findsOneWidget);
      expect(find.text('אחרונים א'), findsNothing);
      expect(find.text('בראשית'), findsNothing);
      expect(find.text('ראשונים ג'), findsNothing);
    });

    testWidgets('סינון "תורה שבכתב" מחזיר את הקישור לבראשית', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'בראשית', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'REFERENCE'),
        ],
        selectedLinkTypes: const {'ERA:TORAHSHEBICHTAV'},
      );

      expect(find.text('בראשית'), findsOneWidget);
      expect(find.text('ראשונים א'), findsNothing);
    });

    testWidgets('סינון מתאים גם ל-case שונה בקישור עצמו', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'ein mishpat'),
          _link(title: 'ראשונים ב', type: 'quotation'),
        ],
        selectedLinkTypes: const {'QUOTATION'},
      );

      expect(find.text('ראשונים א'), findsNothing);
      expect(find.text('ראשונים ב'), findsOneWidget);
    });

    testWidgets('סינון לפי צ׳יפ ממוזג מחזיר את כל הסוגים שמתחתיו', (
      tester,
    ) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'QUOTATION'),
          _link(title: 'ראשונים ב', type: 'quotation auto'),
          _link(title: 'ראשונים ג', type: 'QUOTATION_AUTO_TANAKH'),
          _link(title: 'ראשונים ד', type: 'REFERENCE'),
        ],
        selectedLinkTypes: const {'QUOTATION'},
      );

      expect(find.text('ראשונים א'), findsOneWidget);
      expect(find.text('ראשונים ב'), findsOneWidget);
      expect(find.text('ראשונים ג'), findsOneWidget);
      expect(find.text('ראשונים ד'), findsNothing);
    });

    testWidgets('related passage ו-RELATED נכנסים לצ׳יפ הדור', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'related passage'),
          _link(title: 'ראשונים ב', type: 'RELATED'),
          _link(title: 'ראשונים ג', type: 'EIN_MISHPAT'),
        ],
        selectedLinkTypes: const {'ERA:RISHONIM'},
      );

      expect(find.text('ראשונים א'), findsOneWidget);
      expect(find.text('ראשונים ב'), findsOneWidget);
      expect(find.text('ראשונים ג'), findsNothing);
    });

    testWidgets('בחירה שאין לה אף צ׳יפ בקטע - מציגה הכל ולא מסך ריק', (
      tester,
    ) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        selectedLinkTypes: const {'MESORAT_HASHAS'},
      );

      expect(find.text('ראשונים א'), findsOneWidget);
      expect(find.text('ראשונים ב'), findsOneWidget);
      expect(find.text('לא נמצאו קישורים לקטע הנבחר'), findsNothing);
    });

    testWidgets('מפתח מיושן מהגדרות שמורות אינו מרוקן את הרשימה', (
      tester,
    ) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        // מפתחות שהיו קיימים בגרסאות קודמות ואינם מפתח צ׳יפ כיום.
        selectedLinkTypes: const {'REFERENCE', 'QUOTATION_AUTO'},
      );

      expect(find.text('ראשונים א'), findsOneWidget);
      expect(find.text('ראשונים ב'), findsOneWidget);
    });

    testWidgets('בחירה מיושנת אינה מציגה צ׳יפ כמסומן', (tester) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        selectedLinkTypes: const {'MESORAT_HASHAS'},
      );

      final chips = tester.widgetList<Chip>(find.byType(Chip));
      expect(chips, hasLength(2));
      expect(chips.every((chip) => chip.backgroundColor == null), isTrue);
    });

    testWidgets('אין קישורים כלל - ההודעה הגנרית', (tester) async {
      await _pumpView(tester, links: const []);

      expect(find.text('לא נמצאו קישורים לקטע הנבחר'), findsOneWidget);
    });

    testWidgets('צ׳יפ נבחר שאינו קיים בקטע לצד צ׳יפ שכן קיים - לא מסנן הכל', (
      tester,
    ) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        selectedLinkTypes: const {'ERA:RISHONIM', 'EIN_MISHPAT'},
      );

      expect(find.text('ראשונים א'), findsOneWidget);
      expect(find.text('ראשונים ב'), findsNothing);
    });

    testWidgets('מטמון דורות קר — אין קריסה והכל תחת "ספרים נוספים"', (
      tester,
    ) async {
      CommentaryService.clearEraCache();

      await _pumpView(
        tester,
        links: [
          _link(title: 'בראשית', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'OTHER'),
        ],
        selectedLinkTypes: const {'ERA:OTHER'},
      );

      expect(find.text('בראשית'), findsOneWidget);
      expect(find.text('ראשונים א'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('מטמון חם — הצ׳יפים נכונים כבר בפריים הראשון, ללא הבהוב', (
      tester,
    ) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'בראשית', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'OTHER'),
        ],
        settle: false,
      );

      expect(find.widgetWithText(Chip, 'תורה שבכתב'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'ראשונים'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'ספרים נוספים'), findsNothing);
    });

    testWidgets('קישור SOURCE מוצג ברשימה ומסונן ע"י הצ׳יפ שלו', (
      tester,
    ) async {
      await _pumpView(
        tester,
        links: [
          _link(title: 'ראשונים א', type: 'SOURCE'),
          _link(title: 'ראשונים ב', type: 'REFERENCE'),
        ],
        selectedLinkTypes: const {'SOURCE'},
      );

      expect(find.widgetWithText(Chip, 'מקור'), findsOneWidget);
      expect(find.text('ראשונים א'), findsOneWidget);
      expect(find.text('ראשונים ב'), findsNothing);
    });
  });

  group('צ׳יפ "על <הספר הפתוח>"', () {
    setUp(_seedEras);
    tearDown(CommentaryService.clearEraCache);

    test('קישור לספר "על X" מקבל גם את מפתח הדור וגם את ON_BOOK', () {
      expect(
        CommentaryService.linkChipKeys(
          _link(title: 'רש"י על בבא בתרא', type: 'REFERENCE'),
          openBookTitle: 'בבא בתרא',
        ),
        {'ERA:RISHONIM', LinkTypes.onBookKey},
      );
    });

    test('ספר שאינו "על X" אינו מקבל את המפתח', () {
      expect(
        CommentaryService.linkChipKeys(
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          openBookTitle: 'בבא בתרא',
        ),
        {'ERA:RISHONIM'},
      );
    });

    test('שם ספר ריק או null אינו מוסיף את המפתח', () {
      final link = _link(title: 'רש"י על בבא בתרא', type: 'REFERENCE');

      expect(CommentaryService.linkChipKeys(link), {'ERA:RISHONIM'});
      expect(CommentaryService.linkChipKeys(link, openBookTitle: ''), {
        'ERA:RISHONIM',
      });
      expect(CommentaryService.linkChipKeys(link, openBookTitle: '   '), {
        'ERA:RISHONIM',
      });
    });

    test('המפתח שורד round-trip דרך LinkTypes.normalize', () {
      expect(LinkTypes.normalize(LinkTypes.onBookKey), LinkTypes.onBookKey);
    });

    test('התווית נבנית דינמית משם הספר הפתוח', () {
      expect(
        CommentaryService.chipKeyLabel(
          LinkTypes.onBookKey,
          openBookTitle: 'בבא בתרא',
        ),
        'על בבא בתרא',
      );
    });

    test('קישור חופף מופיע גם בצ׳יפ הדור וגם בצ׳יפ "על הספר"', () {
      final keys = buildLinkChipKeys(
        [
          _link(title: 'רש"י על בבא בתרא', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'REFERENCE'),
        ],
        openBookTitle: 'בבא בתרא',
      );

      expect(keys, containsAll(['ERA:RISHONIM', LinkTypes.onBookKey]));
    });

    test('הצ׳יפ אחרון שבסוגים הייעודיים ולפני צ׳יפי הדורות', () {
      final keys = buildLinkChipKeys(
        [
          _link(title: 'ראשונים א', type: 'EIN_MISHPAT'),
          _link(title: 'ראשונים ג', type: 'REFERENCE'),
          _link(title: 'רש"י על בבא בתרא', type: 'ALT_TOC'),
          _link(title: 'ראשונים ב', type: 'SOURCE'),
        ],
        openBookTitle: 'בבא בתרא',
      );

      expect(keys, [
        'SOURCE',
        'EIN_MISHPAT',
        'ALT_TOC',
        LinkTypes.onBookKey,
        'ERA:RISHONIM',
      ]);
    });

    testWidgets('הצ׳יפ מוצג עם שם הספר הפתוח', (tester) async {
      await _pumpView(
        tester,
        bookTitle: 'בבא בתרא',
        links: [
          _link(title: 'רש"י על בבא בתרא', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'QUOTATION'),
        ],
      );

      expect(find.widgetWithText(Chip, 'על בבא בתרא'), findsOneWidget);
    });

    testWidgets('אין קישורי "על X" — הצ׳יפ לא מוצג', (tester) async {
      await _pumpView(
        tester,
        bookTitle: 'בבא בתרא',
        links: [
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
      );

      expect(find.widgetWithText(Chip, 'על בבא בתרא'), findsNothing);
    });

    testWidgets('שם ספר ריק — אין צ׳יפ ואין קריסה', (tester) async {
      await _pumpView(
        tester,
        bookTitle: '',
        links: [
          _link(title: 'רש"י על בבא בתרא', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'QUOTATION'),
        ],
      );

      expect(find.widgetWithText(Chip, 'על '), findsNothing);
      expect(find.widgetWithText(Chip, 'ראשונים'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('אותו קישור מופיע גם תחת צ׳יפ הדור שלו', (tester) async {
      await _pumpView(
        tester,
        bookTitle: 'בבא בתרא',
        links: [
          _link(title: 'רש"י על בבא בתרא', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'REFERENCE'),
        ],
        selectedLinkTypes: const {'ERA:RISHONIM'},
      );

      expect(find.text('רש"י על בבא בתרא'), findsOneWidget);
      expect(find.text('ראשונים א'), findsOneWidget);
    });

    testWidgets('בחירת "על X" בלבד מציגה רק קישורים כאלה', (tester) async {
      await _pumpView(
        tester,
        bookTitle: 'בבא בתרא',
        links: [
          _link(title: 'רש"י על בבא בתרא', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'אחרונים א', type: 'QUOTATION'),
        ],
        selectedLinkTypes: {LinkTypes.onBookKey},
      );

      expect(find.text('רש"י על בבא בתרא'), findsOneWidget);
      expect(find.text('ראשונים א'), findsNothing);
      expect(find.text('אחרונים א'), findsNothing);
    });

    testWidgets('בחירת "על X" + דור היא איחוד ולא חיתוך', (tester) async {
      await _pumpView(
        tester,
        bookTitle: 'בבא בתרא',
        links: [
          _link(title: 'קצות החושן על בבא בתרא', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'REFERENCE'),
          _link(title: 'זמננו א', type: 'REFERENCE'),
        ],
        selectedLinkTypes: {LinkTypes.onBookKey, 'ERA:RISHONIM'},
      );

      expect(find.text('קצות החושן על בבא בתרא'), findsOneWidget);
      expect(find.text('ראשונים א'), findsOneWidget);
      expect(find.text('זמננו א'), findsNothing);
    });

    testWidgets('לחיצה על הצ׳יפ שולחת את המפתח הקבוע', (tester) async {
      final bloc = await _pumpView(
        tester,
        bookTitle: 'בבא בתרא',
        links: [
          _link(title: 'רש"י על בבא בתרא', type: 'REFERENCE'),
          _link(title: 'ראשונים א', type: 'QUOTATION'),
        ],
      );

      await tester.tap(find.widgetWithText(Chip, 'על בבא בתרא'));
      await tester.pumpAndSettle();

      expect(
        bloc.receivedEvents.whereType<UpdateLinkTypeFilter>().last.linkTypes,
        {LinkTypes.onBookKey},
      );
    });
  });

  group('יציבות הצ׳יפים בדפדוף', () {
    setUp(_seedEras);
    tearDown(CommentaryService.clearEraCache);

    test('chipSourceLinks מסנן קישורי inline ומפרשים', () {
      final inline = Link(
        heRef: 'עוגן',
        index1: 1,
        path2: '/books/ראשונים א.txt',
        index2: 1,
        connectionType: 'REFERENCE',
        start: 3,
        end: 7,
      );
      final commentary = _link(title: 'ראשונים ב', type: 'commentary');
      final reference = _link(title: 'ראשונים ג', type: 'REFERENCE');

      expect(chipSourceLinks([inline, commentary, reference]), [reference]);
    });

    testWidgets('צ׳יפ נבנה מסוג שקיים ב-links אך לא ב-visibleLinks', (
      tester,
    ) async {
      final visible = [_link(title: 'ראשונים א', type: 'EIN_MISHPAT')];

      await _pumpView(
        tester,
        links: [
          ...visible,
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        visibleLinks: visible,
      );

      expect(find.widgetWithText(Chip, 'עין משפט'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'ציטוט'), findsOneWidget);
    });

    testWidgets('בחירה בסוג שאינו בקטע הנראה נשמרת והצ׳יפ נשאר מסומן', (
      tester,
    ) async {
      final visible = [_link(title: 'ראשונים א', type: 'EIN_MISHPAT')];

      await _pumpView(
        tester,
        links: [
          ...visible,
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        visibleLinks: visible,
        selectedLinkTypes: const {'QUOTATION'},
      );

      final quotationChip = tester.widget<Chip>(
        find.widgetWithText(Chip, 'ציטוט'),
      );
      expect(quotationChip.backgroundColor, isNotNull);
      // הסוג הנבחר אינו בקטע הנראה — הרשימה מסוננת לריק, הצ׳יפ לא מתאפס.
      expect(find.text('ראשונים א'), findsNothing);
    });

    testWidgets('הסרת צ׳יפ נבחר אינה מוחקת בחירה שאינה בקטע הנראה', (
      tester,
    ) async {
      final visible = [_link(title: 'ראשונים א', type: 'EIN_MISHPAT')];

      final bloc = await _pumpView(
        tester,
        links: [
          ...visible,
          _link(title: 'ראשונים ב', type: 'QUOTATION'),
        ],
        visibleLinks: visible,
        selectedLinkTypes: const {'QUOTATION', 'EIN_MISHPAT'},
      );

      await tester.tap(find.widgetWithText(Chip, 'עין משפט'));
      await tester.pumpAndSettle();

      expect(
        bloc.receivedEvents.whereType<UpdateLinkTypeFilter>().last.linkTypes,
        {'QUOTATION'},
      );
    });

    testWidgets('גלילה שמשנה רק visibleLinks אינה משנה את שורת הצ׳יפים', (
      tester,
    ) async {
      final first = _link(title: 'ראשונים א', type: 'EIN_MISHPAT');
      final second = _link(title: 'אחרונים א', type: 'QUOTATION');
      final allLinks = [first, second];

      final bloc = await _pumpView(
        tester,
        links: allLinks,
        visibleLinks: [first],
      );

      List<String> chipLabels() => tester
          .widgetList<Chip>(find.byType(Chip))
          .map((chip) => ((chip.label as Text).data)!)
          .toList();

      final before = chipLabels();

      bloc.emitState(
        _loadedState(links: allLinks, visibleLinks: [second]),
      );
      await tester.pumpAndSettle();

      expect(chipLabels(), before);
    });

    testWidgets('המימוש מבוסס זהות: רשימת links חדשה עם תוכן זהה מחושבת מחדש '
        'ומחזירה את אותם צ׳יפים', (tester) async {
      final allLinks = [
        _link(title: 'ראשונים א', type: 'EIN_MISHPAT'),
        _link(title: 'אחרונים א', type: 'QUOTATION'),
      ];

      final bloc = await _pumpView(tester, links: allLinks);

      List<String> chipLabels() => tester
          .widgetList<Chip>(find.byType(Chip))
          .map((chip) => ((chip.label as Text).data)!)
          .toList();
      final before = chipLabels();

      bloc.emitState(_loadedState(links: List.of(allLinks)));
      await tester.pumpAndSettle();

      expect(chipLabels(), before);
    });
  });
}

/// מזין את מטמון הדורות ידנית — בטסטים אין DB, ובלי זה כל הספרים ייפלו
/// ל-[CommentaryEra.other].
void _seedEras() {
  CommentaryService.clearEraCache();
  CommentaryService.seedEraCache(const {
    'בראשית': CommentaryEra.torahShebichtav,
    'חז"ל א': CommentaryEra.chazal,
    'ראשונים א': CommentaryEra.rishonim,
    'ראשונים ב': CommentaryEra.rishonim,
    'ראשונים ג': CommentaryEra.rishonim,
    'ראשונים ד': CommentaryEra.rishonim,
    'אחרונים א': CommentaryEra.acharonim,
    'זמננו א': CommentaryEra.modern,
    'רש"י על בבא בתרא': CommentaryEra.rishonim,
    'רשב"ם על בבא בתרא': CommentaryEra.rishonim,
    'קצות החושן על בבא בתרא': CommentaryEra.acharonim,
  });
}

Future<_RecordingTextBookBloc> _pumpView(
  WidgetTester tester, {
  required List<Link> links,
  List<Link>? visibleLinks,
  Set<String> selectedLinkTypes = const {},
  String bookTitle = 'ספר בדיקה',
  bool settle = true,
}) async {
  final bloc = _RecordingTextBookBloc(
    _loadedState(
      links: links,
      visibleLinks: visibleLinks,
      selectedLinkTypes: selectedLinkTypes,
      bookTitle: bookTitle,
    ),
  );
  addTearDown(bloc.close);
  final settingsBloc = _TestSettingsBloc(SettingsState.initial());
  addTearDown(settingsBloc.close);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: SelectedLineLinksView(
            openBookCallback: (_) {},
            fontSize: 18,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return bloc;
}

Link _link({required String title, required String type}) {
  return Link(
    heRef: 'הפניה $title',
    index1: 1,
    path2: '/books/$title.txt',
    index2: 1,
    connectionType: type,
  );
}

TextBookLoaded _loadedState({
  List<Link> links = const [],
  List<Link>? visibleLinks,
  Set<String> selectedLinkTypes = const {},
  String bookTitle = 'ספר בדיקה',
}) {
  return TextBookLoaded(
    book: TextBook(title: bookTitle),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: links,
    visibleLinks: visibleLinks ?? links,
    selectedLinkTypes: selectedLinkTypes,
    linksByLine: const {},
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

class _RecordingTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  final List<TextBookEvent> receivedEvents = [];

  _RecordingTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) => receivedEvents.add(event));
  }

  void emitState(TextBookState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
