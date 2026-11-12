import 'dart:convert';

import 'package:otzaria/data/data_providers/external_catalog_mapper.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_selection_action.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';

class PluginLibraryBooksException implements Exception {
  final String message;

  /// הספק אינו רשום לתוסף הקורא (ולא שהרשימה עצמה פגומה).
  final bool notFound;

  const PluginLibraryBooksException(this.message, {this.notFound = false});

  @override
  String toString() => message;
}

/// ספק ספרים שתוסף הצהיר עליו ב-`contributes.startup.libraryBooks`.
class PluginLibraryBookProvider {
  static const int maxItemsPerPlugin = 2;
  // מוצג בכפתור "פתח ב..." שבתצוגה המקדימה.
  static const int maxTitleLength = 40;

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_.\-]{1,64}$');
  static final RegExp _providerPattern = RegExp(r'^[a-z][a-z0-9\-]{1,63}$');

  final String pluginId;
  final String id;
  final String provider;
  final String title;
  final String? iconName;
  final PluginWhenCondition? when;

  /// פעולת host שמבצעים בלחיצה על ספר, בלי להעיר את מנוע התוסף. בלעדיה
  /// הלחיצה נמסרת לתוסף באירוע `library.providerBook.openRequested`.
  final Map<String, dynamic>? openAction;

  const PluginLibraryBookProvider({
    required this.pluginId,
    required this.id,
    required this.provider,
    required this.title,
    this.iconName,
    this.when,
    this.openAction,
  });

  /// משמש גם את הוולידציה בעת אריזה, ולכן אינו תלוי במצב התוכנה.
  factory PluginLibraryBookProvider.parse(
    String pluginId,
    Map<String, dynamic> item, {
    String? fallbackIconName,
  }) {
    const allowed = {'id', 'provider', 'title', 'icon', 'when', 'openAction'};
    final unknown = item.keys.where((key) => !allowed.contains(key));
    if (unknown.isNotEmpty) {
      throw PluginLibraryBooksException(
        'libraryBooks: שדה לא מוכר "${unknown.first}"',
      );
    }
    final id = item['id'];
    if (id is! String || !_idPattern.hasMatch(id)) {
      throw const PluginLibraryBooksException(
        'libraryBooks.id חייב להיות מזהה (עד 64 תווים)',
      );
    }
    final provider = item['provider'];
    if (provider is! String || !isValidProviderName(provider)) {
      throw const PluginLibraryBooksException(
        'libraryBooks.provider חייב להיות שם ספק באותיות לטיניות קטנות '
        '(2–64 תווים), שאינו שם של ספק מובנה',
      );
    }
    final title = item['title'];
    if (title is! String ||
        title.trim().isEmpty ||
        title.length > maxTitleLength) {
      throw const PluginLibraryBooksException(
        'libraryBooks.title חייב להיות שם הספק לתצוגה (עד '
        '$maxTitleLength תווים)',
      );
    }
    final icon = item['icon'];
    if (icon != null &&
        (icon is! String ||
            !PluginManifest.toolTabIconNamePattern.hasMatch(icon))) {
      throw const PluginLibraryBooksException(
        'libraryBooks.icon חייב להיות שם אייקון בגודל 24px',
      );
    }
    PluginWhenCondition? when;
    if (item['when'] case final rawWhen?) {
      try {
        when = PluginWhenCondition.fromJson(rawWhen);
      } on PluginWhenConditionException catch (error) {
        throw PluginLibraryBooksException('libraryBooks.when לא תקין: $error');
      }
    }
    // מבנה בלבד: הצהרת ההרשאה נבדקת בוולידטור ההתקנה ושוב בזמן הלחיצה.
    Map<String, dynamic>? openAction;
    if (item['openAction'] case final rawAction?) {
      if (rawAction is! Map) {
        throw const PluginLibraryBooksException(
          'libraryBooks.openAction חייב להיות אובייקט',
        );
      }
      try {
        openAction = Map<String, dynamic>.from(rawAction);
        DeclarativeSelectionAction.validateTemplate(
          openAction,
          source: DeclarativeClickSource.libraryBook,
        );
      } on DeclarativeProgramException catch (error) {
        throw PluginLibraryBooksException(
          'libraryBooks.openAction לא תקין: $error',
        );
      }
    }
    return PluginLibraryBookProvider(
      pluginId: pluginId,
      id: id,
      provider: provider,
      title: title.trim(),
      iconName: icon as String? ?? fallbackIconName,
      when: when,
      openAction: openAction,
    );
  }

  /// אותה הצהרה: רישום חוזר שלה אינו שינוי.
  bool sameAs(PluginLibraryBookProvider other) =>
      pluginId == other.pluginId &&
      id == other.id &&
      provider == other.provider &&
      title == other.title &&
      iconName == other.iconName &&
      jsonEncode(when?.toJson()) == jsonEncode(other.when?.toJson()) &&
      jsonEncode(openAction) == jsonEncode(other.openAction);

  /// שם שהמזהה שלו (`<provider>:<id>`) נקרא כספק מובנה אסור: חלק מהמסכים
  /// מזהים את הספקים המובנים לפי מחרוזת חלקית (`hb:`, `otzar` וכו'), וכך
  /// גם זיהוי הספרים בחוזה התוספים.
  static bool isValidProviderName(String provider) =>
      _providerPattern.hasMatch(provider) &&
      ExternalCatalogMapper.catalogFromLinkOrId(
            externalLibraryId: '$provider:1',
          ) ==
          null;
}

