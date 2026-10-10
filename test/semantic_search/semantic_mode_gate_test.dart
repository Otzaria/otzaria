import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_feedback_snapshots.dart';
import 'package:otzaria/semantic_search/models/semantic_mode_gate.dart';

SemanticAvailability _availability(
  SemanticAvailabilityPhase phase, {
  bool consent = true,
  SemanticHiddenReason? hiddenReason,
}) => SemanticAvailability(
  phase: phase,
  consentGranted: consent,
  hiddenReason: hiddenReason,
);

void main() {
  group('נראות המצב', () {
    test('בשחרור מוסתר רק בשלב hidden', () {
      for (final phase in SemanticAvailabilityPhase.values) {
        expect(
          isSemanticModeVisible(_availability(phase), debug: false),
          phase != SemanticAvailabilityPhase.hidden,
          reason: phase.name,
        );
      }
    });

    test('בפיתוח מוצג תמיד', () {
      for (final phase in SemanticAvailabilityPhase.values) {
        expect(isSemanticModeVisible(_availability(phase), debug: true), true);
      }
    });
  });

  group('תצוגה מקדימה בפיתוח', () {
    test('דורשת פיתוח והסכמה, וחסרים מנוע או נתונים', () {
      final missing = _availability(
        SemanticAvailabilityPhase.needsDownload,
      );
      final hidden = _availability(
        SemanticAvailabilityPhase.hidden,
        hiddenReason: SemanticHiddenReason.engineNotInBuild,
      );
      expect(isSemanticDebugPreview(missing, debug: true), isTrue);
      expect(isSemanticDebugPreview(hidden, debug: true), isTrue);
      expect(isSemanticDebugPreview(missing, debug: false), isFalse);
      expect(isSemanticDebugPreview(hidden, debug: false), isFalse);
      expect(
        isSemanticDebugPreview(
          _availability(SemanticAvailabilityPhase.hidden, consent: false),
          debug: true,
        ),
        isFalse,
      );
      expect(
        isSemanticDebugPreview(
          _availability(SemanticAvailabilityPhase.ready),
          debug: true,
        ),
        isFalse,
      );
    });

    test('בשחרור אפשר לחפש רק כשהכול מוכן', () {
      expect(
        canRunSemanticSearch(
          _availability(SemanticAvailabilityPhase.ready),
          debug: false,
        ),
        isTrue,
      );
      expect(
        canRunSemanticSearch(
          _availability(SemanticAvailabilityPhase.needsDownload),
          debug: false,
        ),
        isFalse,
      );
    });
  });

  group('היקף החיפוש', () {
    test('קטגוריות, ספרים רשמיים וממדים נשמרים; ספרים אישיים ומצורפים לא', () {
      expect(
        semanticScopeFacets({
          '/תנ״ך',
          '/הלכה/שולחן ערוך',
          '/era/ראשונים',
          '/תנ״ך/id:12',
          '/ספרים אישיים/שלי',
          '/uid:4',
          '/הלכה/db:lib:3',
        }),
        ['/era/ראשונים', '/הלכה/שולחן ערוך', '/תנ״ך', '/תנ״ך/id:12'],
      );
    });

    test('בחירה ריקה או "הכול" — כל הספרייה', () {
      expect(semanticScopeFacets(const {}), ['/']);
      expect(semanticScopeFacets({'/', '/תנ״ך'}), ['/']);
      expect(semanticScopeFacets({'/uid:4'}), ['/']);
      expect(semanticScopeFacets({'/', '/era/ראשונים', '/תנ״ך'}), [
        '/',
        '/era/ראשונים',
      ]);
      expect(semanticScopeFacets({'/era/ראשונים'}), ['/', '/era/ראשונים']);
    });
  });

  test('פלטפורמה לא נתמכת חסומה גם בדיבאג וגם בלי הסכמה', () {
    for (final debug in [false, true]) {
      for (final consent in [false, true]) {
        final unsupported = _availability(
          SemanticAvailabilityPhase.hidden,
          consent: consent,
          hiddenReason: SemanticHiddenReason.unsupportedPlatform,
        );
        expect(isSemanticModeVisible(unsupported, debug: debug), isFalse);
        expect(isSemanticDebugPreview(unsupported, debug: debug), isFalse);
        expect(canRunSemanticSearch(unsupported, debug: debug), isFalse);
      }
    }
  });
  group('תמונות הטלמטריה', () {
    test('הדירוג מתחיל ב-1 ונספר על פני כל הרשימה', () {
      expect(semanticResultRank(0, 0), 1);
      expect(semanticResultRank(30, 4), 35);
    });

    test('טקסט פשוט וקטעים מודגשים מתוך ה-HTML', () {
      final text = semanticSnippetText(
        'ויאמר <font color="red">כבד</font> את <font color="red">אביך</font>'
        '<font color="red"> ואת</font> אמך',
      );
      expect(text.plain, 'ויאמר כבד את אביך ואת אמך');
      expect(text.matched, ['כבד', 'אביך ואת']);
    });

    test('התאמה לפי עניין בלבד — בלי קטעים מודגשים', () {
      final text = semanticSnippetText('כבד את אביך &amp; אמך');
      expect(text.plain, 'כבד את אביך & אמך');
      expect(text.matched, isEmpty);
    });
  });

  group('פרטיות התשובה', () {
    SemanticResultsPage page(String? reason) => SemanticResultsPage(
      items: const [],
      hasMore: false,
      executedMode: 'lexicalOnly',
      semanticAvailable: false,
      fallbackReason: reason,
      fallbackKind: 'onnxRuntimeMissing',
      latencyMs: 1,
      totalCount: 0,
      lexicalTotalCount: 0,
      countsAreExact: true,
      truncated: false,
      candidateWindowTruncated: false,
    );

    test('טקסט חופשי של המנוע אינו נשלח; רק fallbackKind וערך מוכר', () {
      final free = buildSemanticResponseSnapshot(
        page(r'failed to load C:\Users\moshe\AppData\onnxruntime.dll'),
      );
      expect(free.fallbackReason, isNull);
      expect(free.fallbackKind, 'onnxRuntimeMissing');
      expect(
        buildSemanticResponseSnapshot(
          page(kSemanticDebugPreviewFallbackReason),
        ).fallbackReason,
        kSemanticDebugPreviewFallbackReason,
      );
    });
  });

  group('קטגוריות של מסדים מצורפים', () {
    Category category(String title, List<Book> books) => Category(
      title: title,
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: books,
      parent: null,
    );

    test('קטגוריה שיש בה רק ספרים ממסד מצורף אינה בהיקף', () {
      final library = Library(
        categories: [
          category('תנ״ך', [TextBook(title: 'בראשית')]),
          category('אוסף מצורף', [
            TextBook(title: 'ספר', source: BookSource.attached('lib')),
          ]),
        ],
      );
      final filter = officialCategoryFilter(library);

      expect(
        semanticScopeFacets({
          '/תנ״ך',
          '/אוסף מצורף',
          '/לא קיים',
        }, isOfficialCategory: filter),
        ['/תנ״ך'],
      );
      expect(officialCategoryFilter(null), isNull);
    });
  });
}
