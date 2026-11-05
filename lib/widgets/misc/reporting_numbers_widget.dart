import 'dart:io';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/text/app_section_label.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/layout/app_card.dart';

/// Widget that displays reporting numbers with copy functionality
class ReportingNumbersWidget extends StatelessWidget {
  final String libraryVersion;
  final int? bookId;
  final int lineNumber;
  final int? errorId;
  final bool showPhoneNumber;

  const ReportingNumbersWidget({
    super.key,
    required this.libraryVersion,
    required this.bookId,
    required this.lineNumber,
    this.errorId,
    this.showPhoneNumber = true,
  });

  static const String _phoneNumber = '(+972) 077-4636-198';

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.all(4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionLabel('נתוני הדיווח:'),
            const SizedBox(height: 8),

            // Wrap מאפשר לנתונים להיות באותה שורה ולעבור לשורה הבאה אם אין מקום
            Wrap(
              spacing: 16, // מרווח אופקי בין הפריטים
              runSpacing: 8, // מרווח אנכי בין השורות
              children: [
                _buildCompactNumberItem(
                  context,
                  'מספר גירסה',
                  libraryVersion,
                ),
                _buildCompactNumberItem(
                  context,
                  'מספר ספר',
                  bookId?.toString() ?? 'לא זמין',
                  enabled: bookId != null,
                ),
                _buildCompactNumberItem(
                  context,
                  'מספר שורה',
                  lineNumber.toString(),
                ),
                _buildCompactNumberItem(
                  context,
                  'מספר שגיאה',
                  errorId?.toString() ?? 'לא נבחר',
                  enabled: errorId != null,
                ),
              ],
            ),

            if (showPhoneNumber) ...[
              const Divider(height: 20),
              _buildPhoneSection(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactNumberItem(
    BuildContext context,
    String label,
    String value, {
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: $value',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: enabled ? null : Theme.of(context).disabledColor,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: enabled ? () => _copyToClipboard(context, value) : null,
            borderRadius: AppTokens.borderRadiusAll,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                FluentIcons.copy_24_regular,
                size: 16,
                color: enabled
                    ? Theme.of(context).iconTheme.color
                    : Theme.of(context).disabledColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneSection(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            const AppSectionLabel('קו אוצריא:'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: AppTokens.borderRadiusAll,
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: isMobile
                      ? InkWell(
                          onTap: () => _makePhoneCall(context),
                          child: Text(
                            _phoneNumber,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.bold,
                                ),
                            textDirection: TextDirection.ltr,
                          ),
                        )
                      : AppSelectionArea(
                          child: Text(
                            _phoneNumber,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                AppIconButton(
                  onPressed: () => _copyToClipboard(context, _phoneNumber),
                  icon: const Icon(FluentIcons.copy_24_regular),
                  size: AppIconButtonSize.small,
                  tooltip: 'העתק מספר טלפון',
                ),
                if (isMobile) ...[
                  const SizedBox(width: 4),
                  AppIconButton(
                    onPressed: () => _makePhoneCall(context),
                    icon: const Icon(FluentIcons.phone_24_regular),
                    size: AppIconButtonSize.small,
                    tooltip: 'התקשר',
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),

        // טקסט המשנה נשאר כמו שהיה
        Text(
          'לפירוט נוסף, השאר הקלטה ברורה!',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _copyToClipboard(BuildContext context, String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        UiSnack.show(CommonMessages.copiedToClipboard(text));
      }
    } catch (e) {
      if (context.mounted) {
        UiSnack.showError(CommonMessages.clipboardCopyError);
      }
    }
  }

  Future<void> _makePhoneCall(BuildContext context) async {
    try {
      final phoneUri = Uri(scheme: 'tel', path: _phoneNumber);
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (context.mounted) {
          UiSnack.showError(CommonMessages.cannotOpenPhoneApp);
        }
      }
    } catch (e) {
      if (context.mounted) {
        UiSnack.showError(CommonMessages.phoneAppOpenError);
      }
    }
  }
}