/// ספר אחד ברשימה שתוסף שלח. ההודעות באנגלית, כמו שאר שגיאות ה-bridge.
class PluginLibraryBookEntry {
  static const int maxBooksPerProvider = 50000;
  static const int maxTitleLength = 300;
  static const int maxAuthorLength = 200;
  static const int maxCategoryPathLength = 300;

  /// תיאור הספר: מוצג בחלון "אודות הספר" ובריחוף על כפתור המידע.
  static const int maxDescriptionLength = 2000;

  /// סך התווים בכל התיאורים של ספק. התיאורים נשמרים ב-DB ונטענים לזיכרון
  /// עם הרשימה, ולכן הם חסומים גם בסכום: 50,000 תיאורים באורך מלא היו כ-100MB.
  static const int maxTotalDescriptionLength = 5000000;

  /// תווי בקרה ותווי כיוון: שורה חדשה או סימן RTL/LTR בשם ספר היו שוברים
  /// את השורה בכרטיס ואת סדר הטקסט סביבו.
  static final RegExp _controlCharacters = RegExp(
    r'[\u0000-\u001F\u007F-\u009F\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  );
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _lineBreaks = RegExp(r'\r\n|[\r\n]');
  static final RegExp _manyNewlines = RegExp(r'\n{3,}');

  final int id;
  final String title;
  final String? author;

  /// נתיב מנורמל בצורת `library.getTree`: `/שו"ת/אחרונים`.
  final String? categoryPath;

  /// טקסט רגיל בלי עיצוב; שבירות שורה ופסקאות נשמרות (ראו
  /// [_normalizeDescription]).
  final String? description;

  const PluginLibraryBookEntry({
    required this.id,
    required this.title,
    this.author,
    this.categoryPath,
    this.description,
  });

  /// מזהה כפול אסור: לחיצה על ספר נמסרת לתוסף לפי המזהה בלבד. [stored] —
  /// הרשימה מהאחסון, בצורה המקוצרת.
  static List<PluginLibraryBookEntry> parseList(
    Object? raw, {
    bool stored = false,
  }) {
    if (raw is! List) {
      throw const PluginLibraryBooksException('books must be an array');
    }
    if (raw.length > maxBooksPerProvider) {
      throw const PluginLibraryBooksException(
        'books is limited to $maxBooksPerProvider books per provider',
      );
    }
    final seen = <int>{};
    final entries = <PluginLibraryBookEntry>[];
    var descriptionLength = 0;
    for (var index = 0; index < raw.length; index++) {
      final entry = PluginLibraryBookEntry.parse(
        raw[index],
        index,
        stored: stored,
      );
      if (!seen.add(entry.id)) {
        throw PluginLibraryBooksException(
          'books[$index]: duplicate id ${entry.id}',
        );
      }
      descriptionLength += entry.description?.length ?? 0;
      if (descriptionLength > maxTotalDescriptionLength) {
        throw PluginLibraryBooksException(
          'books[$index]: the descriptions are longer than '
          '$maxTotalDescriptionLength characters in total',
        );
      }
      entries.add(entry);
    }
    return entries;
  }

  /// מהאחסון: מערך `[id, title, author, categoryPath]`, ועוד `description`
  /// כשיש, שחוסך כמחצית מהנפח ברשימה של אלפי ספרים. מהתוסף: אובייקט בלבד.
  factory PluginLibraryBookEntry.parse(
    Object? raw,
    int index, {
    bool stored = false,
  }) {
    final Object? id;
    final Object? title;
    final Object? author;
    final Object? categoryPath;
    final Object? description;
    if (raw is Map) {
      id = raw['id'];
      title = raw['title'];
      author = raw['author'];
      categoryPath = raw['categoryPath'];
      description = raw['description'];
    } else if (stored && raw is List && (raw.length == 4 || raw.length == 5)) {
      id = raw[0];
      title = raw[1];
      author = raw[2];
      categoryPath = raw[3];
      description = raw.length == 5 ? raw[4] : null;
    } else {
      throw PluginLibraryBooksException('books[$index] must be an object');
    }
    if (id is! int || id <= 0) {
      throw PluginLibraryBooksException(
        'books[$index].id must be a positive integer',
      );
    }

    String? text(
      Object? value,
      String field,
      int max, {
      String? Function(String)? normalize,
      String Function(String) cleaner = _normalizeLine,
    }) {
      if (value == null) return null;
      if (value is! String) {
        throw PluginLibraryBooksException(
          'books[$index].$field must be a string',
        );
      }
      var clean = cleaner(value);
      // אחרי הנרמול: הערך נשמר כך, ונבדק שוב בטעינה מהאחסון.
      if (normalize != null) clean = normalize(clean) ?? '';
      if (clean.length > max) {
        throw PluginLibraryBooksException(
          'books[$index].$field is longer than $max characters',
        );
      }
      return clean.isEmpty ? null : clean;
    }

    final bookTitle = text(title, 'title', maxTitleLength);
    if (bookTitle == null) {
      throw PluginLibraryBooksException('books[$index].title is required');
    }
    return PluginLibraryBookEntry(
      id: id,
      title: bookTitle,
      author: text(author, 'author', maxAuthorLength),
      categoryPath: text(
        categoryPath,
        'categoryPath',
        maxCategoryPathLength,
        normalize: _normalizePath,
      ),
      description: text(
        description,
        'description',
        maxDescriptionLength,
        cleaner: _normalizeDescription,
      ),
    );
  }

  /// שם, מחבר ונתיב הם שורה אחת: תווי בקרה וכיוון ורווחים רצופים הופכים
  /// לרווח יחיד.
  static String _normalizeLine(String value) => value
      .replaceAll(_controlCharacters, ' ')
      .replaceAll(_whitespace, ' ')
      .trim();

  /// תיאור: כל שורה מנורמלת כמו [_normalizeLine], ושבירות השורה נשמרות
  /// (CRLF ו-CR הופכים ל-LF). שורות ריקות רצופות מצטמצמות לאחת, כך שנשארת
  /// הפרדת פסקאות אך לא רווח אנכי שרירותי.
  static String _normalizeDescription(String value) => [
    for (final line in value.split(_lineBreaks)) _normalizeLine(line),
  ].join('\n').replaceAll(_manyNewlines, '\n\n').trim();

  /// `שו"ת/ אחרונים/` ← `/שו"ת/אחרונים`; נתיב בלי שם אף תיקייה ← `null`.
  static String? _normalizePath(String value) {
    final segments = [
      for (final segment in value.split('/'))
        if (segment.trim().isNotEmpty) segment.trim(),
    ];
    return segments.isEmpty ? null : '/${segments.join('/')}';
  }

  /// בלי תיאור: ארבעה איברים, כמו לפני שהשדה נוסף, כך שגם מארח ישן קורא אותה.
  List<Object?> toStorage() => [
    id,
    title,
    author,
    categoryPath,
    if (description != null) description,
  ];

  /// בכרטיס הנתיב מוצג כמו אצל ספרי אוצריא: `שו"ת, אחרונים`.
  ExternalLibraryBook toBook(String provider) => ExternalLibraryBook(
    title: title,
    id: id,
    author: author,
    categoryPath: categoryPath?.substring(1).replaceAll('/', ', '),
    heDesc: description,
    link: '',
    externalLibraryId: '$provider:$id',
  );
}
