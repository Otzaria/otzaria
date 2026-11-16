import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/open_tool_tab.dart';
import 'package:otzaria/tools/tool_query.dart';
import 'package:otzaria/tools/dictionary/widgets/aramaic_dictionary_entry_view.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// כמה צירופים ארמיים שרק *מכילים* את המילה המסומנת מוצגים בתפריט. מילה שכיחה
/// ("ליה", "לא") מופיעה במאות צירופים, ותפריט כזה אינו שמיש.
const int _maxContainingAramaicMatches = 8;

/// פותח את כלי המילון הארמי עם הטקסט המסומן בשדה החיפוש.
void _openInAramaicTool(BuildContext context, String text) {
  openToolTabById(
    context,
    'builtin.aramaic_dictionary',
    query: ToolQuery(text),
  );
}

/// בונה פריטי תפריט הקשר למילונים על סמך הטקסט המסומן.
///
/// [openInDictionaryTool] מחליף את פתיחת הכלי (לבדיקות); ברירת המחדל פותחת
/// כרטיסיית מילון ארמי-עברי עם הטקסט המסומן.
List<AppContextMenuEntry> buildDictionaryContextMenuEntries({
  required BuildContext context,
  required String? selectedText,
  required DictionaryLookupRepository repository,
  void Function(BuildContext context, String text)? openInDictionaryTool,
}) {
  final trimmed = selectedText?.trim() ?? '';
  if (trimmed.isEmpty) {
    return const <AppContextMenuEntry>[];
  }

  final entries = <AppContextMenuEntry>[];
  final shouldCheckAcronyms = repository.isLikelyAcronym(trimmed);

  if (shouldCheckAcronyms && !repository.areAcronymsLoaded) {
    unawaited(repository.ensureAcronymsLoaded().catchError((_) {}));
  }

  if (!repository.areAramaicLoaded) {
    unawaited(repository.ensureAramaicLoaded().catchError((_) {}));
  }

  if (shouldCheckAcronyms && repository.areAcronymsLoaded) {
    final acronymEntries = repository.findAcronymMatches(trimmed);
    if (acronymEntries.isNotEmpty) {
      entries.add(_buildAcronymSubmenu(context, acronymEntries));
    }
  }

  if (repository.areAramaicLoaded) {
    final dictionaries = {...repository.aramaicDictionaryNames};
    final groups = repository.findAramaicMatchGroups(
      trimmed,
      maxContainingMatches: _maxContainingAramaicMatches,
      dictionaries: dictionaries,
    );
    final exact = DictionaryLookupRepository.mergeAramaicMatches(groups.exact);
    final containing = DictionaryLookupRepository.mergeAramaicMatches(
      groups.containing,
    );
    // טקסט מסומן שהוא עצמו אינו מפתח (שלוש מילים ומעלה): צירופים שלמים שנמצאים
    // בתוכו. כשיש התאמה לטקסט כולו מעדיפים אותה, ואין ניחוש צורות.
    final phrases = exact.isEmpty && containing.isEmpty
        ? DictionaryLookupRepository.mergeAramaicMatches(
            repository.findAramaicPhrasesWithin(
              trimmed,
              dictionaries: dictionaries,
            ),
          )
        : const <AramaicDictionaryEntry>[];
    if (exact.isNotEmpty || containing.isNotEmpty || phrases.isNotEmpty) {
      AppContextMenuEntry itemOf(
        AramaicDictionaryEntry entry,
      ) => AppContextMenuEntry(
        label:
            '${entry.aramaic} - ${_summarizeAramaicDefinition(entry.hebrew)}',
        onTap: () => _showMeaningDialog(
          context: context,
          title: entry.aramaic,
          content: _buildAramaicDialogContent(entry),
        ),
      );

      final hidden = groups.hiddenContainingKeys;
      entries.add(
        AppContextMenuEntry(
          label: 'מילון ארמי-עברי',
          icon: OtzariaIcons.alef_near_alef_stam_24_filled,
          children: [
            // קודם ההתאמה המדויקת למילה שסומנה, ואחריה צירופים שמכילים אותה.
            ...exact.map(itemOf),
            if (exact.isNotEmpty && containing.isNotEmpty)
              const AppContextMenuEntry.divider(),
            ...containing.map(itemOf),
            ...phrases.map(itemOf),
            const AppContextMenuEntry.divider(),
            AppContextMenuEntry(
              label: hidden > 0
                  ? 'פתח במילון (עוד $hidden צירופים)'
                  : 'פתח במילון הארמי-עברי',
              icon: FluentIcons.open_24_regular,
              onTap: () => (openInDictionaryTool ?? _openInAramaicTool)(
                context,
                // לטקסט שאינו מפתח פותחים את הצירוף הארוך ביותר שנמצא בו.
                phrases.isEmpty ? trimmed : phrases.first.aramaic,
              ),
            ),
          ],
        ),
      );
    }
  }

  return entries;
}

