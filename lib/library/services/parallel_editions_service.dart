import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/database/plugin_database_service.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/services/plugin_external_book_loader.dart';
import 'package:otzaria/plugins/services/plugin_external_editions_registry.dart';

/// מהדורה מקבילה של הספר הפתוח, לשימוש הלחצן המובנה בסרגל העיון.
class ParallelEdition {
  final Book book;

  /// המהדורה המובנית (עמית באותה ספרייה, למשל PDF של הש"ס) — היא הפעולה
  /// הראשית של הלחצן כל עוד קיימת; מהדורות של ספקים חיצוניים באות אחריה.
  final bool isCompanion;

  /// שם לתצוגה במקום כותרת הספר — שם הגרסה של ספר אישי.
  final String? label;

  const ParallelEdition({
    required this.book,
    required this.isCompanion,
    this.label,
  });
}

/// איתור מהדורות מקבילות לספר הפתוח — מובנות ומקומיות בלבד.
///
/// ללא שום תקשורת עם שירות חיצוני (קטלוג + דיסק בלבד):
/// 1. ספר עמית בספריית אוצריא (טקסט↔PDF של אותו ספר).
/// 2. מהדורות היברובוקס המקומיות, לפי טבלת המיפוי בקטלוג החיצוני.
/// 3. מהדורות של ספקים שתוספים הצהירו עליהם (`externalEditions`).
/// 4. גרסאות אישיות (קובצי `גרסאות.csv`) — של ספר אישי או של ספר רשמי/מצורף.
class ParallelEditionsService {
  ParallelEditionsService._();

  /// תקרת המהדורות לכל קונפיגורציה — כמו מכסת הילדים של לחצן מפוצל.
  static const int _maxEditionsPerConfig = 20;

