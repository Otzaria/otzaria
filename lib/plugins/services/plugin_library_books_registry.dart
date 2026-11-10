import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_library_book_provider.dart';
import 'package:otzaria/plugins/models/plugin_library_books_filter.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';

/// ספרים לרשומות שהשתנו, ולכל רשומה מקומה ברשימה הקודמת (‎-1: ספר חדש
/// מ-`fresh`, לפי הסדר).
typedef _BuiltBooks = ({List<ExternalLibraryBook> fresh, Int32List reused});

typedef PluginLibraryBooksDispatch =
    Future<void> Function(
      String pluginId,
      String topic,
      Map<String, dynamic> payload, {
      int? viewId,
      AppWindowKeys? windowKeys,
    });

/// ביצוע `openAction` של ספק — מסופק ע"י DeclarativePluginHost, בלי להעיר את
/// מנוע התוסף.
typedef PluginLibraryBookActionDispatcher =
    Future<void> Function(
      String pluginId,
      Map<String, dynamic> actionTemplate,
      Map<String, dynamic> bookPayload,
    );

/// ספרים שתוספים מוסיפים לאיתור הספרים במסך הספרייה. הרשימה נשמרת ב-DB
/// ונטענת בסנכרון התוספים, כדי שתופיע גם לפני שמנוע התוסף עולה.
class PluginLibraryBooksRegistry extends ChangeNotifier {
  PluginLibraryBooksRegistry._()
    : _dispatch = _dispatchToPlugin,
      _conditions = PluginConditionEvaluator.instance,
      _repository = PluginRegistryRepository() {
    _conditions.addListener(_onConditionsChanged);
  }

  static PluginLibraryBooksRegistry _instance = PluginLibraryBooksRegistry._();

  static PluginLibraryBooksRegistry get instance => _instance;

  @visibleForTesting
  static set instance(PluginLibraryBooksRegistry value) => _instance = value;

  @visibleForTesting
  PluginLibraryBooksRegistry.forTesting({
    PluginLibraryBooksDispatch? dispatch,
    required this._conditions,
    required this._repository,
  }) : _dispatch = dispatch ?? _dispatchToPlugin {
    _conditions.addListener(_onConditionsChanged);
  }

