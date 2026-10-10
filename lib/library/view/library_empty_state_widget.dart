import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/layout/centered_scrollable_state.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// ווידג'ט המוצג כאשר אין תוצאות בספרייה.
/// מציג הודעה ראשית ופעולות עזר לניווט וחיפוש.
///
/// כאשר [onOpenLink] מסופק, מוצג מצב קישור ישיר עם לחצן פתיחת קישור.
class LibraryEmptyStateWidget extends StatelessWidget {
  const LibraryEmptyStateWidget({
    super.key,
    required this.message,
    required this.onBack,
    required this.onHome,
    required this.onOpenSearch,
    this.onOpenLink,
    this.onSearchWholeLibrary,
    this.showSearchElsewhereHint = false,
  });

  final String message;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onOpenSearch;

  /// כאשר מוגדר, מוצג מצב "קישור ישיר" עם לחצן פתיחת קישור.
  final VoidCallback? onOpenLink;

  /// מריץ את אותו טקסט חיפוש מחדש בשורש הספרייה.
  /// מוצג כלחצן רק יחד עם [showSearchElsewhereHint].
  final VoidCallback? onSearchWholeLibrary;

  /// האם להציג את הרמז "ניתן לנסות לחפש בתיקייה אחרת".
  /// מוצג רק כאשר בוצע חיפוש ללא תוצאות בתוך תת-תיקייה.
  final bool showSearchElsewhereHint;

  bool get _isDeepLink => onOpenLink != null;

  Widget _buildNavButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ActionButton.neutral(
          onPressed: onBack,
          icon: FluentIcons.arrow_up_24_regular,
          text: 'חזור',
        ),
        const SizedBox(width: 8),
        ActionButton.neutral(
          onPressed: onHome,
          icon: FluentIcons.home_24_regular,
          text: 'בית',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CenteredScrollableState(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isDeepLink
                ? OtzariaIcons.link_24_regular
                : FluentIcons.document_search_24_regular,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (_isDeepLink) ...[
            const SizedBox(height: 8),
            Text(
              'נראה שהכנסתם קישור ישיר',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ActionButton.recommended(
              onPressed: onOpenLink,
              icon: OtzariaIcons.link_24_regular,
              text: 'פתיחת קישור',
            ),
            const SizedBox(height: 12),
            _buildNavButtons(),
          ] else ...[
            if (showSearchElsewhereHint) ...[
              const SizedBox(height: 12),
              Text(
                'ניתן לנסות לחפש בתיקייה אחרת',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            _buildNavButtons(),
            if (showSearchElsewhereHint && onSearchWholeLibrary != null) ...[
              const SizedBox(height: 12),
              ActionButton.recommended(
                onPressed: onSearchWholeLibrary,
                icon: FluentIcons.library_24_regular,
                text: 'חפש בתיקייה הראשית',
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'ניתן לחפש גם טקסט ספציפי במאגר',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            ActionButton.recommended(
              onPressed: onOpenSearch,
              icon: FluentIcons.search_24_regular,
              text: 'פתח חיפוש טקסט',
            ),
          ],
        ],
      ),
    );
  }
}
