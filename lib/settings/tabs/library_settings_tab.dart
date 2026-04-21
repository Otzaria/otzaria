import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/settings/panels/library_settings_panel.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folders_tile.dart';
import 'package:otzaria/widgets/zip_extraction_progress_dialog.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/core/ui_snack.dart';

/// טאב הגדרות ספרייה
class LibrarySettingsTab extends StatefulWidget {
  const LibrarySettingsTab({super.key});

  @override
  State<LibrarySettingsTab> createState() => _LibrarySettingsTabState();
}

class _LibrarySettingsTabState extends State<LibrarySettingsTab> {
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

  /// פונקציית בניית ווידג'ט מיקום ספריית אוצריא
  Widget _buildLibraryLocationWidget(BuildContext context) {
    final pathStr =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath);
    final hasPath = pathStr != null;

    return ListTile(
      hoverColor: Colors.transparent,
      leading: const Icon(FluentIcons.folder_24_regular),
      title: const Text('מיקום ספריית אוצריא', style: kSettingsTitleStyle),
      subtitle: Text(
        hasPath ? pathStr : 'בחר מיקום עבור מאגר הספרים',
        style: kSettingsSubtitleStyle,
        textDirection: TextDirection.rtl,
      ),
      trailing: Wrap(
        spacing: 8,
        children: [
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
              String? path = await FilePicker.platform.getDirectoryPath();
              if (path != null && context.mounted) {
                await _showExtractionDialog(context, path, isLibraryPath: true);
                if (mounted) setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  /// פונקציית בניית ווידג'ט מיקום היברובוקס המועברת לפאנל המשותף
  Widget _buildHebrewBooksLocationWidget(BuildContext context) {
    final pathStr =
        Settings.getValue<String>(SettingsRepository.keyHebrewBooksPath);
    final hasPath = pathStr != null;

    return ListTile(
      hoverColor: Colors.transparent,
      leading: const Icon(FluentIcons.folder_24_regular),
      title: const Text('מיקום ספרי היברובוקס', style: kSettingsTitleStyle),
      subtitle: Text(
        hasPath ? pathStr : 'במידה וקיימים ברשותך ספרים ממאגר זה',
        style: kSettingsSubtitleStyle,
        textDirection: TextDirection.rtl,
      ),
      trailing: Wrap(
        spacing: 8,
        children: [
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
              String? path = await FilePicker.platform.getDirectoryPath();
              if (path != null && context.mounted) {
                await _showExtractionDialog(context, path,
                    isLibraryPath: false);
                if (mounted) setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        // בניית כפתור בחירת תיקייה רק בדסקטופ והעברה לפאנל
        final hebrewPathWidget = !(Platform.isAndroid || Platform.isIOS)
            ? _buildHebrewBooksLocationWidget(context)
            : null;

        return SingleChildScrollView(
          primary: true,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // מאגר הספרים (רק בדסקטופ)
              if (!(Platform.isAndroid || Platform.isIOS)) ...[
                SettingsCard(
                  title: 'מאגר הספרים',
                  children: [
                    _buildLibraryLocationWidget(context),
                  ],
                ),
                kSettingsCardSpacing,
              ],

              // הפאנל המשותף (תצוגה + ספרים נוספים) - כעת כולל את תיקיית היברובוקס בתוכו!
              LibrarySettingsPanel(hebrewBooksPathWidget: hebrewPathWidget),

              // תיקיות מותאמות אישית (רק בדסקטופ)
              if (!(Platform.isAndroid || Platform.isIOS)) ...[
                kSettingsCardSpacing,
                SettingsCard(
                  title: 'תיקיות מותאמות אישית',
                  children: const [
                    CustomFoldersTile(),
                  ],
                ),
              ],

              // חיפוש ואינדקס
              kSettingsCardSpacing,
              _buildSearchSection(context, state),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchSection(BuildContext context, SettingsState state) {
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
            String subtitleText;
            TextDirection subtitleDirection = TextDirection.rtl;
            final libraryPath =
                Settings.getValue<String>(SettingsRepository.keyLibraryPath);
            final library = context.watch<LibraryBloc>().state.library;
            final hasBooks = library?.getAllBooks().isNotEmpty ?? false;
            if (libraryPath == null || libraryPath.isEmpty) {
              subtitleText = 'לא קיימת ספרייה לאינדוקס';
            } else if (!hasBooks) {
              subtitleText = 'הספרייה ריקה – אין ספרים לאינדוקס';
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
              hoverColor: Colors.transparent,
              trailing: isActive
                  ? NeutralActionButton(
                      text: 'עצור',
                      onPressed: () async {
                        final result = await showWarningDialog(
                          context: context,
                          title: 'עצירת עדכון',
                          content: 'האם לעצור את תהליך עדכון האינדקס?',
                        );
                        if (!context.mounted) return;
                        if (result == true) {
                          context.read<IndexingBloc>().add(CancelIndexing());
                        }
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
                            );
                            if (!context.mounted) return;
                            if (result == true) {
                              context.read<IndexingBloc>().add(ClearIndex());
                            }
                          },
                        )
                      : RecommendedActionButton(
                          text: 'עדכן',
                          onPressed: () {
                            final library =
                                context.read<LibraryBloc>().state.library;
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
