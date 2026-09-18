import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import '../../models/books.dart';
import '../../utils/navigation/otzar_utils.dart';
import '../../core/ui_snack.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/data_providers/external_catalog_mapper.dart';
import 'package:otzaria/external_catalog/providers/external_provider_capabilities.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/library/services/hebrew_books_download_service.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// דיאלוג פרטי ספר של ספרייה חיצונית.
///
/// הפעולות נקבעות לפי **יכולות הספק**, לא לפי שם המחלקה של הספר ולא
/// לפי ניחוש מתוך הקישור. ספק בלי `webOpen` פשוט אינו מקבל "פתח באתר",
/// וספק חדש אינו דורש ענף נוסף כאן.
class ExternalBookDialog extends StatelessWidget {
  final ExternalLibraryBook book;

  /// נקרא כשהמשתמש בוחר "פתח בתוכנה" אצל ספק עם `localOpen` שאינו אוצר
  /// החכמה. מוזרק כדי שהדיאלוג לא יכיר את שכבת הגשר.
  final Future<String?> Function(ExternalLibraryBook book)? onOpenLocally;

  const ExternalBookDialog({
    super.key,
    required this.book,
    this.onOpenLocally,
  });

  ExternalProviderDescriptor? get _provider => ExternalCatalogMapper.providerOf(
    link: book.link,
    externalLibraryId: book.externalLibraryId,
  );

  ExternalProviderCapabilities get _capabilities =>
      _provider?.capabilities ?? const ExternalProviderCapabilities();

  bool get _isOtzar => _provider?.kind == ExternalProviderKind.otzar;

  bool get _isHebrewBook => _provider?.kind == ExternalProviderKind.hebrewBooks;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: FutureBuilder<(bool, bool)>(
          // בדיקת הזמינות המקומית שייכת לאוצר החכמה בלבד — היא בודקת
          // קובץ ספר, ולספקים אחרים אין מודל כזה.
          future: _isOtzar && book.id != null
              ? Future.wait([
                  OtzarUtils.canLaunchLocally(),
                  OtzarUtils.checkBookExistence(book.id!),
                ]).then((results) => (results[0], results[1]))
              : Future.value((false, false)),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final (canLaunchLocally, bookExists) =
                snapshot.data ?? (false, false);

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).dialogTheme.backgroundColor ??
                    Theme.of(context).colorScheme.surface,
                borderRadius: AppTokens.borderRadiusAll,
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withValues(alpha: 0.26),
                    blurRadius: 10.0,
                    offset: Offset(0.0, 10.0),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      book.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (_provider case final provider?)
                      _buildInfoRow(
                        context,
                        FluentIcons.library_24_regular,
                        'מקור',
                        provider.displayName,
                      ),
                    if (book.categoryPath?.isNotEmpty ?? false)
                      _buildInfoRow(
                        context,
                        FluentIcons.folder_24_regular,
                        'הקשר',
                        book.categoryPath!.replaceAll('/', ' › '),
                      ),
                    // שדה שאין לו מקור אצל הספק אינו מוצג כ"לא ידוע" —
                    // זו אמירה שגויה על הספר ולא על המידע שברשותנו.
                    if (book.heShortDesc != null)
                      _buildInfoRow(
                        context,
                        FluentIcons.document_text_24_regular,
                        'תיאור',
                        book.heShortDesc!,
                      ),
                    if (book.author != null)
                      _buildInfoRow(
                        context,
                        OtzariaIcons.person_24_regular,
                        'מחבר',
                        book.author!,
                      ),
                    if (book.pubPlace != null)
                      _buildInfoRow(
                        context,
                        FluentIcons.location_24_regular,
                        'מקום הדפסה',
                        book.pubPlace!,
                      ),
                    if (book.pubDate != null)
                      _buildInfoRow(
                        context,
                        OtzariaIcons.calendar_24_regular,
                        'שנת הדפסה',
                        book.pubDate!,
                      ),
                    if (book.topics.isNotEmpty)
                      _buildInfoRow(
                        context,
                        FluentIcons.apps_24_regular,
                        'נושאים',
                        book.topics,
                      ),
                    const SizedBox(height: 24),
                    _buildButtons(context, canLaunchLocally, bookExists),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RtlIcon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(
    BuildContext context,
    bool canLaunchLocally,
    bool bookExists,
  ) {
    final capabilities = _capabilities;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        if (_isOtzar && canLaunchLocally && bookExists)
          ElevatedButton.icon(
            icon: const Icon(FluentIcons.desktop_24_regular),
            label: const Text('פתח מקומית'),
            onPressed: () {
              Navigator.of(context).pop();
              OtzarUtils.launchOtzarLocal(book.id!);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        if (!_isOtzar && capabilities.localOpen && onOpenLocally != null)
          _OpenInSoftwareButton(book: book, onOpen: onOpenLocally!),
        if (capabilities.webOpen)
          if (book.link case final url?)
            ElevatedButton.icon(
              icon: const Icon(FluentIcons.open_24_regular),
              label: const Text('פתח באתר'),
              onPressed: () async {
                Navigator.of(context).pop();
                if (await OtzarUtils.launchOtzarWeb(url)) {
                  // Success
                } else {
                  UiSnack.showError(LibraryMessages.cannotOpenLinkInBrowser);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
        if (capabilities.pdfDownload && _isHebrewBook && book.id != null)
          _HebrewBookDownloadButton(bookId: book.id!),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.secondary,
          ),
          child: const Text('סגור'),
        ),
      ],
    );
  }
}

/// "פתח בתוכנה" לספק שפתיחתו מקומית ואיטית (פרויקט השו"ת: 3–25 שניות).
///
/// הכפתור ננעל בזמן הפתיחה ומציג מצב טעינה. אין כאן "ביטול": הוא ייווסף
/// רק כשהוא באמת יעצור את הפעולה, ולא כדי להסתיר את מחוון הטעינה.
class _OpenInSoftwareButton extends StatefulWidget {
  final ExternalLibraryBook book;
  final Future<String?> Function(ExternalLibraryBook book) onOpen;

