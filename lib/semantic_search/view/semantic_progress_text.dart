import 'package:flutter/widgets.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

/// התווית המתורגמת עם האחוז הכולל: "מוריד את נתוני החיפוש (12%)".
String semanticProgressText(
  BuildContext context,
  SemanticDownloadProgress progress,
) {
  final label = context.settingsText(
    SemanticSearchMessages.progressAction(progress),
  );
  final percent = SemanticSearchMessages.progressPercent(progress);
  return percent == null
      ? label
      : context.settingsText(
          SemanticSearchMessages.percentTemplate,
          args: {'label': label, 'percent': percent},
        );
}