  /// נקודות הזרקה לבדיקות: הרצת שאילתת ה-DB וטעינת הספרים החיצוניים.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(
    InstalledPlugin plugin,
    Map<String, dynamic> spec,
  )
  queryRunner = (plugin, spec) => PluginDatabaseService().query(plugin, spec);

  @visibleForTesting
  static Future<List<Book>> Function(String provider, Set<Object> externalIds)
  externalBooksLoader = loadExternalBooksByProvider;

  /// המיפוי המובנה של היברובוקס בקטלוג החיצוני, בשני הכיוונים.
  @visibleForTesting
  static Future<List<int>> Function(int otzariaId) builtInExternalIdsFor =
      (id) => ExternalCatalogRepository.instance.getHebrewBookIdsForOtzariaId(
        id,
      );

  @visibleForTesting
  static Future<List<int>> Function(int externalId) builtInOtzariaIdsFor =
      (id) => ExternalCatalogRepository.instance.getOtzariaIdsForHebrewBookId(
        id,
      );

  static const String _builtInProvider = 'hebrewbooks';

  /// מחזיר את המהדורות בסדר תצוגה: המובנית ראשונה (כשקיימת), ואז מהדורות
  /// הספקים החיצוניים לפי איכות ההתאמה. רשימה ריקה = אין לחצן.
  static Future<List<ParallelEdition>> find(Book current) async {
    final editions = <ParallelEdition>[];

    final companionType = current is PdfBook ? TextBook : PdfBook;
    final library = await DataRepository.instance.library;
    final companion = library.getCompanionBook(current, companionType);
    if (companion != null) {
      editions.add(ParallelEdition(book: companion, isCompanion: true));
    }

    final provider = DatabaseLibraryProvider.instance;
    final versions = current.isUserBook
        ? provider.getUserBookVersions(current)
        : provider.getPersonalVersionsOf(current);
    for (final version in versions) {
      final book = version.separateBook;
      if (book == null ||
          (book.source == current.source && book.id == current.id)) {
        continue;
      }
      editions.add(
        ParallelEdition(
          book: book,
          isCompanion: false,
          label: version.displayTitle,
        ),
      );
    }

    final configs = PluginExternalEditionsRegistry.instance.configs;
    // המיפוי שייך לקטלוג שהאפליקציה מורידה, ולכן לא תלוי בתוסף; תוסף שמצהיר
    // על אותו ספק מחליף אותו כדי שלא יופיעו כפילויות.
    if (!configs.any((config) => config.provider == _builtInProvider)) {
      try {
        for (final book in await builtInEditionsFor(current)) {
          editions.add(ParallelEdition(book: book, isCompanion: false));
        }
      } catch (e) {
        debugPrint('ParallelEditionsService: built-in editions failed: $e');
      }
    }

    for (final config in configs) {
      try {
        for (final book in await _externalEditions(current, config)) {
          editions.add(ParallelEdition(book: book, isCompanion: false));
        }
      } catch (e) {
        // קונפיגורציה שנכשלת (DB חסר, policy) לא מפילה את הלחצן כולו.
        debugPrint(
          'ParallelEditionsService: ${config.provider} editions failed: $e',
        );
      }
    }
    return editions;
  }

  /// המנוע הגנרי לקונפיגורציה בודדת — חשוף לבדיקות דרך נקודות ההזרקה.
  @visibleForTesting
  static Future<List<Book>> externalEditionsFor(
    Book current,
    PluginExternalEditionsConfig config,
  ) => _externalEditions(current, config);

  /// מהדורות היברובוקס מהמיפוי המובנה — חשוף לבדיקות דרך נקודות ההזרקה.
  @visibleForTesting
  static Future<List<Book>> builtInEditionsFor(Book current) => _resolve(
    current,
    provider: _builtInProvider,
    externalIdsFor: (otzariaIds) async => [
      for (final id in otzariaIds) ...await builtInExternalIdsFor(id),
    ],
    otzariaIdsFor: builtInOtzariaIdsFor,
  );

  static Future<List<Book>> _externalEditions(
    Book current,
    PluginExternalEditionsConfig config,
  ) => _resolve(
    current,
    provider: config.provider,
    externalIdsFor: (otzariaIds) => _selectIds(
      config,
      select: config.externalIdColumn,
      whereColumn: config.otzariaIdColumn,
      values: otzariaIds,
    ),
    otzariaIdsFor: (externalId) => _selectIds(
      config,
      select: config.otzariaIdColumn,
      whereColumn: config.externalIdColumn,
      values: [externalId],
    ),
  );

  static Future<List<Book>> _resolve(
    Book current, {
    required String provider,
    required Future<List<int>> Function(List<int> otzariaIds) externalIdsFor,
    required Future<List<int>> Function(int externalId) otzariaIdsFor,
  }) async {
    final external = PluginBookIdentity.externalOf(current);
    final currentExternalId = external?.provider == provider
        ? PluginBookIdentity.parseId(external?.id)
        : null;

    List<int> externalIds;
    if (currentExternalId != null) {
      // ספר של הספק פתוח: מהדורות מקבילות הן ספרי הספק האחרים הממופים
      // לאותם ספרי אוצריא (שני צעדים בטבלת המיפוי).
      final otzariaIds = await otzariaIdsFor(currentExternalId);
      if (otzariaIds.isEmpty) return const [];
      externalIds = [...await externalIdsFor(otzariaIds.toSet().toList())];
      externalIds.removeWhere((id) => id == currentExternalId);
    } else {
      // המיפוי ממופתח במזהי seforim.db; מזהה של מסד אחר חופף להם ואינו אותו ספר.
      final otzariaId = current.source.isOfficial ? current.id : null;
      if (otzariaId == null) return const [];
      externalIds = await externalIdsFor([otzariaId]);
    }
    // הסרת כפילויות תוך שימור סדר איכות ההתאמה של המיפוי.
    final orderedIds = <int>[];
    final seen = <int>{};
    for (final id in externalIds) {
      if (seen.add(id)) orderedIds.add(id);
    }
    if (orderedIds.isEmpty) return const [];

    // רק מהדורות שנפתחות מקומית — ספר שקיים בקטלוג החיצוני בלבד (נפתח
    // באתר הספק) אינו "מהדורה מקבילה" בקורא.
    final books = await externalBooksLoader(
      provider,
      orderedIds.toSet(),
    );
    final byId = <int, Book>{};
    for (final book in books) {
      if (book is ExternalLibraryBook) continue;
      final bookExternal = PluginBookIdentity.externalOf(book);
      final id = bookExternal?.provider == provider
          ? PluginBookIdentity.parseId(bookExternal?.id)
          : null;
      if (id != null) byId.putIfAbsent(id, () => book);
    }
    return [for (final id in orderedIds) ?byId[id]];
  }

  /// שאילתת עמודה בודדת בטבלת המיפוי, דרך שירות ה-DB לתוספים — כך שה-policy
  /// של המקור (טבלאות, עמודות, מכסות) נאכף גם על המנוע הזה.
  static Future<List<int>> _selectIds(
    PluginExternalEditionsConfig config, {
    required String select,
    required String whereColumn,
    required List<int> values,
  }) async {
    final result = await queryRunner(config.plugin, {
      'sourceId': config.sourceId,
      'from': {'table': config.table, 'alias': 'm'},
      'select': [
        {'expr': 'm.$select', 'as': 'value'},
      ],
      'where': {'op': 'in', 'left': 'm.$whereColumn', 'value': values},
      if (config.orderBy.isNotEmpty)
        'orderBy': [
          for (final order in config.orderBy)
            {
              'expr': 'm.${order.column}',
              'direction': order.descending ? 'desc' : 'asc',
            },
        ],
      'limit': _maxEditionsPerConfig,
      'rowFormat': 'object',
    });
    final rows = result['rows'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map && row['value'] is int) row['value'] as int,
    ];
  }
}