  const _OpenInSoftwareButton({required this.book, required this.onOpen});

  @override
  State<_OpenInSoftwareButton> createState() => _OpenInSoftwareButtonState();
}

class _OpenInSoftwareButtonState extends State<_OpenInSoftwareButton> {
  bool _isOpening = false;

  @override
  Widget build(BuildContext context) {
    return ActionButton.recommended(
      text: _isOpening ? 'פותח...' : 'פתח בתוכנה',
      icon: FluentIcons.desktop_24_regular,
      isLoading: _isOpening,
      onPressed: _isOpening ? null : _open,
    );
  }

  Future<void> _open() async {
    setState(() => _isOpening = true);
    String? error;
    try {
      error = await widget.onOpen(widget.book);
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      UiSnack.showError(error);
    }
  }
}

class _HebrewBookDownloadButton extends StatefulWidget {
  final int bookId;

  const _HebrewBookDownloadButton({required this.bookId});

  @override
  State<_HebrewBookDownloadButton> createState() =>
      _HebrewBookDownloadButtonState();
}

class _HebrewBookDownloadButtonState extends State<_HebrewBookDownloadButton> {
  bool _isDownloading = false;
  int? _percent;

  @override
  Widget build(BuildContext context) {
    final label = _isDownloading
        ? (_percent == null ? 'מוריד...' : 'מוריד... $_percent%')
        : 'הורדת הקובץ';
    return ActionButton.neutral(
      text: label,
      icon: FluentIcons.arrow_download_24_regular,
      isLoading: _isDownloading,
      onPressed: _isDownloading ? null : _download,
    );
  }

  Future<void> _download() async {
    final hasFolder = HebrewBooksDownloadService.configuredFolder() != null;
    if (!hasFolder && !await verifySaferModePassword(context)) return;
    if (!mounted) return;

    setState(() {
      _isDownloading = true;
      _percent = null;
    });
    final service = HebrewBooksDownloadService();
    try {
      final result = await service.download(
        widget.bookId,
        onProgress: (received, total) {
          if (!mounted || total == null || total <= 0) return;
          final percent = (received * 100 ~/ total).clamp(0, 100);
          if (percent == _percent) return;
          setState(() => _percent = percent);
        },
      );

      var savedPath = await HebrewBooksDownloadService.saveToConfiguredFolder(
        widget.bookId,
        result.bytes,
      );
      if (!mounted) return;
      savedPath ??= await saveFileWithExtension(
        fileName: result.fileName,
        extension: 'pdf',
        bytes: result.bytes,
        context: context,
      );

      if (savedPath == null) {
        UiSnack.show(LibraryMessages.hebrewBookDownloadCanceled);
        return;
      }
      UiSnack.show(LibraryMessages.hebrewBookDownloaded(savedPath));
    } catch (e) {
      UiSnack.showError(LibraryMessages.hebrewBookDownloadError(e));
    } finally {
      service.dispose();
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _percent = null;
        });
      }
    }
  }
}
