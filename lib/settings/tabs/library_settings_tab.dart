import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/settings/panels/settings_panels_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/dialogs/zip_extraction_progress_dialog.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/dialogs/change_location_dialog.dart';
import 'package:otzaria/settings/tabs/widgets/android_storage_location_card.dart';
import 'package:otzaria/settings/dialogs/library_setup_dialog.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:path/path.dart' as p;

/// טאב הגדרות ספרייה
class LibrarySettingsTab extends StatefulWidget {
  const LibrarySettingsTab({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'library.location.path',
      title: 'מיקום הספרייה והאינדקס',
      subtitle: 'התיקיה שבה נמצאים תיקיות הספרים והאינדקס',
      tab: SettingsTab.library,
      cardId: 'library.repository',
      keywords: ['נתיב', 'תיקיה', 'מאגר', 'אינדקס', 'חיפוש', 'שורש'],
    ),
    SettingsSearchEntry(
      id: 'library.search.auto_index',
      title: 'עדכון אינדקס אוטומטי',
      subtitle: 'אינדקס החיפוש יתעדכן אוטומטית',
      tab: SettingsTab.library,
      cardId: 'library.repository',
      keywords: ['חיפוש', 'אינדקס', 'אוטומטי', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'library.search.index_status',
      title: 'אינדקס חיפוש',
      subtitle: 'סטטוס ועדכון אינדקס החיפוש',
      tab: SettingsTab.library,
      cardId: 'library.repository',
      keywords: [
        'חיפוש',
        'אינדקס',
        'בנייה',
        'מעודכן',
        'לא מעודכן',
        'איפוס',
        'עדכן',
      ],
    ),
    SettingsSearchEntry(
      id: 'library.location.hebrewbooks',
      title: 'מיקום ספרי היברובוקס',
      subtitle: 'תיקיית ספרי HebrewBooks',
      tab: SettingsTab.library,
      cardId: 'library.external',
      keywords: ['hebrewbooks', 'היברובוקס'],
    ),
    SettingsSearchEntry(
      id: 'library.custom_folders',
      title: 'תיקיות מותאמות אישית',
      subtitle: 'הוסף תיקיות ספרים נוספות',
      tab: SettingsTab.library,
      cardId: 'library.custom_folders',
      keywords: ['תיקיות', 'מותאם'],
    ),
    SettingsSearchEntry(
      id: 'library.android_storage',
      title: 'מיקום אחסון הספרייה',
      subtitle: 'העברת הספרייה לכרטיס זיכרון או בחזרה לאחסון הפנימי',
      tab: SettingsTab.library,
      cardId: 'library.android_storage',
      keywords: ['sd', 'כרטיס זיכרון', 'אחסון חיצוני'],
    ),
    SettingsSearchEntry(
      id: 'library.custom_folders.merge_into_library',
      title: 'מיזוג ספרים אישיים לעץ הספרייה',
      subtitle: 'תת-התיקיות של התיקייה הנבחרת ימוזגו לקטגוריות הראשיות לפי שם',
      tab: SettingsTab.library,
      cardId: 'library.custom_folders',
      keywords: [
        'מיזוג',
        'ספרים אישיים',
        'תיקיות',
        'מותאם',
        'מוזג',
        'ממוזג',
        'ספריה',
        'עץ',
      ],
    ),
  ];

  @override
  State<LibrarySettingsTab> createState() => _LibrarySettingsTabState();
}

class _LibrarySettingsTabState extends State<LibrarySettingsTab> {
  static const _hebrewBooksFolderName = 'ספרי היברובוקס';

  bool _isRemovingHebrewPath = false;
  final IndexingRepository _indexingRepository = IndexingRepository(
    TantivyDataProvider.instance,
  );
  bool? _requiresManualReindex;
  String? _defaultLibraryPath;
  String? _indexPath;
  String? _databasesPath;

