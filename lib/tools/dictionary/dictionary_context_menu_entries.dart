import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/dictionary/widgets/aramaic_dictionary_entry_view.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// בונה פריטי תפריט הקשר למילונים על סמך הטקסט המסומן.
List<AppContextMenuEntry> buildDictionaryContextMenuEntries({
  required BuildContext context,
  required String? selectedText,
  required DictionaryLookupRepository repository,
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
    final aramaicMatches = repository.findAramaicMatches(trimmed);
    if (aramaicMatches.isNotEmpty) {
      entries.add(
        AppContextMenuEntry(
          label: 'מילון ארמי-עברי',
          icon: FluentIcons.translate_24_regular,
          children: aramaicMatches
              .map<AppContextMenuEntry>(
                (entry) => AppContextMenuEntry(
                  label:
                      '${entry.aramaic} - ${_summarizeAramaicDefinition(entry.hebrew)}',
                  onTap: () => _showMeaningDialog(
                    context: context,
                    title: entry.aramaic,
                    content: _buildAramaicDialogContent(entry),
                  ),
                ),
              )
              .toList(),
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

  return _summarizePlainText(summary);
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
      child: SelectionArea(
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
      child: SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AramaicDictionaryEntryView(
              definition: entry.hebrew,
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
    customContent: content,
    confirmText: 'סגור',
  );
}
