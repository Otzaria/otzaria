import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/library_browser.dart';

void main() {
  test('preview pane widths stay valid below preferred minimum width', () {
    final widths = calculateLibraryPreviewPaneWidths(
      availableWidth: 200,
      viewMode: 'grid',
    );

    expect(widths.minPaneWidth, 200);
    expect(widths.maxPaneWidth, 200);
    expect(widths.paneWidth, 200);
  });

  test('preview pane widths keep min and max in legal order', () {
    for (final availableWidth in [0.0, 1.0, 279.0, 280.0, 326.0, 400.0]) {
      final widths = calculateLibraryPreviewPaneWidths(
        availableWidth: availableWidth,
        viewMode: 'grid',
        paneWidthOverride: 600,
      );

      expect(widths.maxPaneWidth, greaterThanOrEqualTo(widths.minPaneWidth));
      expect(
        widths.paneWidth,
        inInclusiveRange(
          widths.minPaneWidth,
          widths.maxPaneWidth,
        ),
      );
    }
  });
}
