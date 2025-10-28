import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:pdf_render/pdf_render.dart' as pdf_render;

class ThumbnailsView extends StatefulWidget {
  const ThumbnailsView({
    required this.document,
    required this.controller,
    required this.filePath,
    super.key,
  });

  final PdfDocument? document;
  final PdfViewerController? controller;
  final String filePath;

  @override
  State<ThumbnailsView> createState() => _ThumbnailsViewState();
}

class _ThumbnailsViewState extends State<ThumbnailsView> {
  late Future<List<Uint8List>> _thumbs;
  int? _currentPage;

  @override
  void initState() {
    super.initState();
    _thumbs = _buildThumbnails(widget.filePath);
    _currentPage = widget.controller?.pageNumber ?? 1;
    widget.controller?.addListener(_onPageChanged);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onPageChanged);
    super.dispose();
  }

  void _onPageChanged() {
    if (mounted) {
      setState(() {
        _currentPage = widget.controller?.pageNumber ?? 1;
      });
    }
  }

  Future<List<Uint8List>> _buildThumbnails(String path) async {
    try {
      final doc = await pdf_render.PdfDocument.openFile(path);
      final count = doc.pageCount;
      final List<Uint8List> result = [];
      const thumbMaxWidth = 140.0;

      for (var i = 1; i <= count; i++) {
        final page = await doc.getPage(i);
        final pageImage = await page.render(width: thumbMaxWidth.toInt());
        final uiImage = await pageImage.createImageIfNotAvailable();
        final byteData =
            await uiImage.toByteData(format: ui.ImageByteFormat.png);
        result.add(byteData!.buffer.asUint8List());
      }
      await doc.dispose();
      return result;
    } catch (e) {
      debugPrint('Error building thumbnails: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Uint8List>>(
      future: _thumbs,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'שגיאה בטעינת תצוגת דפים',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'תכונה זו אינה נתמכת במערכת ההפעלה הנוכחית',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'השתמש בתוכן העניינים לניווט',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final thumbs = snap.data!;
        if (thumbs.isEmpty) {
          return Center(
            child: Text(
              'אין דפים להצגה',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: thumbs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, idx) {
            final pageNumber = idx + 1;
            final isCurrentPage = pageNumber == _currentPage;

            return InkWell(
              onTap: () => widget.controller?.jumpToPage(pageNumber),
              child: Container(
                decoration: BoxDecoration(
                  color: isCurrentPage
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: isCurrentPage
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                    width: isCurrentPage ? 3 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    // Thumbnail image
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(7),
                      ),
                      child: Image.memory(
                        thumbs[idx],
                        width: 100,
                        height: 140,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Page info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'עמוד $pageNumber',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: isCurrentPage
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurface,
                                  fontWeight: isCurrentPage
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                          ),
                          if (isCurrentPage)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'עמוד נוכחי',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isCurrentPage)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Icon(
                          Icons.arrow_back,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
