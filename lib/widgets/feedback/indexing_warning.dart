import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';

/// מצב אזהרת האינדקס המוצג למשתמש.
enum IndexingWarningMode {
  /// אינדקס קיים אך נמצא בתהליך עדכון/בנייה - חיפוש אפשרי, חלק מהתוצאות עלול לחסור.
  inProgress,

  /// אין אינדקס כלל - לא ניתן לבצע חיפוש שמשתמש באינדקס.
  missing,
}

/// מחשב את מצב אזהרת האינדקס לפי ה-Bloc + הספרים המאונדקסים שנקראו
/// מהאינדקס עצמו. אסור להסיק "missing" לפני ש-TantivyDataProvider סיים
/// לקרוא את indexedFilePaths מהאינדקס (אחרת תוצג אזהרה שגויה בחלון
/// אתחול האפליקציה).
///
/// מחזיר null כשאין אזהרה (אינדקס תקין או שעוד לא ידוע), או כש-inProgress
/// אבל [inProgressDismissed] מסמן שהמשתמש סגר את הבאנר.
IndexingWarningMode? resolveIndexingWarningMode({
  required IndexingState state,
  required bool providerInitialized,
  required bool inProgressDismissed,
}) {
  if (providerInitialized &&
      TantivyDataProvider.instance.indexedFilePaths.isEmpty) {
    return IndexingWarningMode.missing;
  }
  if (state is IndexingInProgress && !inProgressDismissed) {
    return IndexingWarningMode.inProgress;
  }
  return null;
}

/// האם יש לחסום חיפוש שמשתמש באינדקס. מתאים בדיוק ל-mode == missing.
/// אם ה-provider עוד לא הסתיים לטעון, לא חוסמים — לא ידוע אם יש אינדקס.
bool isSearchBlockedByMissingIndex({required bool providerInitialized}) {
  return providerInitialized &&
      TantivyDataProvider.instance.indexedFilePaths.isEmpty;
}

/// וידג'ט באנר אזהרה (ללא state חיצוני). השתמש ב-[IndexingWarningContainer]
/// אם אתה רוצה גם לחבר אוטומטית ל-IndexingBloc + TantivyDataProvider.
class IndexingWarning extends StatelessWidget {
  final VoidCallback? onDismiss;
  final IndexingWarningMode mode;

  const IndexingWarning({
    super.key,
    this.onDismiss,
    this.mode = IndexingWarningMode.inProgress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = switch (mode) {
      IndexingWarningMode.inProgress =>
        'אינדקס החיפוש בתהליך עדכון. יתכן שחלק מהספרים לא יוצגו בתוצאות החיפוש.',
      IndexingWarningMode.missing =>
        'אינדקס לא קיים, לא ניתן לבצע חיפוש זה ללא אינדקס.',
    };
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        children: [
          Icon(FluentIcons.warning_24_regular, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              textAlign: TextAlign.right,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          if (onDismiss != null && mode == IndexingWarningMode.inProgress)
            IconButton(
              icon: const Icon(FluentIcons.dismiss_24_regular),
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}

/// באנר אזהרת אינדקס המחובר אוטומטית ל-IndexingBloc ולסטטוס הטעינה של
/// TantivyDataProvider. מחליף לוגיקה כפולה ב-search_dialog ו-tantivy_full_text_search.
///
/// הקריאה לטיפול ב"סגור" מועברת ב-[onDismiss]; כשהמצב missing הבאנר אינו
/// ניתן לסגירה (החיפוש חסום בכל מקרה).
class IndexingWarningContainer extends StatelessWidget {
  /// האם המשתמש סגר את אזהרת ה-inProgress. ה-StatefulWidget שמחזיק את הדיאלוג
  /// מנהל את הדגל הזה (כי הוא חי עד סגירת הדיאלוג, לא יותר מכך).
  final bool inProgressDismissed;

  /// נקרא כשהמשתמש סוגר את אזהרת ה-inProgress.
  final VoidCallback onDismiss;

  const IndexingWarningContainer({
    super.key,
    required this.inProgressDismissed,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: TantivyDataProvider.instance.isInitialized,
      builder: (context, providerInitialized, _) {
        return BlocBuilder<IndexingBloc, IndexingState>(
          builder: (context, state) {
            final mode = resolveIndexingWarningMode(
              state: state,
              providerInitialized: providerInitialized,
              inProgressDismissed: inProgressDismissed,
            );
            if (mode == null) return const SizedBox.shrink();
            return IndexingWarning(
              mode: mode,
              onDismiss: mode == IndexingWarningMode.inProgress
                  ? onDismiss
                  : null,
            );
          },
        );
      },
    );
  }
}
