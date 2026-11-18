import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_viewport_geometry.dart';

void main() {
  group('PDF spread viewport geometry', () {
    test('transforms the spread rectangle without clipping', () {
      final matrix = Matrix4.translationValues(10, 20, 0);
      expect(
        pdfSpreadTurnViewportRect(
          matrix,
          const Rect.fromLTWH(0, 0, 100, 200),
        ),
        const Rect.fromLTWH(10, 20, 100, 200),
      );
    });

    test('clips visible spread to viewport and returns null when outside', () {
      final matrix = Matrix4.translationValues(80, 20, 0);
      expect(
        pdfSpreadVisibleViewportRect(
          matrix,
          const Rect.fromLTWH(0, 0, 100, 100),
          const Size(120, 80),
        ),
        const Rect.fromLTWH(80, 20, 40, 60),
      );
      final outside = Matrix4.translationValues(200, 0, 0);
      expect(
        pdfSpreadVisibleViewportRect(
          outside,
          const Rect.fromLTWH(0, 0, 100, 100),
          const Size(120, 80),
        ),
        isNull,
      );
    });

    test(
      'top anchor preserves horizontal center and adjusts vertical center',
      () {
        expect(
          pdfTopAnchoredCenter(
            anchorDocTop: 500,
            currentCenter: const Offset(120, 200),
            viewSize: const Size(800, 600),
            zoom: 2,
          ),
          const Offset(120, 650),
        );
      },
    );
  });

  group('PdfPaneToggleAnchor', () {
    test('is consumed once for the matching width change', () {
      final anchor = PdfPaneToggleAnchor()
        ..prepare(
          changesReaderWidth: true,
          docTop: 420,
          viewSize: const Size(900, 700),
        );

      expect(
        anchor.consume(
          oldViewSize: const Size(900, 700),
          newViewSize: const Size(700, 700),
          isBookView: false,
        ),
        420,
      );
      expect(
        anchor.consume(
          oldViewSize: const Size(900, 700),
          newViewSize: const Size(700, 700),
          isBookView: false,
        ),
        isNull,
      );
    });

    test('rejects overlays, book view, and non-width changes', () {
      final anchor = PdfPaneToggleAnchor()
        ..prepare(
          changesReaderWidth: true,
          docTop: 420,
          viewSize: const Size(900, 700),
        );
      expect(
        anchor.consume(
          oldViewSize: const Size(900, 700),
          newViewSize: const Size(900, 800),
          isBookView: false,
        ),
        isNull,
      );

      anchor.prepare(
        changesReaderWidth: true,
        docTop: 420,
        viewSize: const Size(900, 700),
      );
      expect(
        anchor.consume(
          oldViewSize: const Size(900, 700),
          newViewSize: const Size(700, 700),
          isBookView: true,
        ),
        isNull,
      );

      anchor.prepare(
        changesReaderWidth: false,
        docTop: 420,
        viewSize: const Size(900, 700),
      );
      expect(
        anchor.consume(
          oldViewSize: const Size(900, 700),
          newViewSize: const Size(700, 700),
          isBookView: false,
        ),
        isNull,
      );
    });
  });

  group('PDF fit zooms', () {
    test('width zoom and page zoom use the limiting dimension', () {
      expect(
        pdfFitZooms(
          shown: const Rect.fromLTWH(0, 0, 400, 800),
          viewSize: const Size(600, 600),
          margin: 20,
        ),
        (width: 1.4, page: 0.7),
      );
    });

    test('fit toggle recognizes a width fit within one percent', () {
      expect(pdfNextFitIsPage(zoom: 1.0, widthZoom: 1.0), isTrue);
      expect(pdfNextFitIsPage(zoom: 1.005, widthZoom: 1.0), isTrue);
      expect(pdfNextFitIsPage(zoom: 1.02, widthZoom: 1.0), isFalse);
    });
  });
}
