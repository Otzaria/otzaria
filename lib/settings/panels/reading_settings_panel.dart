import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/tabs/text_settings_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// פאנל הגדרות תצוגת הספרים — משמש גם כ-overlay צף וגם כתוכן הדיאלוג
/// ([showReadingSettingsDialog]). הגלילה מטופלת בתוך [TextSettingsTab].
///
/// מזהה אם הטאב הפעיל מוצג במצב "צורת הדף" — ובמקרה זה מחוון "גודל גופן
/// מפרשים" הוא של צורת הדף, כי שם הגודל הוא הגדרה ייעודית נפרדת.
///
/// בכרטיסיית תוצאות חיפוש מוצגות רק ההגדרות שחלות על התוצאות או על התצוגה
/// המקדימה ([TextSettingsScope.searchResults], #2826), ובכרטיסיית ספר — בלי
/// גודל התוצאות.
class ReadingSettingsPanel extends StatelessWidget {
  const ReadingSettingsPanel({super.key});

  static bool _isPageShape(TextBookState state) =>
      state is TextBookLoaded && state.showPageShapeView;

  static (double?, double?) _bookMetrics(TextBookState state) =>
      state is TextBookLoaded
      ? (state.commentatorsFontSize, state.lineHeight)
      : (null, null);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      // רק מעבר לחלונית אחרת: בלי זה כל שינוי בטאבים (סימון, סידור) בונה מחדש
      // את כל ההגדרות, גם כשהפאנל סגור.
      buildWhen: (previous, current) =>
          !identical(previous.activePane, current.activePane),
      builder: (context, tabsState) {
        final currentTab = tabsState.activePane;
        if (currentTab is TextBookTab) {
          return BlocBuilder<TextBookBloc, TextBookState>(
            bloc: currentTab.bloc,
            // הפאנל נשאר חי גם כשהוא סגור, וגלילה בקורא משדרת מצב בכל שורה.
            buildWhen: (previous, current) =>
                _isPageShape(previous) != _isPageShape(current) ||
                _bookMetrics(previous) != _bookMetrics(current),
            builder: (context, textState) {
              // כשהשמירה לספר מופעלת, גודל המפרשים ומרווח השורות הם של הספר
              // הפעיל (#2306) ולכן הם נבנים מחדש עמו.
              if (context.select(
                (SettingsBloc bloc) => bloc.state.enablePerBookSettings,
              )) {
                return TextSettingsTab(
                  isDialog: true,
                  pageShapeCommentaryFontSize: _isPageShape(textState),
                  scope: TextSettingsScope.book,
                  book: currentTab.bloc,
                );
              }
              // מופע const זהה עוצר כאן את הבנייה: בלעדיו כל מעבר טאב בונה מחדש
              // את כל ההגדרות.
              return _isPageShape(textState)
                  ? const TextSettingsTab(
                      isDialog: true,
                      pageShapeCommentaryFontSize: true,
                      scope: TextSettingsScope.book,
                    )
                  : const TextSettingsTab(
                      isDialog: true,
                      scope: TextSettingsScope.book,
                    );
            },
          );
        }
        if (currentTab is SearchingTab) {
          return const TextSettingsTab(
            isDialog: true,
            scope: TextSettingsScope.searchResults,
          );
        }
        return const TextSettingsTab(
          isDialog: true,
          scope: TextSettingsScope.book,
        );
      },
    );
  }
}

/// מציג את [ReadingSettingsPanel] כדיאלוג. ניתן לקרוא מכל מקום (למשל ממסך העיון).
void showReadingSettingsDialog() {
  final dialogContext = navigatorKey.currentContext;
  if (dialogContext == null) {
    return;
  }

  showDialog(
    context: dialogContext,
    builder: settingsDialogBuilder(
      dialogContext,
      (context) => AppDialog.singleAction(
        title: context.settingsText('הגדרות תצוגת הספרים'),
        icon: FluentIcons.text_font_24_regular,
        size: AppDialogSize.large,
        confirmText: context.settingsText('סגור'),
        customContent: const ReadingSettingsPanel(),
      ),
    ),
  );
}
