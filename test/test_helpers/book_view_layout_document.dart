import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

class CountingLayoutDocument extends Fake implements PdfDocument {
  CountingLayoutDocument(List<Size> sizes, {bool syncEvents = true})
    : _events = StreamController<PdfDocumentEvent>.broadcast(sync: syncEvents) {
    _pages = List.unmodifiable([
      for (var i = 0; i < sizes.length; i++)
        CountingLayoutPage(this, i + 1, sizes[i]),
    ]);
  }

  final StreamController<PdfDocumentEvent> _events;
  late List<PdfPage> _pages;
  int dimensionReads = 0;

  bool get hasListener => _events.hasListener;

  @override
  List<PdfPage> get pages => _pages;

  @override
  Stream<PdfDocumentEvent> get events => _events.stream;

  void emit(PdfDocumentEvent event) => _events.add(event);

  void replacePages(
    List<PdfPage> pages, {
    Map<int, PdfPageStatusChange>? changes,
  }) {
    _pages = List.unmodifiable(pages);
    emit(
      PdfDocumentPageStatusChangedEvent(
        this,
        changes:
            changes ??
            {
              for (final page in pages)
                page.pageNumber: PdfPageStatusChange.modified(page: page),
            },
      ),
    );
  }

  @override
  Future<void> dispose() => _events.close();
}

class CountingLayoutPage extends Fake implements PdfPage {
  CountingLayoutPage(this.document, this.pageNumber, this.size);

  @override
  final CountingLayoutDocument document;
  @override
  final int pageNumber;
  Size size;

  @override
  double get width {
    document.dimensionReads++;
    return size.width;
  }

  @override
  double get height {
    document.dimensionReads++;
    return size.height;
  }

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  bool get isLoaded => true;
}
