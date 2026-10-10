import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_library_book_provider.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';

typedef PluginLibraryBooksDispatch =
    Future<void> Function(
      String pluginId,
      String topic,
      Map<String, dynamic> payload,
    );

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
    required this._dispatch,
    required this._conditions,
    required this._repository,
  }) {
    _conditions.addListener(_onConditionsChanged);
  }

  static Future<void> _dispatchToPlugin(
    String pluginId,
    String topic,
    Map<String, dynamic> payload,
  ) => PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
    pluginId,
    topic,
    payload,
    preferBackground: true,
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

  /// הספקים שהוצגו בהודעה האחרונה. המעריך מודיע על כל מפתח של כל תוסף,
  /// וכל הודעה כאן מריצה מחדש את החיפוש המוצג בספרייה.
  Set<String> _visibleProviders = const {};
  List<ExternalLibraryBook> _visibleBooks = const [];

  @visibleForTesting
  Iterable<PluginLibraryBookProvider> get providers => _providers.values;

  bool isOwner(String pluginId, String provider) =>
      _providers[provider]?.pluginId == pluginId;

  @visibleForTesting
  List<ExternalLibraryBook> booksOf(String provider) =>
      List.unmodifiable(_books[provider] ?? const []);

  /// ספרי הספקים שתנאי ה-`when` שלהם מתקיים כרגע.
  List<ExternalLibraryBook> get visibleBooks => _visibleBooks;

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
  bool open(Book book, {PluginLibraryBookActionDispatcher? actionDispatcher}) {
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
        : _dispatch(owner.pluginId, openRequestedTopic, payload);
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
    if (existing == null) unawaited(_restore(pluginId, parsed.provider));
  }

  void remove(String pluginId, String itemId) {
    if (_forget(_ownedBy(pluginId, itemId: itemId))) notifyListeners();
  }

  void removePlugin(String pluginId) {
    if (_forget(_ownedBy(pluginId))) notifyListeners();
  }

  /// איפוס נתוני התוסף מוחק את הרשימות מה-DB. הספקים נשארים רשומים, כדי
  /// שהתוסף יוכל לשלוח רשימה חדשה מיד, עוד לפני הסנכרון הבא.
  void clearBooks(String pluginId) {
    var changed = false;
    for (final provider in _ownedBy(pluginId)) {
      _revisions[provider] = _revisionOf(provider) + 1;
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
    }
    return providers.isNotEmpty;
  }

  int _revisionOf(String provider) => _revisions[provider] ?? 0;

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
    final entries = PluginLibraryBookEntry.parseList(raw);
    if (_sameEntries(_pending[provider] ?? _entries[provider], entries)) {
      return entries.length;
    }
    final revision = _revisionOf(provider) + 1;
    _revisions[provider] = revision;
    _pending[provider] = entries;
    bool current() =>
        _revisionOf(provider) == revision && isOwner(pluginId, provider);

    try {
      final stored = entries.isEmpty ? null : await _encodeInIsolate(entries);
      // איפוס או הסרה בזמן הקידוד: כתיבה עכשיו הייתה מחזירה רשימה שנמחקה.
      if (!current()) return entries.length;
      if (stored == null) {
        await _repository.removeKV(pluginId, _storageNamespace, provider);
      } else {
        await _repository.setKV(pluginId, _storageNamespace, provider, stored);
      }
      if (current()) {
        _apply(pluginId, provider, entries);
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
  ) {
    final previousEntries = _entries[provider] ?? const [];
    final previousBooks = _books[provider] ?? const [];
    final previousIndex = {
      for (var i = 0; i < previousEntries.length; i++) previousEntries[i].id: i,
    };
    final books = <ExternalLibraryBook>[];
    for (final entry in entries) {
      final index = previousIndex[entry.id];
      if (index != null && _sameEntry(previousEntries[index], entry)) {
        books.add(previousBooks[index]);
        continue;
      }
      final book = entry.toBook(provider);
      _creator[book] = pluginId;
      books.add(book);
    }
    _entries[provider] = entries;
    if (books.isEmpty) {
      _books.remove(provider);
    } else {
      _books[provider] = books;
    }
  }

  static bool _sameEntry(PluginLibraryBookEntry a, PluginLibraryBookEntry b) =>
      a.id == b.id &&
      a.title == b.title &&
      a.author == b.author &&
      a.categoryPath == b.categoryPath;

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
    try {
      final raw = await _repository.getKV(
        pluginId,
        _storageNamespace,
        provider,
      );
      if (raw == null) return;
      // רשימה של אלפי ספרים, בעליית התוכנה: מפוענחת מחוץ ל-isolate של הממשק.
      final entries = await _decodeInIsolate(raw);
      if (entries == null ||
          entries.isEmpty ||
          _revisionOf(provider) != revision ||
          !isOwner(pluginId, provider)) {
        return;
      }
      _apply(pluginId, provider, entries);
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
  static Future<String> _encodeInIsolate(
    List<PluginLibraryBookEntry> entries,
  ) => Isolate.run(() => _encode(entries));

  static Future<List<PluginLibraryBookEntry>?> _decodeInIsolate(String raw) =>
      Isolate.run(() => _decode(raw));

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

  @visibleForTesting
  void clear() {
    _providers.clear();
    _books.clear();
    _entries.clear();
    _pending.clear();
    _revisions.clear();
    _visibleProviders = const {};
    _visibleBooks = const [];
  }
}
