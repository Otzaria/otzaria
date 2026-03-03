import 'package:flutter/material.dart';
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
import 'package:otzaria/widgets/custom_ui_components.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';

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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'הקובץ "${extractionResult.extractedFileName}" חולץ בהצלחה!'),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          }
        }
      },
      onError: (errorMessage) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. הפאנל המשותף (תצוגה + ספרים חיצוניים)
              const LibraryBasicSettingsPanel(),

              // מיקום ספריות (רק בדסקטופ)
              if (!(Platform.isAndroid || Platform.isIOS)) ...[
                const SizedBox(height: 16),
                SettingsCard(
                  title: 'מיקום ספריות',
                  children: [
                    Tooltip(
                      message: 'במידה וקיימים ברשותך ספרים ממאגר זה',
                      child: ListTile(
                        leading: const Icon(FluentIcons.folder_24_regular),
                        title: const Text('מיקום ספרי היברובוקס',
                            style: TextStyle(fontSize: 16)),
                        subtitle: Text(
                          Settings.getValue<String>(
                                  SettingsRepository.keyHebrewBooksPath) ??
                              'לא קיים',
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: _buildHebrewBooksPathButton(context),
                      ),
                    ),
                  ],
                ),
              ],

              // תיקיות מותאמות אישית (רק בדסקטופ)
              if (!(Platform.isAndroid || Platform.isIOS)) ...[
                const SizedBox(height: 16),
                SettingsCard(
                  title: 'תיקיות מותאמות אישית',
                  children: const [
                    CustomFoldersTile(),
                  ],
                ),
              ],

              // חיפוש ואינדקס
              const SizedBox(height: 16),
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
          leading: const Icon(FluentIcons.search_24_regular),
          title: const Text('חיפוש מהיר באמצעות אינדקס',
              style: TextStyle(fontSize: 16)),
          subtitle: Text(
              state.useFastSearch
                  ? 'חיפוש מהיר יותר, נדרש ליצור אינדקס'
                  : 'חיפוש איטי יותר, לא נדרש אינדקס',
              style: const TextStyle(fontSize: 13)),
          value: state.useFastSearch,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateUseFastSearch(value));
          },
        ),
        SwitchSettingsTile(
          leading: const Icon(FluentIcons.arrow_clockwise_24_regular),
          title: const Text('עדכון אינדקס אוטומטי',
              style: TextStyle(fontSize: 16)),
          subtitle: Text(
              state.autoUpdateIndex
                  ? 'אינדקס החיפוש יתעדכן אוטומטית'
                  : 'אינדקס החיפוש לא יתעדכן אוטומטית',
              style: const TextStyle(fontSize: 13)),
          value: state.autoUpdateIndex,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateAutoUpdateIndex(value));
          },
        ),
        BlocBuilder<IndexingBloc, IndexingState>(
          builder: (context, indexingState) {
            return ListTile(
              leading: const Icon(FluentIcons.table_24_regular),
              title: const Text('אינדקס חיפוש', style: TextStyle(fontSize: 16)),
              subtitle: Text(
                  indexingState is IndexingInProgress
                      ? 'התקדמות האינדקס: ${indexingState.booksProcessed}/${indexingState.totalBooks}'
                      : indexingState is IndexingComplete
                          ? 'האינדקס מעודכן'
                          : 'האינדקס לא מעודכן',
                  style: const TextStyle(fontSize: 13)),
              hoverColor: Colors.transparent,
              trailing: indexingState is IndexingInProgress
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

  Widget _buildHebrewBooksPathButton(BuildContext context) {
    final hasPath =
        Settings.getValue<String>(SettingsRepository.keyHebrewBooksPath) !=
            null;
    return RecommendedActionButton(
      text: hasPath ? 'שנה מיקום' : 'בחר מיקום',
      icon: FluentIcons.folder_24_regular,
      onPressed: () async {
        String? path = await FilePicker.platform.getDirectoryPath();
        if (path != null && context.mounted) {
          await _showExtractionDialog(context, path, isLibraryPath: false);
          if (mounted) setState(() {}); // רענון תצוגה לאחר שינוי נתיב
        }
      },
    );
  }
}
