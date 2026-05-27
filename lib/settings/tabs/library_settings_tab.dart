import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/widgets/settings_action_tile.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/settings/panels/library_settings_panel.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folders_tile.dart';
import 'package:otzaria/widgets/dialogs/zip_extraction_progress_dialog.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/core/ui_snack.dart';

/// טאב הגדרות ספרייה
class LibrarySettingsTab extends StatefulWidget {
  const LibrarySettingsTab({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'library.location.path',
      title: 'מיקום ספריית אוצריא',
      subtitle: 'התיקייה בה נשמרים ספרי אוצריא',
      tab: SettingsTab.library,
      cardId: 'library.repository',
      keywords: ['נתיב', 'תיקיה', 'מאגר'],
    ),
    SettingsSearchEntry(
      id: 'library.location.hebrewbooks',
      title: 'מיקום ספרי היברובוקס',
      subtitle: 'תיקיית ספרי HebrewBooks',
      tab: SettingsTab.library,
      cardId: 'library.display',
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
      id: 'library.custom_folders.merge_into_library',
      title: 'מיזוג ספרים אישיים לעץ הספרייה',
      subtitle:
          'תת-התיקיות של התיקייה הנבחרת ימוזגו לקטגוריות הראשיות לפי שם',
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
    SettingsSearchEntry(
      id: 'library.search.auto_index',
      title: 'עדכון אינדקס אוטומטי',
      subtitle: 'אינדקס החיפוש יתעדכן אוטומטית',
      tab: SettingsTab.library,
      cardId: 'library.search',
      keywords: ['חיפוש', 'אינדקס', 'אוטומטי', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'library.search.index_status',
      title: 'אינדקס חיפוש',
      subtitle: 'סטטוס ועדכון אינדקס החיפוש',
      tab: SettingsTab.library,
      cardId: 'library.search',
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
  ];

  @override
  State<LibrarySettingsTab> createState() => _LibrarySettingsTabState();
}

class _LibrarySettingsTabState extends State<LibrarySettingsTab> {
  bool _isRemovingHebrewPath = false;
  final IndexingRepository _indexingRepository =
      IndexingRepository(TantivyDataProvider.instance);
  bool? _requiresManualReindex;

  @override
  void initState() {
    super.initState();
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
      LibraryState libraryState) async {
    final library = libraryState.library;
    if (!mounted || library == null) {
      if (_requiresManualReindex != false) {
        setState(() => _requiresManualReindex = false);
      }
      return;
    }

    final requiresManualReindex =
        await _indexingRepository.requiresManualReindex(library);
    if (!mounted || _requiresManualReindex == requiresManualReindex) {
      return;
    }

    setState(() {
      _requiresManualReindex = requiresManualReindex;
    });
  }

  Future<void> _showExtractionDialog(BuildContext context, String path,
      {required bool isLibraryPath}) async {
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
                'הקובץ "${extractionResult.extractedFileName}" חולץ בהצלחה!');
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

  /// פונקציית בניית ווידג'ט מיקום ספריית אוצריא
  Widget _buildLibraryLocationWidget(BuildContext context) {
    final pathStr =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath);
    final hasPath = pathStr != null;

    final actions = <Widget>[
      if (hasPath)
        NeutralActionButton(
          text: 'העתק נתיב',
          icon: FluentIcons.copy_24_regular,
          onPressed: () async {
            try {
              await Clipboard.setData(ClipboardData(text: pathStr));
              if (context.mounted) {
                UiSnack.show(UiSnack.textCopied);
              }
            } catch (e) {
              if (context.mounted) {
                UiSnack.showError('שגיאה בהעתקה: ${e.toString()}');
              }
            }
          },
        ),
      RecommendedActionButton(
        text: hasPath ? 'שנה מיקום' : 'בחר מיקום',
        icon: FluentIcons.folder_24_regular,
        onPressed: () async {
          String? path =
              await FilePicker.getDirectoryPath(lockParentWindow: true);
          if (path != null && context.mounted) {
            await _showExtractionDialog(context, path, isLibraryPath: true);
            if (mounted) setState(() {});
          }
        },
      ),
    ];

    return SettingsActionTile.text(
      icon: FluentIcons.folder_24_regular,
      title: 'מיקום ספריית אוצריא',
      subtitle: hasPath ? pathStr : 'בחר מיקום עבור מאגר הספרים',
      actions: actions,
    );
  }

  /// פונקציית בניית ווידג'ט מיקום היברובוקס המועברת לפאנל המשותף
  Widget _buildHebrewBooksLocationWidget(BuildContext context) {
    final pathStr =
        Settings.getValue<String>(SettingsRepository.keyHebrewBooksPath);
    final hasPath = pathStr != null && pathStr.isNotEmpty;

    final actions = <Widget>[
      if (hasPath)
        NeutralActionButton(
          text: 'העתק נתיב',
          icon: FluentIcons.copy_24_regular,
          onPressed: () async {
            try {
              await Clipboard.setData(ClipboardData(text: pathStr));
              if (context.mounted) {
                UiSnack.show(UiSnack.textCopied);
              }
            } catch (e) {
              if (context.mounted) {
                UiSnack.showError('שגיאה בהעתקה: ${e.toString()}');
              }
            }
          },
        ),
      RecommendedActionButton(
        text: hasPath ? 'שנה מיקום' : 'בחר מיקום',
        icon: FluentIcons.folder_24_regular,
        onPressed: () async {
          String? path =
              await FilePicker.getDirectoryPath(lockParentWindow: true);
          if (path != null && context.mounted) {
            await _showExtractionDialog(context, path, isLibraryPath: false);
            if (mounted) setState(() {});
          }
        },
      ),
      if (hasPath)
        IconButton(
          icon: const Icon(FluentIcons.delete_24_regular),
          onPressed: () => _removeHebrewBooksPath(context),
          tooltip: 'הסר מיקום',
        ),
    ];

    return SettingsActionTile.text(
      icon: FluentIcons.folder_24_regular,
      title: 'מיקום ספרי היברובוקס',
      subtitle: hasPath ? pathStr : 'במידה וקיימים ברשותך ספרים ממאגר זה',
      actions: actions,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LibraryBloc, LibraryState>(
      listener: (context, libraryState) {
        if (_isRemovingHebrewPath && !libraryState.isLoading) {
          setState(() => _isRemovingHebrewPath = false);
          if (libraryState.error == null) {
            UiSnack.show('מיקום ספרי היברובוקס הוסר בהצלחה');
          } else {
            UiSnack.showError('שגיאה בהסרת המיקום: ${libraryState.error}');
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
                      SettingsAnchor(
                        cardId: 'library.repository',
                        child: SettingsCard(
                          title: 'מאגר הספרים',
                          children: [
                            _buildLibraryLocationWidget(context),
                          ],
                        ),
                      ),
                      kSettingsCardSpacing,
                    ],

                    // הפאנל המשותף (תצוגה + ספרים נוספים) - כעת כולל את תיקיית היברובוקס בתוכו!
                    SettingsAnchor(
                      cardId: 'library.display',
                      child: LibrarySettingsPanel(
                          hebrewBooksPathWidget: hebrewPathWidget),
                    ),

                    // תיקיות מותאמות אישית (רק בדסקטופ)
                    if (!(Platform.isAndroid || Platform.isIOS)) ...[
                      kSettingsCardSpacing,
                      SettingsAnchor(
                        cardId: 'library.custom_folders',
                        child: SettingsCard(
                          title: 'תיקיות מותאמות אישית',
                          children: [
                            const CustomFoldersTile(),
                            SwitchSettingsTile(
                              leading: const Icon(FluentIcons.person_24_regular),
                              title: const Text(
                                'מיזוג ספרים אישיים לעץ הספרייה',
                                style: kSettingsTitleStyle,
                              ),
                              subtitle: Text(
                                state.mergeUserBooksIntoLibrary
                                    ? 'תת-התיקיות של התיקייה הנבחרת ימוזגו לקטגוריות הראשיות לפי שם'
                                    : 'תיקיות אישיות יוצגו תחת קטגוריית "ספרים אישיים"',
                                style: kSettingsSubtitleStyle,
                              ),
                              value: state.mergeUserBooksIntoLibrary,
                              onChanged: (value) {
                                // ה-RefreshLibrary מופעל ב-listener למעלה,
                                // אחרי שהערך החדש נשמר ב-`Settings`. אחרת
                                // הספרייה היתה נבנית עם הערך הישן.
                                context
                                    .read<SettingsBloc>()
                                    .add(UpdateMergeUserBooksIntoLibrary(value));
                              },
                            ),
                          ],
                        ),
                      ),
                    ],

                    // חיפוש ואינדקס
                    kSettingsCardSpacing,
                    SettingsAnchor(
                      cardId: 'library.search',
                      child: _buildSearchSection(context, state, libraryState),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSearchSection(
    BuildContext context,
    SettingsState state,
    LibraryState libraryState,
  ) {
    return SettingsCard(
      title: 'חיפוש ואינדקס',
      children: [
        SwitchSettingsTile(
          leading: const Icon(FluentIcons.arrow_clockwise_24_regular),
          title: const Text('עדכון אינדקס אוטומטי', style: kSettingsTitleStyle),
          subtitle: Text(
              state.autoUpdateIndex
                  ? 'אינדקס החיפוש יתעדכן אוטומטית'
                  : 'אינדקס החיפוש לא יתעדכן אוטומטית',
              style: kSettingsSubtitleStyle),
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
            TextDirection subtitleDirection = TextDirection.rtl;
            final libraryPath =
                Settings.getValue<String>(SettingsRepository.keyLibraryPath);
            final library = libraryState.library;
            final hasBooks = library?.getAllBooks().isNotEmpty ?? false;
            if (libraryPath == null || libraryPath.isEmpty) {
              subtitleText = 'לא קיימת ספרייה לאינדוקס';
            } else if (!hasBooks) {
              subtitleText = 'הספרייה ריקה – אין ספרים לאינדוקס';
            } else if (isCheckingManualReindex) {
              subtitleText = 'בודק אם נדרש איפוס ואינדוקס מחדש';
            } else if (_requiresManualReindex == true) {
              subtitleText = 'נדרש איפוס ואינדוקס מחדש באישור המשתמש';
            } else if (isActive) {
              subtitleText = 'התקדמות האינדקס: $processed/$total';
            } else if (indexingState is IndexingComplete) {
              subtitleText = 'האינדקס מעודכן';
            } else {
              subtitleText = 'האינדקס לא מעודכן';
            }
            return ListTile(
              leading: const Icon(FluentIcons.table_24_regular),
              title: const Text(
                'אינדקס חיפוש',
                style: kSettingsTitleStyle,
                textDirection: TextDirection.rtl,
              ),
              subtitle: Text(
                subtitleText,
                style: kSettingsSubtitleStyle,
                textDirection: subtitleDirection,
              ),
              trailing: isActive
                  ? NeutralActionButton(
                      text: 'עצור',
                      onPressed: () async {
                        final result = await showWarningDialog(
                          context: context,
                          title: 'עצירת עדכון',
                          content: 'האם לעצור את תהליך עדכון האינדקס?',
                          confirmText: 'עצור',
                        );
                        if (!context.mounted) return;
                        if (result == true) {
                          context.read<IndexingBloc>().add(CancelIndexing());
                        }
                      },
                    )
                  : isCheckingManualReindex
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _requiresManualReindex == true
                          ? RecommendedActionButton(
                              text: 'אפס ועדכן',
                              onPressed: () async {
                                if (library == null) {
                                  return;
                                }

                                final indexingBloc =
                                    context.read<IndexingBloc>();

                                await _indexingRepository
                                    .prepareForManualReindex(
                                  library,
                                );
                                if (!mounted) {
                                  return;
                                }

                                setState(() {
                                  _requiresManualReindex = false;
                                });
                                indexingBloc.add(StartIndexing(library));
                              },
                            )
                          : indexingState is IndexingComplete
                              ? NeutralActionButton(
                                  text: 'איפוס',
                                  onPressed: () async {
                                    final result = await showWarningDialog(
                                      context: context,
                                      title: 'איפוס אינדקס',
                                      content:
                                          'האם למחוק את אינדקס החיפוש? תצטרך לבנות אותו מחדש כדי להשתמש בחיפוש.',
                                      confirmText: 'אפס',
                                    );
                                    if (!context.mounted) return;
                                    if (result == true) {
                                      context
                                          .read<IndexingBloc>()
                                          .add(ClearIndex());
                                    }
                                  },
                                )
                              : RecommendedActionButton(
                                  text: 'עדכן',
                                  onPressed: () {
                                    final library = context
                                        .read<LibraryBloc>()
                                        .state
                                        .library;
                                    if (library != null) {
                                      context
                                          .read<IndexingBloc>()
                                          .add(StartIndexing(library));
                                    }
                                  },
                                ),
            );
          },
        ),
      ],
    );
  }
}
