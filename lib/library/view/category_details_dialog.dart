import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// מציג את כל פרטי הקטגוריה הזמינים.
Future<void> showCategoryDetailsDialog(
  BuildContext context,
  Category category,
) async {
  await showSingleActionDialog(
    context: context,
    title: 'אודות הקטגוריה',
    icon: FluentIcons.folder_24_regular,
    headerBand: true,
    confirmText: 'סגור',
    customContent: _CategoryDetailsDialogContent(category: category),
  );
}

class _CategoryDetailsDialogContent extends StatelessWidget {
  const _CategoryDetailsDialogContent({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    final shortDescription = category.shortDescription.trim();
    final fullDescription = category.description.trim();

    return SizedBox(
      width: 500,
      child: AppSelectionArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailsHeading(
                title: category.title,
                subtitle: shortDescription,
              ),
              if (fullDescription.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spaceMD),
                DetailsCard(
                  title: 'תיאור',
                  icon: FluentIcons.document_text_24_regular,
                  children: [DetailsText(category.description)],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
