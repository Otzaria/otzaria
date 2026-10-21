import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

/// העדפות המרקר, שמורות בהגדרות האפליקציה: נכללות בגיבוי ההגדרות ומסונכרנות
/// בין חלונות דרך [SettingsSync].
class MarkerSettings extends ChangeNotifier {
  MarkerSettings._() {
    _remote = SettingsSync.instance.changes
        .where((key) => key.isEmpty || keys.contains(key))
        .listen((_) => reload());
  }

  static final MarkerSettings instance = MarkerSettings._();

  static const String keyPalette = 'key-marker-palette';
  static const String keyShowHighlights = 'key-marker-show-highlights';
  static const String keyHiddenBooks = 'key-marker-hidden-books';
  static const String keyShowInContextMenu = 'key-marker-context-menu';
  static const String keyShowInCommentaryMenu =
      'key-marker-commentary-context-menu';
  static const String keyShowInPdfMenu = 'key-marker-pdf-context-menu';
  static const String keyShowToolbarButton = 'key-marker-toolbar-button';
  static const String keySort = 'key-marker-sort';
  static const String keyGroup = 'key-marker-group';

  static const Set<String> keys = {
    keyPalette,
    keyShowHighlights,
    keyHiddenBooks,
    keyShowInContextMenu,
    keyShowInCommentaryMenu,
    keyShowInPdfMenu,
    keyShowToolbarButton,
    keySort,
    keyGroup,
  };

  late final StreamSubscription<String> _remote;

  MarkerPalette? _palette;
  Set<String>? _hiddenBooks;

  MarkerPalette get palette =>
      _palette ??= MarkerPalette.decode(_read<String>(keyPalette));

  bool get showHighlights => _read<bool>(keyShowHighlights) ?? true;

  bool get showInContextMenu => _read<bool>(keyShowInContextMenu) ?? true;

  /// גם בתפריט של המפרשים; חל רק כשהסימון מהתפריט מופעל.
  bool get showInCommentaryMenu =>
      showInContextMenu && (_read<bool>(keyShowInCommentaryMenu) ?? true);

  /// גם בתפריט של ספרי PDF; חל רק כשהסימון מהתפריט מופעל.
  bool get showInPdfMenu =>
      showInContextMenu && (_read<bool>(keyShowInPdfMenu) ?? true);

  bool get showToolbarButton => _read<bool>(keyShowToolbarButton) ?? true;

  /// ספרים שבהם הסימונים מוסתרים בלי להימחק, לפי [hiddenKey]: ספר PDF
  /// וספר טקסט באותה כותרת מוסתרים כל אחד בנפרד.
  Set<String> get hiddenBooks => _hiddenBooks ??= _decodeBooks();

  bool isBookHidden(String bookTitle, {bool pdf = false}) =>
      hiddenBooks.contains(hiddenKey(bookTitle, pdf: pdf));

  static const String _pdfPrefix = 'pdf:';

  static String hiddenKey(String bookTitle, {bool pdf = false}) =>
      pdf ? '$_pdfPrefix$bookTitle' : bookTitle;

  /// הספר שמפתח מ-[hiddenBooks] מתאר.
  static ({String title, bool pdf}) bookOfHiddenKey(String key) =>
      key.startsWith(_pdfPrefix)
      ? (title: key.substring(_pdfPrefix.length), pdf: true)
      : (title: key, pdf: false);

  MarkerSort get sort => MarkerSort.values.firstWhere(
    (sort) => sort.name == _read<String>(keySort),
    orElse: () => MarkerSort.newest,
  );

  MarkerGroup get group => MarkerGroup.values.firstWhere(
    (group) => group.name == _read<String>(keyGroup),
    orElse: () => MarkerGroup.none,
  );

  Future<void> setPalette(MarkerPalette palette) async {
    _palette = palette;
    notifyListeners();
    await Settings.setValue<String>(keyPalette, palette.encode());
  }

  Future<void> setShowHighlights(bool value) =>
      _write<bool>(keyShowHighlights, value);

  Future<void> setShowInContextMenu(bool value) =>
      _write<bool>(keyShowInContextMenu, value);

  Future<void> setShowInCommentaryMenu(bool value) =>
      _write<bool>(keyShowInCommentaryMenu, value);

  Future<void> setShowInPdfMenu(bool value) =>
      _write<bool>(keyShowInPdfMenu, value);

  Future<void> setShowToolbarButton(bool value) =>
      _write<bool>(keyShowToolbarButton, value);

  Future<void> setBookHidden(
    String bookTitle,
    bool hidden, {
    bool pdf = false,
  }) async {
    final key = hiddenKey(bookTitle, pdf: pdf);
    final next = {...hiddenBooks};
    if (!(hidden ? next.add(key) : next.remove(key))) return;
    _hiddenBooks = next;
    notifyListeners();
    await Settings.setValue<String>(
      keyHiddenBooks,
      jsonEncode((next.toList()..sort())),
    );
  }

  Future<void> setListOrder(MarkerSort sort, MarkerGroup group) async {
    await Settings.setValue<String>(keySort, sort.name);
    await Settings.setValue<String>(keyGroup, group.name);
  }

  /// קורא מחדש את הערכים השמורים — אחרי שינוי בחלון אחר או שחזור הגדרות.
  void reload() {
    _palette = null;
    _hiddenBooks = null;
    notifyListeners();
  }

  Future<void> _write<T>(String key, T value) async {
    await Settings.setValue<T>(key, value);
    notifyListeners();
  }

  static T? _read<T>(String key) =>
      Settings.isInitialized ? Settings.getValue<T>(key) : null;

  static Set<String> _decodeBooks() {
    final raw = _read<String>(keyHiddenBooks);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? {...decoded.whereType<String>()} : const {};
    } on FormatException {
      return const {};
    }
  }

  @override
  void dispose() {
    unawaited(_remote.cancel());
    super.dispose();
  }
}