  @override
  void initState() {
    super.initState();
    AppPaths.getDefaultLibraryPath().then((path) {
      if (mounted) setState(() => _defaultLibraryPath = path);
    });
    AppPaths.getIndexPath().then((path) {
      if (mounted) setState(() => _indexPath = path);
    });
    AppPaths.getDatabasesPath().then((path) {
      if (mounted) setState(() => _databasesPath = path);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        _refreshManualReindexRequirement(context.read<LibraryBloc>().state),
      );
    });
  }

  Future<void> _refreshManualReindexRequirement(
    LibraryState libraryState,
  ) async {
    final library = libraryState.library;
    if (!mounted || library == null) {
      if (_requiresManualReindex != false) {
        setState(() => _requiresManualReindex = false);
      }
      return;
    }

    final requiresManualReindex = await _indexingRepository
        .requiresManualReindex(library);
    if (!mounted || _requiresManualReindex == requiresManualReindex) {
      return;
    }

    setState(() {
      _requiresManualReindex = requiresManualReindex;
    });
  }

  Future<void> _showExtractionDialog(
    BuildContext context,
    String path, {
    required bool isLibraryPath,
  }) async {
    await ZipExtractionProgressDialog.showAndExtract(
      context: context,
      path: path,
      onSuccess: (extractionResult) async {
        if (!context.mounted) return;

        // עדכון הנתיב
        if (isLibraryPath) {
          context.read<LibraryBloc>().add(UpdateLibraryPath(path));
        } else {
          context.read<LibraryBloc>().add(UpdateHebrewBooksPath(path));
        }

        // המתנה קצרה
        await Future.delayed(const Duration(milliseconds: 500));

        if (context.mounted) {
          context.read<NavigationBloc>().add(const CheckLibrary());

          if (extractionResult.successfullyExtracted) {
            UiSnack.show(
              SettingsMessages.fileExtracted(
                extractionResult.extractedFileName,
              ),
            );
          }
        }
      },
      onError: (errorMessage) {
        UiSnack.showError(errorMessage);
      },
    );
  }

  /// הסרת מיקום ספרי היברובוקס
  void _removeHebrewBooksPath(BuildContext context) {
    setState(() => _isRemovingHebrewPath = true);
    context.read<LibraryBloc>().add(const RemoveHebrewBooksPath());
  }

