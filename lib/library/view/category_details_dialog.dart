import 'package:flutter/material.dart';
import 'package:otzaria/library/models/library.dart';
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
      width: 450,
      child: AppSelectionArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailsInfoSection(
                title: 'שם הקטגוריה:',
                value: category.title,
              ),
              if (shortDescription.isNotEmpty)
                DetailsInfoSection(
                  title: 'תיאור קצר:',
                  value: category.shortDescription,
                ),
              if (fullDescription.isNotEmpty)
                DetailsInfoSection(
                  title: 'תיאור מורחב:',
                  value: category.description,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