AppContextMenuEntry _buildAcronymSubmenu(
  BuildContext context,
  List<AcronymDictionaryEntry> acronymEntries,
) {
  final items = acronymEntries.length == 1
      ? acronymEntries.single.meanings
            .map<AppContextMenuEntry>(
              (meaning) => AppContextMenuEntry(
                label: _summarizePlainText(meaning),
                onTap: () => _showMeaningDialog(
                  context: context,
                  title: acronymEntries.single.acronym,
                  content: _buildAcronymDialogContent(meaning),
                ),
              ),
            )
            .toList()
      : acronymEntries
            .map<AppContextMenuEntry>(
              (entry) => entry.meanings.length == 1
                  ? AppContextMenuEntry(
                      label:
                          '${entry.acronym} - ${_summarizePlainText(entry.meanings.single)}',
                      onTap: () => _showMeaningDialog(
                        context: context,
                        title: entry.acronym,
                        content: _buildAcronymDialogContent(
                          entry.meanings.single,
                        ),
                      ),
                    )
                  : AppContextMenuEntry(
                      label: entry.acronym,
                      children: entry.meanings
                          .map<AppContextMenuEntry>(
                            (meaning) => AppContextMenuEntry(
                              label: _summarizePlainText(meaning),
                              onTap: () => _showMeaningDialog(
                                context: context,
                                title: entry.acronym,
                                content: _buildAcronymDialogContent(meaning),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            )
            .toList();

  return AppContextMenuEntry(
    label: 'פתיחת ראשי תיבות',
    icon: FluentIcons.text_quote_24_regular,
    children: items,
  );
}

String _summarizeAramaicDefinition(String definition) {
  final presentation = AramaicDictionaryEntryPresentation.parse(definition);
  final summary = presentation.meanings
      .map((meaning) {
        final parts = <String>[
          if (meaning.expression != null && meaning.expression!.isNotEmpty)
            meaning.expression!,
          if (meaning.mainText.isNotEmpty) meaning.mainText,
          if (meaning.expansion != null && meaning.expansion!.isNotEmpty)
            meaning.expansion!,
        ];

        return parts.join(' ');
      })
      .where((part) => part.isNotEmpty)
      .join('; ');

  return _summarizePlainText(
    AramaicDictionaryEntryPresentation.stripBold(summary),
  );
}

String _summarizePlainText(String text, {int maxLength = 90}) {
  final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= maxLength) {
    return compact;
  }

  return '${compact.substring(0, maxLength - 1).trim()}…';
}

Widget _buildAcronymDialogContent(String meaning) {
  return SizedBox(
    width: 460,
    child: SingleChildScrollView(
      child: AppSelectionArea(
        child: Text(
          meaning,
        ),
      ),
    ),
  );
}

Widget _buildAramaicDialogContent(AramaicDictionaryEntry entry) {
  return SizedBox(
    width: 520,
    child: SingleChildScrollView(
      child: AppSelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AramaicDictionaryEntryView(
              definition: entry.hebrew,
              skipRepeatedMeanings: true,
            ),
          ],
        ),
      ),
    ),
  );
}

void _showMeaningDialog({
  required BuildContext context,
  required String title,
  required Widget content,
}) {
  context.read<TourCubit>().recordInteraction(
    TourInteraction(
      type: TourInteractionType.dictionaryUsed,
    ),
  );
  showSingleActionDialog(
    context: context,
    title: title,
    icon: FluentIcons.book_open_24_regular,
    size: AppDialogSize.medium,
    customContent: content,
    confirmText: 'סגור',
  );
}
