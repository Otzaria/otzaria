// issue #1392: הסתרת טור בצורת הדף נשמרת יחד עם בחירת המפרשים, ולכן חלה
// רק על אותו תחום (קטגוריה / ספר / שולחן עבודה) ולא על כל הספרים.

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const chumashCategories = 'אוצריא, תנ"ך, תורה, בראשית';
  const gemaraCategories = 'אוצריא, תלמוד בבלי, סדר זרעים, ברכות';
  const config = {
    'left': 'רש"י',
    'right': 'אונקלוס',
    'bottom': null,
    'bottomRight': null,
  };
  const rightHidden = {
    'left': true,
    'right': false,
    'bottom': true,
    'bottomRight': true,
  };

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('טור שהוסתר בקטגוריה אחת מוצג בקטגוריה אחרת', () async {
    await PageShapeSettingsManager.saveConfiguration(
      'בראשית',
      config,
      saveToCategory: 'תורה',
      columnVisibility: rightHidden,
    );
    await PageShapeSettingsManager.saveConfiguration(
      'ברכות',
      config,
      saveToCategory: 'סדר זרעים',
      columnVisibility: const {'right': true},
    );

    expect(
      PageShapeSettingsManager.getColumnVisibility(
        'שמות',
        heCategories: 'אוצריא, תנ"ך, תורה, שמות',
      )['right'],
      isFalse,
    );
    expect(
      PageShapeSettingsManager.getColumnVisibility(
        'ברכות',
        heCategories: gemaraCategories,
      )['right'],
      isTrue,
    );
  });

  test('ההסתרה נקראת מאותה הגדרה שממנה נטענו המפרשים', () async {
    await PageShapeSettingsManager.saveConfiguration(
      'בראשית',
      config,
      saveToCategory: 'תורה',
      columnVisibility: rightHidden,
    );
    await PageShapeSettingsManager.saveConfiguration(
      'בראשית',
      config,
      columnVisibility: const {'right': true},
    );

    expect(
      PageShapeSettingsManager.getColumnVisibility(
        'בראשית',
        heCategories: chumashCategories,
      )['right'],
      isTrue,
    );

    await PageShapeSettingsManager.resetBookCommentatorConfig('בראשית');
    expect(
      PageShapeSettingsManager.getColumnVisibility(
        'בראשית',
        heCategories: chumashCategories,
      )['right'],
      isFalse,
    );
  });

  test('שמירת מפרשים בלי טורים אינה מוחקת את ההסתרה', () async {
    await PageShapeSettingsManager.saveConfiguration(
      'בראשית',
      config,
      columnVisibility: rightHidden,
    );
    await PageShapeSettingsManager.saveConfiguration('בראשית', config);

    expect(
      PageShapeSettingsManager.getColumnVisibility('בראשית')['right'],
      isFalse,
    );
  });

  test('בלי הסתרה שמורה לצד המפרשים - נופל להגדרה הגלובלית הישנה', () async {
    await Settings.setValue<bool>('page_shape_global_visibility_right', false);
    await PageShapeSettingsManager.saveConfiguration(
      'ברכות',
      config,
      saveToCategory: 'סדר זרעים',
    );

    expect(
      PageShapeSettingsManager.getColumnVisibility(
        'ברכות',
        heCategories: gemaraCategories,
      )['right'],
      isFalse,
    );
  });

  test('איפוס ספר מוחק גם את הטורים המוסתרים שלו', () async {
    await PageShapeSettingsManager.saveConfiguration(
      'בראשית',
      config,
      columnVisibility: rightHidden,
    );
    expect(
      Settings.getValue<String>('page_shape_book_בראשית_hidden_columns'),
      isNotNull,
    );
    await PageShapeSettingsManager.resetBookCommentatorConfig('בראשית');

    expect(
      Settings.getValue<String>('page_shape_book_בראשית_hidden_columns'),
      isNull,
    );
  });
}
