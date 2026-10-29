import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/tabs/text_settings_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// פאנל הגדרות תצוגת הספרים — משמש גם כ-overlay צף וגם כתוכן הדיאלוג
/// ([showReadingSettingsDialog]). הגלילה מטופלת בתוך [TextSettingsTab].
///
/// מזהה אם הטאב הפעיל מוצג במצב "צורת הדף" — ובמקרה זה מסתיר את סליידר
/// "גודל גופן מפרשים", שכן בצורת הדף גודל גופן המפרשים נשלט בהגדרה ייעודית
/// נפרדת (בדיאלוג צורת הדף) ולא בהגדרה הכללית.
class ReadingSettingsPanel extends StatelessWidget {
  const ReadingSettingsPanel({super.key});

  static bool _isPageShape(TextBookState state) =>
      state is TextBookLoaded && state.showPageShapeView;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, tabsState) {
        final currentTab = tabsState.currentTab;
        if (currentTab is TextBookTab) {
          return BlocBuilder<TextBookBloc, TextBookState>(
            bloc: currentTab.bloc,
            // הפאנל נשאר חי גם כשהוא סגור, וגלילה בקורא משדרת מצב בכל שורה.
            buildWhen: (previous, current) =>
                _isPageShape(previous) != _isPageShape(current),
            // מופע const זהה עוצר כאן את הבנייה: בלעדיו כל שינוי בטאבים (מעבר,
            // סימון, סידור) בונה מחדש את כל ההגדרות, גם כשהפאנל סגור.
            builder: (context, textState) => _isPageShape(textState)
                ? const TextSettingsTab(
                    isDialog: true,
                    hideCommentaryFontSize: true,
                  )
                : const TextSettingsTab(isDialog: true),
          );
        }
        return const TextSettingsTab(isDialog: true);
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
        headerBand: true,
        confirmText: context.settingsText('סגור'),
        customContent: SizedBox(
          width: 650,
          height: MediaQuery.of(context).size.height * 0.7,
          child: const ReadingSettingsPanel(),
        ),
      ),
    ),
  );
}
