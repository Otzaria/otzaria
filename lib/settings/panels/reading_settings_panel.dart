import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/tabs/text_settings_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

/// פאנל הגדרות תצוגת הספרים — משמש גם כ-overlay צף וגם כתוכן הדיאלוג
/// ([showReadingSettingsDialog]). הגלילה מטופלת בתוך [TextSettingsTab].
///
/// מזהה אם הטאב הפעיל מוצג במצב "צורת הדף" — ובמקרה זה מסתיר את סליידר
/// "גודל גופן מפרשים", שכן בצורת הדף גודל גופן המפרשים נשלט בהגדרה ייעודית
/// נפרדת (בדיאלוג צורת הדף) ולא בהגדרה הכללית.
class ReadingSettingsPanel extends StatelessWidget {
  const ReadingSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, tabsState) {
        final currentTab = tabsState.currentTab;
        if (currentTab is TextBookTab) {
          return BlocBuilder<TextBookBloc, TextBookState>(
            bloc: currentTab.bloc,
            builder: (context, textState) {
              final isPageShape =
                  textState is TextBookLoaded && textState.showPageShapeView;
              return TextSettingsTab(
                isDialog: true,
                hideCommentaryFontSize: isPageShape,
              );
            },
          );
        }
        return const TextSettingsTab(isDialog: true);
      },
    );
  }
}

/// מציג את [ReadingSettingsPanel] כדיאלוג. ניתן לקרוא מכל מקום (למשל ממסך העיון).
void showReadingSettingsDialog(BuildContext context) {
  final dialogContext = navigatorKey.currentContext;
  if (dialogContext == null) {
    return;
  }

  showDialog(
    context: dialogContext,
    builder: (context) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      title: Text(
        context.settingsText('הגדרות תצוגת הספרים'),
        style: const TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: 650,
        height: MediaQuery.of(context).size.height * 0.7,
        child: const ReadingSettingsPanel(),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.settingsText('סגור')),
        ),
      ],
    ),
  );
}