  /// מעדכן BLoC לאחר העברת תיקייה (moveDirectory נקרא על-ידי makeChangeLocationCallback).
  Future<void> _afterMoveUpdateBloc(
    String to,
    LibraryEvent Function(String) makeEvent,
  ) async {
    if (!mounted) return;
    context.read<LibraryBloc>().add(makeEvent(to));
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      context.read<NavigationBloc>().add(const CheckLibrary());
      setState(() {});
    }
  }

  /// פותח נתיב במנהל הקבצים של מערכת ההפעלה.
  void _openInFileManager(String path) {
    if (path.isEmpty) return;
    if (Platform.isWindows) {
      unawaited(Process.run('explorer', [path]));
    } else if (Platform.isMacOS) {
      unawaited(Process.run('open', [path]));
    } else if (Platform.isLinux) {
      unawaited(Process.run('xdg-open', [path]));
    }
  }

  /// מחיל בחירת תיקיית שורש של הספרייה: ה-DB מאותר תחת <שורש>/books, ואם אינו
  /// שם — ישירות תחת התיקייה שנבחרה (תמיכה במי שמצביע על תיקיית הספרים עצמה).
  Future<void> _applyLibraryRootChange(String root) async {
    final booksDir = p.join(root, 'books');
    String target;
    if (await File(
      p.join(booksDir, DatabaseConstants.databaseFileName),
    ).exists()) {
      target = booksDir;
    } else if (await File(
      p.join(root, DatabaseConstants.databaseFileName),
    ).exists()) {
      target = root;
    } else {
      target = booksDir;
    }
    if (!mounted || !context.mounted) return;
    await _showExtractionDialog(context, target, isLibraryPath: true);
    if (mounted) setState(() {});
  }

  /// תיקיית השורש (ההורה של books/index) עבור נתיב ספרייה נתון.
  /// כשהנתיב הוא תת-תיקיית "books" — השורש הוא ההורה; אחרת המשתמש הצביע
  /// על תיקייה שמכילה את ה-DB ישירות, והיא עצמה השורש.
  String _libraryRootOf(String libraryPath) =>
      p.basename(libraryPath).toLowerCase() == 'books'
      ? p.dirname(libraryPath)
      : libraryPath;

  /// פריטי כרטיס "מאגר הספרים": כשלא זוהתה ספרייה — כפתור "הגדרת ספריה"
  /// שפותח את הדיאלוג המאוחד; אחרת שורת המיקום עם תפריט "אפשרויות מיקום".
  List<Widget> _buildRepositoryCardChildren(
    BuildContext context,
    bool libraryEmpty,
  ) {
    if (libraryEmpty) {
      return [
        SettingsActionTile.text(
          icon: FluentIcons.folder_add_24_regular,
          title: context.settingsText('מיקום הספרייה'),
          subtitle: context.settingsText(
            'לא זוהתה ספרייה — הגדר מיקום, הורד או ייבא ספרייה',
          ),
          actions: [
            ActionButton.recommended(
              text: context.settingsText('הגדרת ספריה'),
              onPressed: () => _openLibraryDialog(''),
            ),
          ],
        ),
      ];
    }
    return [_buildLibraryLocationWidget(context)];
  }

  /// פותח את דיאלוג הגדרת/עדכון מיקום הספרייה המאוחד. [booksPath] ריק → מצב
  /// הגדרה ראשונית; אחרת מצב עדכון/מיקום מחדש של ספרייה קיימת.
  Future<void> _openLibraryDialog(String booksPath) async {
    if (!await verifySaferModePassword(context)) return;
    if (!mounted) return;
    final defaultRoot =
        (_defaultLibraryPath == null || _defaultLibraryPath!.isEmpty)
        ? ''
        : _libraryRootOf(_defaultLibraryPath!);
    final configured = await showLibrarySetupDialog(
      context: context,
      defaultTargetPath: defaultRoot,
      currentLibraryPath: booksPath.isEmpty ? null : booksPath,
    );
    if (configured) await _refreshAfterLibraryChange();
  }

  Future<void> _refreshAfterLibraryChange() async {
    if (!mounted) return;
    await context.read<NavigationBloc>().refreshLibrary();
    if (!mounted) return;
    context.read<LibraryBloc>().add(RefreshLibrary());
    setState(() {});
  }

  /// שורת מיקום הספרייה והאינדקס — מציגה את תיקיית השורש המשותפת
  /// (ההורה של books ו-index), בלי אפשרות ניקוי (הספרייה חיונית לפעולה).
  Widget _buildLibraryLocationWidget(BuildContext context) {
    final booksPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '';
    final rootPath = booksPath.isEmpty ? '' : _libraryRootOf(booksPath);
    final indexPath = _indexPath ?? '';
    final databasesPath = _databasesPath ?? '';

    return SettingsActionTile.pathTile(
      icon: FluentIcons.folder_24_regular,
      title: context.settingsText('מיקום הספרייה והאינדקס'),
      currentPath: rootPath,
      placeholder: context.settingsText('בחר מיקום עבור מאגר הספרים'),
      onFolderChanged: (root) async {
        if (!context.mounted) return;
        await _applyLibraryRootChange(root);
      },
      requestChangeLocation: (_) => _openLibraryDialog(booksPath),
      changeLocationLabel: 'מתקדם',
      onOpenFolder: () => _openInFileManager(rootPath),
      onOpenPath: _openInFileManager,
      pathTargets: [
        PathTarget(
          label: context.settingsText('תיקייה ראשית'),
          path: rootPath,
        ),
        PathTarget(label: context.settingsText('ספרייה'), path: booksPath),
        PathTarget(label: context.settingsText('אינדקס'), path: indexPath),
        PathTarget(
          label: context.settingsText('נתוני משתמש'),
          path: databasesPath,
        ),
      ],
    );
  }

  /// שורת מיקום ספרי היברובוקס — עם אפשרות ניקוי הנתיב
  Widget _buildHebrewBooksLocationWidget(BuildContext context) {
    final pathStr = Settings.getValue<String>(
      SettingsRepository.keyHebrewBooksPath,
    );
    final hasPath = pathStr != null && pathStr.isNotEmpty;

    return SettingsActionTile.pathTile(
      icon: FluentIcons.folder_24_regular,
      title: context.settingsText('מיקום ספרי היברובוקס'),
      currentPath: hasPath ? pathStr : '',
      placeholder: context.settingsText(
        'במידה וקיימים ברשותך ספרים ממאגר זה',
      ),
      onFolderChanged: (path) async {
        if (!context.mounted) return;
        await _showExtractionDialog(context, path, isLibraryPath: false);
        if (mounted) setState(() {});
      },
      requestChangeLocation: makeChangeLocationCallback(
        currentPath: hasPath ? pathStr : '',
        folderName: _hebrewBooksFolderName,
        onPathChanged: (newPath) async {
          if (!context.mounted) return;
          await _showExtractionDialog(context, newPath, isLibraryPath: false);
          if (mounted) setState(() {});
        },
        onAfterMove: hasPath
            ? (newPath) =>
                  _afterMoveUpdateBloc(newPath, UpdateHebrewBooksPath.new)
            : null,
      ),
      onOpenFolder: () => _openInFileManager(hasPath ? pathStr : ''),
      onClearPath: () => _removeHebrewBooksPath(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LibraryBloc, LibraryState>(
      listener: (context, libraryState) {
        if (_isRemovingHebrewPath && !libraryState.isLoading) {
          setState(() => _isRemovingHebrewPath = false);
          if (libraryState.error == null) {
            UiSnack.show(SettingsMessages.hebrewBooksPathRemoved);
          } else {
            UiSnack.showError(
              SettingsMessages.hebrewBooksPathRemoveError(libraryState.error!),
            );
          }
        }

        unawaited(_refreshManualReindexRequirement(libraryState));
      },
      builder: (context, libraryState) {
        return BlocConsumer<SettingsBloc, SettingsState>(
          // הרענון מופעל רק אחרי שה-BLoC סיים `await` של הכתיבה
          // ל-`Settings` ופלט state חדש — אחרת `RefreshLibrary` היה
          // עלול לרוץ לפני שהערך החדש זמין ל-`Settings.getValue`
          // בתוך `_appendUserBooksToLibrary`.
          listenWhen: (prev, curr) =>
              prev.mergeUserBooksIntoLibrary != curr.mergeUserBooksIntoLibrary,
          listener: (context, state) {
            context.read<LibraryBloc>().add(RefreshLibrary());
          },
          builder: (context, state) {
            // זיהוי אמיתי של קיום הספרייה (קובץ seforim.db) — לא רק ערך ההגדרה,
            // כדי שגם הטאב יזהה מצב "אין ספרייה" ויפתח את דיאלוג ההגדרה.
            final libraryEmpty = context.select<NavigationBloc, bool>(
              (b) => b.state.isLibraryEmpty,
            );
            // בניית כפתור בחירת תיקייה רק בדסקטופ והעברה לפאנל
            final hebrewPathWidget = !(Platform.isAndroid || Platform.isIOS)
                ? _buildHebrewBooksLocationWidget(context)
                : null;

            return SingleChildScrollView(
              primary: true,
              padding: const EdgeInsets.all(16.0),
              child: ToolPanelWrapper(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // מאגר הספרים (רק בדסקטופ)
                    if (!(Platform.isAndroid || Platform.isIOS)) ...[
                      SettingsCard(
                        cardId: 'library.repository',
                        title: context.settingsText('מאגר הספרים וחיפוש'),
                        subtitle: context.settingsText(
                          'התיקיה שבה נמצאים תיקיות הספרים והאינדקס',
                        ),
                        children: [
                          ..._buildRepositoryCardChildren(
                            context,
                            libraryEmpty,
                          ),
                          ..._buildSearchChildren(context, state, libraryState),
                        ],
                      ),
                      kSettingsCardSpacing,
                    ],

                    // הפאנל המשותף (תצוגה + ספרים נוספים) - כעת כולל את תיקיית היברובוקס בתוכו!
                    LibrarySettingsPanel(
                      hebrewBooksPathWidget: hebrewPathWidget,
                    ),

                    // בחירת מיקום אחסון (Android בלבד) — מוצג רק כשקיים
                    // כרטיס SD; הרכיב עצמו מסתיר את עצמו אחרת.
                    if (Platform.isAndroid) const AndroidStorageLocationCard(),

                    // ייבוא ספרים אישיים (רק במובייל — בדסקטופ יש תיקיות
                    // מותאמות אישית עם גישה ישירה למערכת הקבצים)
                    if (Platform.isAndroid || Platform.isIOS) ...[
                      kSettingsCardSpacing,
                      SettingsCard(
                        cardId: 'library.personal_books_import',
                        title: context.settingsText('ספרים אישיים'),
                        subtitle: context.settingsText(
                          'ייבוא ספרים משלך אל תוך הספרייה',
                        ),
                        children: const [
                          PersonalBooksImportPanel(),
                        ],
                      ),
                    ],

                    // תיקיות מותאמות אישית (רק בדסקטופ)
                    if (!(Platform.isAndroid || Platform.isIOS)) ...[
                      kSettingsCardSpacing,
                      CustomFoldersPanel(
                        mergeToggle: SettingsActionTile.switchTile(
                          icon: FluentIcons.person_24_regular,
                          title: context.settingsText(
                            'מיזוג ספרים אישיים לעץ הספרייה',
                          ),
                          subtitle: state.mergeUserBooksIntoLibrary
                              ? context.settingsText(
                                  'תת-התיקיות של התיקייה הנבחרת ימוזגו לקטגוריות הראשיות לפי שם',
                                )
                              : context.settingsText(
                                  'תיקיות אישיות יוצגו תחת קטגוריית "ספרים אישיים"',
                                ),
                          value: state.mergeUserBooksIntoLibrary,
                          onChanged: (value) {
                            // ה-RefreshLibrary מופעל ב-listener למעלה,
                            // אחרי שהערך החדש נשמר ב-`Settings`. אחרת
                            // הספרייה היתה נבנית עם הערך הישן.
                            context.read<SettingsBloc>().add(
                              UpdateMergeUserBooksIntoLibrary(value),
                            );
                          },
                        ),
                      ),
                      kSettingsCardSpacing,
                      SettingsCard(
                        cardId: 'library.user_content_import',
                        title: context.settingsText(
                          'דורות וקישורים לספרים אישיים',
                        ),
                        subtitle: context.settingsText(
                          'ייבוא קובצי CSV/JSON של סדר דורות וקישורים לספרים האישיים.',
                        ),
                        children: [
                          const UserContentImportTile(),
                        ],
                      ),
                    ],

                    // חיפוש ואינדקס — במובייל ככרטיס נפרד, ללא שורת מיקום
                    // הספרייה (בדסקטופ מוצג בתוך כרטיס מאגר הספרים וחיפוש)
                    if (Platform.isAndroid || Platform.isIOS) ...[
                      kSettingsCardSpacing,
                      SettingsCard(
                        cardId: 'library.repository',
                        title: context.settingsText('חיפוש ואינדקס'),
                        children: _buildSearchChildren(
                          context,
                          state,
                          libraryState,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildSearchChildren(
    BuildContext context,
    SettingsState state,
    LibraryState libraryState,
  ) {
    return [
      SettingsActionTile.switchTile(
        icon: FluentIcons.arrow_clockwise_24_regular,
        title: context.settingsText('עדכון אינדקס אוטומטי'),
        subtitle: state.autoUpdateIndex
            ? context.settingsText('אינדקס החיפוש יתעדכן אוטומטית')
            : context.settingsText('אינדקס החיפוש לא יתעדכן אוטומטית'),
        value: state.autoUpdateIndex,
        onChanged: (value) {
          context.read<SettingsBloc>().add(UpdateAutoUpdateIndex(value));
        },
      ),
      BlocBuilder<IndexingBloc, IndexingState>(
        builder: (context, indexingState) {
          final processed = indexingState.booksProcessed ?? 0;
          final total = indexingState.totalBooks ?? 0;
          final isActive = indexingState is IndexingInProgress && total > 0;
          final isCheckingManualReindex = _requiresManualReindex == null;
          String subtitleText;
          final libraryPath = Settings.getValue<String>(
            SettingsRepository.keyLibraryPath,
          );
          final library = libraryState.library;
          final hasBooks = library?.getAllBooks().isNotEmpty ?? false;
          if (libraryPath == null || libraryPath.isEmpty) {
            subtitleText = context.settingsText('לא קיימת ספרייה לאינדוקס');
          } else if (!hasBooks) {
            subtitleText = context.settingsText(
              'הספרייה ריקה – אין ספרים לאינדוקס',
            );
          } else if (isCheckingManualReindex) {
            subtitleText = context.settingsText(
              'בודק אם נדרש איפוס ואינדוקס מחדש',
            );
          } else if (_requiresManualReindex == true) {
            subtitleText = context.settingsText(
              'נדרש איפוס ואינדוקס מחדש באישור המשתמש',
            );
          } else if (isActive) {
            subtitleText = context.settingsText(
              'התקדמות האינדקס: {processed}/{total}',
              args: {'processed': processed, 'total': total},
            );
          } else if (indexingState is IndexingComplete) {
            subtitleText = context.settingsText('האינדקס מעודכן');
          } else {
            subtitleText = context.settingsText('האינדקס לא מעודכן');
          }
          return SettingsActionTile.text(
            icon: FluentIcons.table_24_regular,
            title: context.settingsText('אינדקס חיפוש'),
            subtitle: subtitleText,
            actions: [
              if (isActive)
                ActionButton.neutral(
                  text: context.settingsText('עצור'),
                  onPressed: () async {
                    final result = await showWarningDialog(
                      context: context,
                      title: context.settingsText('עצירת עדכון'),
                      content: context.settingsText(
                        'האם לעצור את תהליך עדכון האינדקס?',
                      ),
                      confirmText: context.settingsText('עצור'),
                    );
                    if (!context.mounted) return;
                    if (result == true) {
                      context.read<IndexingBloc>().add(CancelIndexing());
                    }
                  },
                )
              else if (isCheckingManualReindex)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_requiresManualReindex == true)
                ActionButton.recommended(
                  text: context.settingsText('אפס ועדכן'),
                  onPressed: () async {
                    if (library == null) return;
                    final indexingBloc = context.read<IndexingBloc>();
                    await _indexingRepository.clearIndex();
                    if (!mounted) return;
                    setState(() => _requiresManualReindex = false);
                    indexingBloc.add(StartIndexing(library));
                  },
                )
              else if (indexingState is IndexingComplete)
                ActionButton.ghost(
                  text: context.settingsText('איפוס'),
                  onPressed: () async {
                    final result = await showWarningDialog(
                      context: context,
                      title: context.settingsText('איפוס אינדקס'),
                      content: context.settingsText(
                        'האם למחוק את אינדקס החיפוש? תצטרך לבנות אותו מחדש כדי להשתמש בחיפוש.',
                      ),
                      confirmText: context.settingsText('אפס'),
                    );
                    if (!context.mounted) return;
                    if (result == true) {
                      context.read<IndexingBloc>().add(ClearIndex());
                    }
                  },
                )
              else
                ActionButton.recommended(
                  text: context.settingsText('עדכן'),
                  onPressed: () {
                    final library = context.read<LibraryBloc>().state.library;
                    if (library != null) {
                      context.read<IndexingBloc>().add(StartIndexing(library));
                    }
                  },
                ),
            ],
          );
        },
      ),
    ];
  }
}
