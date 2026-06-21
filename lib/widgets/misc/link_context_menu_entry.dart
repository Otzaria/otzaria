import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

/// בונה פריט תפריט הקשר עבור קישור בודד בתת-תפריט "קישורים".
///
/// מאחד מימוש שהיה משוכפל בתצוגה המשולבת, בצורת הדף וב-PDF: תווית עם
/// כתובת תצוגה מלאה (נטענת ברקע), פתיחת היעד בלחיצה, וחלונית תצוגה
/// מקדימה צפה עם תוכן הקישור ברפרוף ([AppContextMenuEntry.hoverPreviewBuilder]).
AppContextMenuEntry buildLinkContextMenuEntry({
  required Link link,
  required VoidCallback onTap,
}) {
  return AppContextMenuEntry(
    label: link.fallbackDisplayReference,
    labelWidget: FutureBuilder<String>(
      future: link.displayReference,
      builder: (context, snapshot) => Text(
        snapshot.data ?? link.fallbackDisplayReference,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    onTap: onTap,
    hoverPreviewBuilder: (context) => LinkHoverPreviewContent(link: link),
  );
}

/// תוכן חלונית התצוגה המקדימה של קישור — כותרת (כתובת היעד) ותוכן הקטע,
/// מעוצב לפי הגדרות תצוגת המפרשים (גופן, ניקוד, טעמים).
class LinkHoverPreviewContent extends StatelessWidget {
  final Link link;

  const LinkHoverPreviewContent({super.key, required this.link});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final colorScheme = Theme.of(context).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<String>(
              future: link.displayReference,
              builder: (context, snapshot) {
                var title = snapshot.data ?? link.fallbackDisplayReference;
                if (settingsState.replaceHolyNames) {
                  title = utils.replaceHolyNames(title);
                }
                return Text(
                  title,
                  style: TextStyle(
                    fontSize: settingsState.commentatorsFontSize - 2,
                    fontWeight: FontWeight.bold,
                    fontFamily: settingsState.commentatorsFontFamily,
                    color: colorScheme.primary,
                  ),
                );
              },
            ),
            const Divider(height: 16),
            FutureBuilder<String>(
              future: link.content,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'שגיאה בטעינת התוכן',
                    style: TextStyle(
                      color: colorScheme.error,
                      fontSize: settingsState.commentatorsFontSize - 2,
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final cleanContent = TextRendererService.stripHtml(
                  snapshot.data!,
                )
                    .replaceAll('&nbsp;', ' ')
                    .replaceAll(RegExp(r'[^\S\r\n]+'), ' ')
                    .trim();
                if (cleanContent.isEmpty) {
                  return Text(
                    'אין תוכן זמין',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: settingsState.commentatorsFontSize - 2,
                    ),
                  );
                }

                return FutureBuilder<bool>(
                  future: resolveRemoveNikudForBook(
                    title: utils.getTitleFromPath(link.path2),
                    defaultRemoveNikud: settingsState.defaultRemoveNikud,
                    removeNikudFromTanach: settingsState.removeNikudFromTanach,
                  ),
                  builder: (context, nikudSnapshot) {
                    return SmartTextWidget(
                      text: cleanContent,
                      settings: RenderSettings(
                        removeNikud: nikudSnapshot.data ?? false,
                        removeTeamim: !settingsState.showTeamim,
                        replaceHolyNames: settingsState.replaceHolyNames,
                        fontSize: settingsState.commentatorsFontSize,
                        fontFamily: settingsState.commentatorsFontFamily,
                        fontWeight: settingsState.commentatorsFontBold
                            ? FontWeight.bold
                            : null,
                        lineHeight: settingsState.lineHeight,
                        justifyText: true,
                      ),
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }
}
