import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

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
  });

  final String message;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onOpenSearch;

  /// כאשר מוגדר, מוצג מצב "קישור ישיר" עם לחצן פתיחת קישור.
  final VoidCallback? onOpenLink;

  bool get _isDeepLink => onOpenLink != null;

  Widget _buildNavButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: onBack,
          icon: const Icon(FluentIcons.arrow_up_24_regular),
          label: const Text('חזור'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onHome,
          icon: const Icon(FluentIcons.home_24_regular),
          label: const Text('בית'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            FilledButton.icon(
              onPressed: onOpenLink,
              icon: const Icon(FluentIcons.link_24_regular),
              label: const Text('פתיחת קישור'),
            ),
            const SizedBox(height: 12),
            _buildNavButtons(),
          ] else ...[
            const SizedBox(height: 16),
            _buildNavButtons(),
            const SizedBox(height: 12),
            Text(
              'ניתן לחפש גם טקסט ספציפי במאגר',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onOpenSearch,
              icon: const Icon(FluentIcons.search_24_regular),
              label: const Text('פתח חיפוש טקסט'),
            ),
          ],
        ],
      ),
    );
  }
}
