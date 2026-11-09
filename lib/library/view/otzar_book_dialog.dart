import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import '../../models/books.dart';
import '../../utils/navigation/otzar_utils.dart';
import '../../core/ui_snack.dart';
import '../bloc/library_bloc.dart';
import '../bloc/library_event.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/data_providers/external_catalog_mapper.dart';
import 'package:otzaria/library/services/hebrew_books_download_service.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

class OtzarBookDialog extends StatefulWidget {
  final ExternalLibraryBook book;

  const OtzarBookDialog({super.key, required this.book});

  @override
  State<OtzarBookDialog> createState() => _OtzarBookDialogState();
}

class _OtzarBookDialogState extends State<OtzarBookDialog> {
  /// (פתיחה מקומית אפשרית, הספר קיים מקומית) — נבדק פעם אחת, לא בכל בנייה.
  late final Future<(bool, bool)> _localAvailability;

  ExternalLibraryBook get book => widget.book;

  bool get _isHebrewBook =>
      ExternalCatalogMapper.catalogFromLinkOrId(
        link: book.link,
        externalLibraryId: book.externalLibraryId,
      ) ==
      ExternalCatalogType.hebrew;

  @override
  void initState() {
    super.initState();
    _localAvailability = _isHebrewBook
        ? Future.value((false, false))
        : Future.wait([
            OtzarUtils.canLaunchLocally(),
            OtzarUtils.checkBookExistence(book.id!),
          ]).then((results) => (results[0], results[1]));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, bool)>(
      future: _localAvailability,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final (canLaunchLocally, bookExists) = snapshot.data ?? (false, false);
        return AppDialogFrame(
          title: book.title,
          icon: OtzariaIcons.book_24_regular,
          // שלוש פעולות לא נכנסות בשורה אחת ברוחב small.
          size: AppDialogSize.medium,
          scrollable: !loading,
          actions: [
            ActionButton.neutral(
              onPressed: () => Navigator.of(context).pop(),
              text: 'סגור',
            ),
            if (!loading)
              ..._buildActions(context, canLaunchLocally, bookExists),
          ],
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(AppTokens.spaceXL),
                  child: Center(heightFactor: 1, child: LoadingIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildInfoRow(
                      context,
                      FluentIcons.document_text_24_regular,
                      'תיאור',
                      book.heShortDesc ?? 'לא קיים',
                    ),
                    _buildInfoRow(
                      context,
                      OtzariaIcons.person_24_regular,
                      'מחבר',
                      book.author ?? 'לא ידוע',
                    ),
                    _buildInfoRow(
                      context,
                      FluentIcons.location_24_regular,
                      'מקום הדפסה',
                      book.pubPlace ?? 'לא ידוע',
                    ),
                    _buildInfoRow(
                      context,
                      OtzariaIcons.calendar_24_regular,
                      'שנת הדפסה',
                      book.pubDate ?? 'לא ידוע',
                    ),
                    _buildInfoRow(
                      context,
                      FluentIcons.apps_24_regular,
                      'נושאים',
                      book.topics,
                    ),
                  ],
                ),
        );
      },
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
            size: AppTokens.iconMD,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              textScaler: MediaQuery.textScalerOf(context),
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

  /// הפעולות אחרי "סגור": הורדה, פתיחה באתר, ופתיחה מקומית (הראשית) בסוף.
  List<Widget> _buildActions(
    BuildContext context,
    bool canLaunchLocally,
    bool bookExists,
  ) {
    return <Widget>[
      if (_isHebrewBook && book.id != null)
        _HebrewBookDownloadButton(bookId: book.id!),
      ActionButton.neutral(
        icon: FluentIcons.open_24_regular,
        text: 'פתח באתר',
        onPressed: () async {
          Navigator.of(context).pop();
          if (await OtzarUtils.launchOtzarWeb(book.link)) {
            // Success
          } else {
            UiSnack.showError(LibraryMessages.cannotOpenLinkInBrowser);
          }
        },
      ),
      if (canLaunchLocally && bookExists)
        ActionButton.recommended(
          icon: FluentIcons.desktop_24_regular,
          text: 'פתח מקומית',
          onPressed: () {
            Navigator.of(context).pop();
            OtzarUtils.launchOtzarLocal(book.id!);
          },
        ),
    ];
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
    // נלכד מראש: ההורדה ממשיכה גם אם הדיאלוג נסגר באמצע.
    final libraryBloc = context.read<LibraryBloc>();

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
      if (savedPath != null && !libraryBloc.isClosed) {
        libraryBloc.add(const ExternalBooksChanged());
      }
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
