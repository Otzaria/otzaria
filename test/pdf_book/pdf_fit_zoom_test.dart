import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  test('עמוד גבוה — הרוחב קובע את ההתאמה לרוחב, הגובה את העמוד השלם', () {
    final fits = pdfFitZooms(
      shown: const Rect.fromLTWH(0, 0, 600, 800),
      viewSize: const Size(1216, 816),
      margin: 8,
    );
    expect(fits.width, closeTo(2.0, 1e-9));
    expect(fits.page, closeTo(1.0, 1e-9));
  });

  test('עמוד שנכנס לרוחב לפני הגובה — שתי ההתאמות זהות', () {
    final fits = pdfFitZooms(
      shown: const Rect.fromLTWH(0, 0, 1000, 200),
      viewSize: const Size(1016, 816),
      margin: 8,
    );
    expect(fits.page, fits.width);
  });

  test('המתג עובר לעמוד שלם רק מהתאמה לרוחב', () {
    expect(pdfNextFitIsPage(zoom: 2.0, widthZoom: 2.0), isTrue);
    expect(pdfNextFitIsPage(zoom: 2.01, widthZoom: 2.0), isTrue);
    expect(pdfNextFitIsPage(zoom: 1.0, widthZoom: 2.0), isFalse);
    expect(pdfNextFitIsPage(zoom: 3.0, widthZoom: 2.0), isFalse);
  });

  group('כפתור ההתאמה מציג את ההתאמה הבאה (#2988)', () {
    setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

    test('סמל וכיתוב לפי הפעולה, והקיצור ב-tooltip', () async {
      final shortcut = ShortcutHelper.formatShortcutForDisplay('ctrl+shift+0');
      final toPage = pdfFitButtonVisual(nextIsPage: true);
      expect(toPage.icon, FluentIcons.arrow_autofit_height_24_regular);
      expect(toPage.tooltip, 'התאם לעמוד שלם ($shortcut)');
      final toWidth = pdfFitButtonVisual(nextIsPage: false);
      expect(toWidth.icon, FluentIcons.arrow_autofit_width_24_regular);
      expect(toWidth.tooltip, 'התאם לרוחב ($shortcut)');
    });

    test('בלי קיצור — הכיתוב לבד', () async {
      await Settings.setValue<String>(ShortcutValidator.fitPdfViewKey, '');
      addTearDown(
        () => Settings.setValue<String>(
          ShortcutValidator.fitPdfViewKey,
          'ctrl+shift+0',
        ),
      );
      expect(pdfFitButtonVisual(nextIsPage: true).tooltip, 'התאם לעמוד שלם');
    });
  });
}
