import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/hidden/hidden_books_import.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/settings/dialogs/hidden_books_list_dialog.dart';
import 'package:otzaria/settings/dialogs/hidden_books_picker_dialog.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// מסך ניהול הספרים והקטגוריות שהוסתרו מהממשק (issue #1448).
///
/// מסד הספרים אינו משתנה; ספר מוסתר מוסר מאינדקס החיפוש אך עדיין נפתח
/// מקישור, מהיסטוריה או מסימנייה.
class HiddenBooksPanel extends StatefulWidget {
  /// חנות ההסתרות. ניתנת להחלפה בבדיקות.
  final HiddenLibraryStore store;

  /// לצורכי בדיקה — עוקף את בורר הקבצים של המערכת.
  final Future<String?> Function()? pickFileOverride;

  /// לצורכי בדיקה — עוקף את טעינת הספרייה.
  final Future<Library> Function()? libraryLoader;

  /// מסיר ספרים מאינדקס החיפוש. ניתן להחלפה בבדיקות.
  final Future<bool> Function(Iterable<Book> books)? indexDropper;

  /// מתזמן אינדוקס של ספרים שחזרו להיות גלויים; ניתן להחלפה בבדיקות.
  final void Function(List<Book> books, Library library)? indexAdder;

  const HiddenBooksPanel({
    super.key,
    this.store = const HiddenLibraryStore(),
    this.pickFileOverride,
    this.libraryLoader,
    this.indexDropper,
    this.indexAdder,
  });

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'library.hidden_books.import',
      title: 'ייבוא רשימת הסתרות',
      subtitle: 'הסתרת ספרים מהממשק לפי רשימת שמות בקובץ CSV או JSON',
      tab: SettingsTab.library,
      cardId: 'library.hidden_books',
      keywords: ['הסתרה', 'מוסתר', 'הסתר', 'ייבוא', 'רשימה', 'CSV', 'JSON'],
    ),
    SettingsSearchEntry(
      id: 'library.hidden_books.list',
      title: 'ספרים וקטגוריות מוסתרים',
      subtitle: 'בחירת ספרים וקטגוריות להסתרה וביטול הסתרה',
      tab: SettingsTab.library,
      cardId: 'library.hidden_books',
      keywords: ['הסתרה', 'מוסתר', 'ביטול', 'שחזור', 'ספרים', 'קטגוריות'],
    ),
  ];

  @override
  State<HiddenBooksPanel> createState() => _HiddenBooksPanelState();
}

class _HiddenBooksPanelState extends State<HiddenBooksPanel> {
  late HiddenLibrarySelection _hidden = widget.store.load();
  StreamSubscription<HiddenLibrarySelection>? _hiddenChanges;

  /// מפתח ספר → כותרת להצגה. ספר שאינו בספרייה יוצג לפי המפתח הגולמי, כדי
  /// שהמשתמש יוכל להסיר גם הסתרה של ספר שנעלם.
  Map<String, String> _titles = const {};

  @override
  void initState() {
    super.initState();
    // גם שמירה מפאנל פתוח בחלון אחר: כל החלונות כותבים לאותה חנות.
    _hiddenChanges = widget.store.changes.listen((selection) {
      if (mounted) setState(() => _hidden = selection);
    });
    unawaited(_loadTitles());
  }

  @override
  void dispose() {
    unawaited(_hiddenChanges?.cancel());
    super.dispose();
  }

  Future<void> _loadTitles() async {
    if (_hidden.bookKeys.isEmpty) return;
    try {
      final library = await _library();
      if (!mounted) return;
      setState(() {
        _titles = {
          for (final book in library.getAllBooks())
            PerBookSettings.bookKey(book): book.title,
        };
      });
    } catch (_) {
      // הספרייה לא נטענה — הרשימה תוצג לפי המפתחות.
    }
  }

  Future<Library> _library() =>
      widget.libraryLoader?.call() ?? DataRepository.instance.library;

  HiddenLibrarySelection _currentSelection() {
    final current = widget.store.load();
    if (current != _hidden) setState(() => _hidden = current);
    return current;
  }

  Future<bool> _save(
    HiddenLibrarySelection next, {
    required HiddenLibrarySelection base,
    Library? library,
  }) async {
    if (next == base) return true;
    if (!mounted) return false;
    final fullLibrary = library ?? await _library();
    if (!mounted) return false;
    final indexing = widget.indexDropper == null && widget.indexAdder == null
        ? context.read<IndexingBloc>()
        : null;
    final saved = await HiddenLibraryUpdateQueue.instance.run(() async {
      final before = widget.store.load();
      final desired = applyHiddenSelectionChange(before, base, next);
      final int revision;
      try {
        revision = await widget.store.beginVisibilityIndexUpdate();
      } catch (error) {
        debugPrint('[HiddenBooks] failed to mark index update: $error');
        UiSnack.showError(SettingsMessages.hiddenBooksSelectionSaveFailed);
        return false;
      }
      final result = await widget.store.saveAndRead(desired);
      final actual = result.actual;
      final delta = hiddenIndexDelta(fullLibrary, before, actual);
      if (mounted) {
        setState(() => _hidden = actual);
        if (actual != before) {
          context.read<LibraryBloc>().add(const HiddenBooksChanged());
        }
      }
      if (indexing != null) {
        indexing.add(
          ApplyHiddenIndexDelta(
            fullLibrary,
            newlyHidden: delta.newlyHidden,
            newlyVisible: delta.newlyVisible,
            visibilityRevision: revision,
            onCompleted: (success) {
              if (!success) {
                UiSnack.showError(
                  SettingsMessages.hiddenBooksIndexUpdateFailed,
                );
              }
            },
          ),
        );
      } else {
        final dropped = await _dropFromIndex(delta.newlyHidden);
        if (dropped) widget.indexAdder?.call(delta.newlyVisible, fullLibrary);
        await widget.store.completeVisibilityIndexUpdate(revision, dropped);
      }
      if (result.error != null) {
        debugPrint('[HiddenBooks] failed to save selection: ${result.error}');
        UiSnack.showError(SettingsMessages.hiddenBooksSelectionSaveFailed);
      }
      return result.error == null && actual == desired;
    });
    return saved;
  }