  static Future<void> _dispatchToPlugin(
    String pluginId,
    String topic,
    Map<String, dynamic> payload, {
    int? viewId,
    AppWindowKeys? windowKeys,
  }) => PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
    pluginId,
    topic,
    payload,
    preferBackground: true,
    viewId: viewId,
    windowKeys: windowKeys,
  );

  static const String openRequestedTopic = 'library.providerBook.openRequested';

  static const String _storageNamespace = 'otzaria.library-books';
  static const int _storageVersion = 1;

  final PluginLibraryBooksDispatch _dispatch;
  final PluginConditionEvaluator _conditions;
  final PluginRegistryRepository _repository;

  final Map<String, PluginLibraryBookProvider> _providers = {};
  final Map<String, List<ExternalLibraryBook>> _books = {};

  /// הרשימה המוצגת, להשוואה: שליחה חוזרת של אותה רשימה (בכל הפעלה של
  /// התוסף) אינה כותבת ל-DB ואינה מריצה מחדש את החיפוש המוצג.
  final Map<String, List<PluginLibraryBookEntry>> _entries = {};

  /// הרשימה האחרונה שהתקבלה ועדיין נשמרת. היא, ולא [_entries], קובעת אם
  /// שליחה חדשה זהה: אחרת A ואחריו מיד הרשימה המוצגת היו משאירים את A.
  final Map<String, List<PluginLibraryBookEntry>> _pending = {};

  /// התוסף שיצר כל ספר. ספר שנשאר בתוצאות אחרי שתוסף הוסר אינו נמסר
  /// לתוסף אחר שרשם בינתיים ספק באותו שם.
  final Expando<String> _creator = Expando('plugin library book creator');

  /// מונה לכל ספק: כתיבה או טעינה שהסתיימה אחרי שינוי מאוחר יותר (רשימה
  /// חדשה, איפוס, הסרה) אינה דורסת אותו.
  final Map<String, int> _revisions = {};

  /// רשימות מפוענחות ב-isolate במקביל, ומוחלות לפי סדר השליחה.
  final Map<String, Future<void>> _parseTurns = {};

  /// איפוס או הסרה בזמן הפענוח: רשימה שנשלחה לפניהם לא תיכתב.
  final Map<String, int> _resets = {};

  /// הספקים שהוצגו בהודעה האחרונה. המעריך מודיע על כל מפתח של כל תוסף,
  /// וכל הודעה כאן מריצה מחדש את החיפוש המוצג בספרייה.
  Set<String> _visibleProviders = const {};
  List<ExternalLibraryBook> _visibleBooks = const [];

  @visibleForTesting
  Iterable<PluginLibraryBookProvider> get providers => _providers.values;

  bool hasProviderFor(String pluginId) =>
      _providers.values.any((provider) => provider.pluginId == pluginId);

  bool isOwner(String pluginId, String provider) =>
      _providers[provider]?.pluginId == pluginId;

  @visibleForTesting
  List<ExternalLibraryBook> booksOf(String provider) =>
      List.unmodifiable(_books[provider] ?? const []);

  /// ספרי הספקים שתנאי ה-`when` שלהם מתקיים כרגע.
  List<ExternalLibraryBook> get visibleBooks => _visibleBooks;

  /// מצב כפתור `providerBooksFilter`. ההאזנה לשינוי היא ההזדמנות להריץ מחדש
  /// את החיפוש המוצג; הסינון חל על תוצאות החיפוש בלבד.
  final ValueNotifier<PluginLibraryBooksFilter> sourceFilter = ValueNotifier(
    PluginLibraryBooksFilter.all,
  );

  /// לחיצה על כפתור `providerBooksFilter` של [pluginId]; מחזיר את המצב
  /// החדש שלו. תוסף בלי ספק רשום אינו משנה דבר.
  PluginLibraryBooksSource cycleSource(String pluginId) {
    if (hasProviderFor(pluginId)) {
      sourceFilter.value = sourceFilter.value.pressedBy(pluginId);
    }
    return sourceFilter.value.sourceFor(pluginId);
  }

  void resetSourceFilter() => sourceFilter.value = PluginLibraryBooksFilter.all;

  /// הספרים מבחוץ שיצטרפו לחיפוש לפי [sourceFilter]: בלי ספרים במצב
  /// "ספרי הספרייה בלבד", ורק של התוסף שנבחר במצב "ספרי התוסף בלבד".
  List<ExternalLibraryBook> get filteredVisibleBooks {
    final filter = sourceFilter.value;
    return switch (filter.source) {
      PluginLibraryBooksSource.all => _visibleBooks,
      PluginLibraryBooksSource.libraryOnly => const [],
      PluginLibraryBooksSource.pluginOnly => [
        for (final book in _visibleBooks)
          if (providerOf(book)?.pluginId == filter.pluginId) book,
      ],
    };
  }

  /// האם החיפוש מוגבל לספרי התוסף בלבד (בלי ספרי הספרייה).
  bool get searchesExtraBooksOnly =>
      sourceFilter.value.source == PluginLibraryBooksSource.pluginOnly;

  /// הספק שהספר שייך לו, רק כשהספק רשום כרגע לתוסף שיצר את הספר.
  PluginLibraryBookProvider? providerOf(Book book) {
    if (book is! ExternalLibraryBook) return null;
    final value = book.externalLibraryId;
    final separator = value?.indexOf(':') ?? -1;
    if (separator <= 0) return null;
    final provider = _providers[value!.substring(0, separator)];
    if (provider == null || _creator[book] != provider.pluginId) return null;
    return provider;
  }

  /// `false` כשהספר אינו של תוסף — אז הפתיחה נשארת בידי המסלול הקיים.
  /// ספק עם `openAction` מבוצע ב-[actionDispatcher], בלי להעיר את המנוע;
  /// בלעדיו (עץ בלי מערכת התוספים) נשלח האירוע, כמו לספק בלי פעולה.
  bool open(
    Book book, {
    PluginLibraryBookActionDispatcher? actionDispatcher,
    int? viewId,
    AppWindowKeys? windowKeys,
  }) {
    final owner = providerOf(book);
    if (owner == null) return false;
    final payload = {
      'provider': owner.provider,
      'id': book.id!,
      'title': book.title,
      if (book.author case final author? when author.isNotEmpty)
        'author': author,
    };
    final action = owner.openAction;
    final Future<void> opening = action != null && actionDispatcher != null
        ? actionDispatcher(owner.pluginId, action, payload)
        : _dispatch(
            owner.pluginId,
            openRequestedTopic,
            payload,
            viewId: viewId,
            windowKeys: windowKeys,
          );
    unawaited(
      opening.catchError((Object error) {
        debugPrint('PluginLibraryBooksRegistry: open dispatch failed: $error');
      }),
    );
    return true;
  }

  /// רישום חוזר של אותו ספק שומר את ספריו; ספק חדש נטען מה-DB ברקע.
  void registerPayload(
    String pluginId,
    Map<String, dynamic> item, {
    String? fallbackIconName,
  }) {
    final parsed = PluginLibraryBookProvider.parse(
      pluginId,
      item,
      fallbackIconName: fallbackIconName,
    );
    final existing = _providers[parsed.provider];
    if (existing != null && existing.pluginId != pluginId) {
      throw PluginLibraryBooksException(
        'הספק "${parsed.provider}" כבר רשום לתוסף אחר',
      );
    }
    // אותו פריט במניפסט עם שם ספק אחר: הישן יוצא, אחרת הוא נשאר רפאים.
    final renamed = [
      for (final provider in _ownedBy(pluginId, itemId: parsed.id))
        if (provider != parsed.provider) provider,
    ];
    final ownedByPlugin = _ownedBy(
      pluginId,
    ).where((p) => p != parsed.provider && !renamed.contains(p)).length;
    if (existing == null &&
        ownedByPlugin >= PluginLibraryBookProvider.maxItemsPerPlugin) {
      throw const PluginLibraryBooksException(
        'libraryBooks מוגבל ל-${PluginLibraryBookProvider.maxItemsPerPlugin} '
        'ספקים לתוסף',
      );
    }
    _forget(renamed);
    // כל LoadPlugins מסנכרן מחדש; הודעה בלי שינוי הייתה מריצה את החיפוש
    // המוצג ומאפסת את הבחירה בתצוגה המקדימה.
    if (existing != null && existing.sameAs(parsed) && renamed.isEmpty) return;
    _providers[parsed.provider] = parsed;
    notifyListeners();
    _dropOrphanedSourceFilter();
    if (existing == null) unawaited(_restore(pluginId, parsed.provider));
  }

  void remove(String pluginId, String itemId) {
    if (_forget(_ownedBy(pluginId, itemId: itemId))) {
      notifyListeners();
      _dropOrphanedSourceFilter();
    }
  }

  void removePlugin(String pluginId) {
    if (_forget(_ownedBy(pluginId))) {
      notifyListeners();
      _dropOrphanedSourceFilter();
    }
  }

  /// איפוס נתוני התוסף מוחק את הרשימות מה-DB. הספקים נשארים רשומים, כדי
  /// שהתוסף יוכל לשלוח רשימה חדשה מיד, עוד לפני הסנכרון הבא.
  void clearBooks(String pluginId) {
    var changed = false;
    for (final provider in _ownedBy(pluginId)) {
      _revisions[provider] = _revisionOf(provider) + 1;
      _resets[provider] = _resetsOf(provider) + 1;
      _entries.remove(provider);
      _pending.remove(provider);
      changed = _books.remove(provider) != null || changed;
    }
    if (changed) notifyListeners();
  }

  List<String> _ownedBy(String pluginId, {String? itemId}) => [
    for (final provider in _providers.values)
      if (provider.pluginId == pluginId &&
          (itemId == null || provider.id == itemId))
        provider.provider,
  ];

  bool _forget(List<String> providers) {
    for (final provider in providers) {
      _providers.remove(provider);
      _books.remove(provider);
      _entries.remove(provider);
      _pending.remove(provider);
      _revisions[provider] = _revisionOf(provider) + 1;
      _resets[provider] = _resetsOf(provider) + 1;
    }
    return providers.isNotEmpty;
  }

  /// נקרא אחרי ההודעה ואחרי רישום ספק חלופי, כדי ששינוי שם של הספק היחיד
  /// לא יאפס את הסינון ושמאזיני הסינון יראו את הרשימה המעודכנת.
  void _dropOrphanedSourceFilter() {
    final filterOwner = sourceFilter.value.pluginId;
    if (filterOwner != null && !hasProviderFor(filterOwner)) {
      resetSourceFilter();
    }
  }

  int _revisionOf(String provider) => _revisions[provider] ?? 0;

  int _resetsOf(String provider) => _resets[provider] ?? 0;

  /// מחליף את כל ספרי [provider]; רשימה ריקה מסירה אותם. מחזיר את מספר
  /// הספרים שנשמרו.
  Future<int> setBooks(String pluginId, String provider, Object? raw) async {
    if (!isOwner(pluginId, provider)) {
      throw PluginLibraryBooksException(
        'provider "$provider" is not registered for this plugin: it needs '
        'contributes.startup.libraryBooks and the permissions '
        'app.startup_contributions and library.books.provide',
        notFound: true,
      );
    }
    final resets = _resetsOf(provider);
    final parsing = _parseInIsolate(raw);
    final previousTurn = _parseTurns[provider];
    final turn = Completer<void>();
    _parseTurns[provider] = turn.future;
    final List<PluginLibraryBookEntry> entries;
    try {
      entries = await parsing;
      await previousTurn;
    } finally {
      turn.complete(previousTurn);
    }
    if (_resetsOf(provider) != resets || !isOwner(pluginId, provider)) {
      return entries.length;
    }
    if (_sameEntries(_pending[provider] ?? _entries[provider], entries)) {
      return entries.length;
    }
    final revision = _revisionOf(provider) + 1;
    _revisions[provider] = revision;
    _pending[provider] = entries;
    bool current() =>
        _revisionOf(provider) == revision && isOwner(pluginId, provider);
    final previousEntries = _entries[provider] ?? const [];
    final previousBooks = _books[provider] ?? const [];

    try {
      final prepared = entries.isEmpty
          ? null
          : await _prepareInIsolate(provider, entries, previousEntries);
      // איפוס או הסרה בזמן הקידוד: כתיבה עכשיו הייתה מחזירה רשימה שנמחקה.
      if (!current()) return entries.length;
      if (prepared == null) {
        await _repository.removeKV(pluginId, _storageNamespace, provider);
      } else {
        await _repository.setKV(
          pluginId,
          _storageNamespace,
          provider,
          prepared.stored,
        );
      }
      if (current()) {
        _apply(pluginId, provider, entries, prepared?.books, previousBooks);
        notifyListeners();
      }
      return entries.length;
    } finally {
      if (_revisionOf(provider) == revision) _pending.remove(provider);
    }
  }

  /// ספר שלא השתנה שומר את האובייקט הקודם: כך הוא נשאר בתצוגה המקדימה
  /// גם אחרי שהרשימה סביבו השתנתה.
  void _apply(
    String pluginId,
    String provider,
    List<PluginLibraryBookEntry> entries,
    _BuiltBooks? built,
    List<ExternalLibraryBook> previousBooks,
  ) {
    final fresh = built?.fresh ?? const <ExternalLibraryBook>[];
    for (final book in fresh) {
      _creator[book] = pluginId;
    }
    var next = 0;
    final books = fresh.length == entries.length
        ? fresh
        : [
            for (final index in built!.reused)
              index < 0 ? fresh[next++] : previousBooks[index],
          ];
    _entries[provider] = entries;
    if (books.isEmpty) {
      _books.remove(provider);
    } else {
      _books[provider] = books;
    }
  }

  static _BuiltBooks _buildBooks(
    String provider,
    List<PluginLibraryBookEntry> entries,
    List<PluginLibraryBookEntry> previous,
  ) {
    final previousIndex = {
      for (var i = 0; i < previous.length; i++) previous[i].id: i,
    };
    final fresh = <ExternalLibraryBook>[];
    final reused = Int32List(entries.length);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final index = previousIndex[entry.id];
      if (index != null && _sameEntry(previous[index], entry)) {
        reused[i] = index;
      } else {
        reused[i] = -1;
        fresh.add(entry.toBook(provider));
      }
    }
    return (fresh: fresh, reused: reused);
  }

  static bool _sameEntry(PluginLibraryBookEntry a, PluginLibraryBookEntry b) =>
      a.id == b.id &&
      a.title == b.title &&
      a.author == b.author &&
      a.categoryPath == b.categoryPath &&
      a.description == b.description;

  static bool _sameEntries(
    List<PluginLibraryBookEntry>? previous,
    List<PluginLibraryBookEntry> next,
  ) {
    if (previous == null) return false;
    if (previous.length != next.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (!_sameEntry(previous[i], next[i])) return false;
    }
    return true;
  }

  Future<void> _restore(String pluginId, String provider) async {
    final revision = _revisionOf(provider);
    final previousEntries = _entries[provider] ?? const [];
    final previousBooks = _books[provider] ?? const [];
    try {
      final raw = await _repository.getKV(
        pluginId,
        _storageNamespace,
        provider,
      );
      if (raw == null) return;
      // רשימה של אלפי ספרים, בעליית התוכנה: מפוענחת מחוץ ל-isolate של הממשק.
      final restored = await _decodeInIsolate(provider, raw, previousEntries);
      if (restored == null ||
          restored.entries.isEmpty ||
          _revisionOf(provider) != revision ||
          !isOwner(pluginId, provider)) {
        return;
      }
      _apply(
        pluginId,
        provider,
        restored.entries,
        restored.books,
        previousBooks,
      );
      notifyListeners();
    } catch (e) {
      // רשימה פגומה לא תעצור את עליית התוספים; התוסף ישלח אותה שוב.
      debugPrint('PluginLibraryBooksRegistry: $pluginId/$provider: $e');
      unawaited(
        PluginSystemDatabase.instance
            .writeLog(
              pluginId,
              'ERROR',
              'libraryBooks: stored list for "$provider" is unreadable: $e',
            )
            .catchError((Object _) {}),
      );
    }
  }

  // סטטיות בכוונה: סגור שנוצר במתודה של המופע עלול לשאת את `this` להקשר
  // המשותף, ו-Isolate.run נכשל על אובייקט שאי אפשר לשלוח.
  static Future<({String stored, _BuiltBooks books})> _prepareInIsolate(
    String provider,
    List<PluginLibraryBookEntry> entries,
    List<PluginLibraryBookEntry> previous,
  ) => Isolate.run(
    () => (
      stored: _encode(entries),
      books: _buildBooks(provider, entries, previous),
    ),
  );

  static Future<List<PluginLibraryBookEntry>> _parseInIsolate(Object? raw) =>
      Isolate.run(() => PluginLibraryBookEntry.parseList(raw));

  static Future<({List<PluginLibraryBookEntry> entries, _BuiltBooks books})?>
  _decodeInIsolate(
    String provider,
    String raw,
    List<PluginLibraryBookEntry> previous,
  ) => Isolate.run(() {
    final entries = _decode(raw);
    if (entries == null) return null;
    return (entries: entries, books: _buildBooks(provider, entries, previous));
  });

  static String _encode(List<PluginLibraryBookEntry> entries) => jsonEncode({
    'version': _storageVersion,
    'books': [for (final entry in entries) entry.toStorage()],
  });

  /// `null` לגרסת אחסון אחרת: התוסף פשוט ישלח את הרשימה שוב.
  static List<PluginLibraryBookEntry>? _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['version'] != _storageVersion) return null;
    return PluginLibraryBookEntry.parseList(decoded['books'], stored: true);
  }

  void _onConditionsChanged() {
    if (setEquals(_computeVisibleProviders(), _visibleProviders)) return;
    notifyListeners();
  }

  Set<String> _computeVisibleProviders() => {
    for (final provider in _providers.values)
      if (_conditions.isVisible(provider.pluginId, provider.when))
        provider.provider,
  };

  @override
  void notifyListeners() {
    final visibleProviders = _computeVisibleProviders();
    _visibleProviders = visibleProviders;
    _visibleBooks = List.unmodifiable([
      for (final provider in _providers.values)
        if (visibleProviders.contains(provider.provider))
          ...?_books[provider.provider],
    ]);
    super.notifyListeners();
  }
}
