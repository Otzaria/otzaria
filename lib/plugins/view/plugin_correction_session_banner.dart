import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/app_info_banner.dart';

/// הודעה קבועה מעל הקורא כל עוד יש בלשונית סשן תיקון של תוסף.
class PluginCorrectionSessionBanner extends StatelessWidget {
  static String modeText(String ownerName) =>
      'מצב תיקון של התוסף ‹$ownerName› — הנוסח המוצג כולל הצעות מקומיות; '
      'הספר אינו משתנה';
  static const savedText = 'הטיוטה נשמרה';
  static const savingText = 'שומר טיוטה…';
  static const failedText = 'שמירת הטיוטה נכשלה';
  static const retryText = 'נסה שוב';
  static const pageShapeText = 'התיקונים מוסתרים בצורת הדף';
  static const endText = 'סיום עריכה';

  final String tabId;
  final bool pageShape;
  final PluginCorrectionSessionService? service;

  const PluginCorrectionSessionBanner({
    super.key,
    required this.tabId,
    this.pageShape = false,
    this.service,
  });

  @override
  Widget build(BuildContext context) {
    final sessions = service ?? PluginCorrectionSessionService.instance;
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final ownerName = sessions.ownerNameForTab(tabId);
        final status = sessions.draftStatusForTab(tabId);
        if (ownerName == null || status == null) return const SizedBox.shrink();
        final statusText = switch (status) {
          PluginCorrectionDraftStatus.saved => savedText,
          PluginCorrectionDraftStatus.saving => savingText,
          PluginCorrectionDraftStatus.failed => failedText,
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceSM,
            AppTokens.spaceSM,
            AppTokens.spaceSM,
            0,
          ),
          child: AppInfoBanner(
            tone: AppInfoBannerTone.tertiary,
            icon: FluentIcons.edit_24_regular,
            title: modeText(ownerName),
            message: statusText,
            extraLines: [if (pageShape) pageShapeText],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status == PluginCorrectionDraftStatus.failed)
                  ActionButton.ghost(
                    text: retryText,
                    onPressed: sessions.retryDraftWrites,
                  ),
                const SizedBox(width: AppTokens.spaceSM),
                ActionButton.neutral(
                  text: endText,
                  onPressed: () => sessions.endByUser(tabId),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