  Future<void> _showHiddenList() async {
    final base = _currentSelection();
    final updated = await showHiddenBooksListDialog(
      context: context,
      hidden: base,
      titles: _titles,
    );
    if (updated == null || !mounted) return;
    await _save(updated, base: base);
  }

  Future<void> _pickBooks() async {
    final library = await _library();
    if (!mounted) return;

    final base = _currentSelection();
    final picked = await showHiddenBooksPickerDialog(
      context: context,
      library: library,
      hidden: base,
    );
    if (picked == null || !mounted) return;

    await _save(picked, base: base, library: library);
    await _loadTitles();
  }

  Future<void> _import() async {
    final path = await (widget.pickFileOverride?.call() ?? _pickFile());
    if (path == null || !mounted) return;

    final String content;
    try {
      content = await File(path).readAsString();
    } catch (error) {
      UiSnack.showError(SettingsMessages.hiddenBooksFileReadError(error));
      return;
    }

    final library = await _library();
    final result = parseHiddenBooksImport(content, library);
    if (!mounted) return;

    if (result.isEmpty) {
      UiSnack.showError(SettingsMessages.hiddenBooksFileEmpty);
      return;
    }

    final base = _currentSelection();
    final saved = await _save(
      base.copyWith(
        bookKeys: {...base.bookKeys, ...result.matchedBookKeys},
      ),
      base: base,
      library: library,
    );
    if (!saved) return;
    await _loadTitles();
    if (!mounted) return;

    UiSnack.show(
      SettingsMessages.hiddenBooksImported(
        result.matchedBookKeys.length,
        result.unmatchedNames.length,
      ),
    );
  }

  Future<bool> _dropFromIndex(List<Book> books) async {
    if (books.isEmpty) return true;
    final drop =
        widget.indexDropper ??
        IndexingRepository(TantivyDataProvider.instance).dropBookIndexEntries;
    try {
      if (!await drop(books)) {
        UiSnack.showError(SettingsMessages.hiddenBooksIndexDropFailed);
        return false;
      }
      return true;
    } catch (error) {
      debugPrint('[HiddenBooks] index drop failed: $error');
      UiSnack.showError(SettingsMessages.hiddenBooksIndexDropFailed);
      return false;
    }
  }

  Future<String?> _pickFile() async {
    final result = await withFilePickerOwner(
      context,
      (picker) => picker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'json', 'txt'],
        windowsOptions: modalWindowsOptions(context),
        linuxOptions: kModalLinuxOptions,
      ),
    );
    return result?.path;
  }

  @override
  Widget build(BuildContext context) {
    final count = _hidden.bookKeys.length + _hidden.categoryPaths.length;

    // שלוש שורות בתוך ילד אחד של הכרטיס, ולכן הקו החוצץ שבין שורות הכרטיס
    // לא מגיע אליהן — מוסיפים אותו כאן, באותו צבע.
    final divider = AppCard.sectionDivider(context);
    return Column(
      children: [
        SettingsActionTile.text(
          icon: OtzariaIcons.book_delete_24_regular,
          title: context.settingsText('בחירת ספרים וקטגוריות להסתרה'),
          subtitle: context.settingsText(
            'בחירת ספרים או קטגוריות מתוך הספרייה, עם חיפוש וסימון',
          ),
          actions: [
            ActionButton.recommended(
              text: context.settingsText('פתח רשימה'),
              onPressed: _pickBooks,
            ),
          ],
        ),
        divider,
        SettingsActionTile.text(
          icon: FluentIcons.arrow_import_24_regular,
          title: context.settingsText('ייבוא רשימת הסתרות'),
          subtitle: context.settingsText(
            'קובץ CSV עם שם ספר בכל שורה, או JSON עם מערך שמות. שם שלא יימצא בספרייה ידווח',
          ),
          actions: [
            ActionButton.neutral(
              text: context.settingsText('בחר קובץ'),
              onPressed: _import,
            ),
          ],
        ),
        divider,
        SettingsActionTile.text(
          icon: FluentIcons.eye_off_24_regular,
          title: count == 0
              ? context.settingsText('אין בחירות הסתרה')
              : context.settingsText(
                  'בחירות הסתרה ישירות: {count}',
                  args: {'count': count},
                ),
          subtitle: context.settingsText(
            'הסתרה משפיעה על מסך הספרייה, האיתור והחיפוש בלבד — ספר מוסתר עדיין נפתח מקישור או מההיסטוריה',
          ),
          actions: [
            if (count > 0)
              ActionButton.neutral(
                text: context.settingsText('הצג רשימה'),
                onPressed: _showHiddenList,
              ),
          ],
        ),
      ],
    );
  }
}
