// issue #2704: בחירת "תוספות" נתפסה כמפרש אחר ששמו מתחיל ב"תוספות".

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/commentator_name_matching.dart';
import 'package:otzaria/book_common/utils/default_commentators.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/services/category_commentators_service.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _bavliCategories = 'אוצריא, תלמוד, תלמוד בבלי';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('בבלי: "תוספות" אינו "תוספות הרא"ש" שקודם לו בסדר הא"ב', () {
    expect(
      findMatchingCommentator(
        'תוספות',
        const ['תוספות הרא"ש על מכות', 'תוספות על מכות'],
        commentedBookTitle: 'מכות',
      ),
      'תוספות על מכות',
    );
  });

  test('משנה: "תוספות" אינו "תוספות יום טוב"', () {
    expect(
      findMatchingCommentator(
        'תוספות',
        const ['תוספות יום טוב על משנה מכות'],
        commentedBookTitle: 'משנה מכות',
      ),
      isNull,
    );
  });

  test('מפרשים קבועים לקטגוריה נטענים כאותו מפרש בספר אחר', () async {
    await CategoryCommentatorsService.save(
      'תלמוד בבלי',
      const ['תוספות על ברכות'],
      bookTitle: 'ברכות',
    );

    final selection = await DefaultCommentators.getInitialSelection(
      TextBook(title: 'מכות', heCategories: _bavliCategories),
      availableCommentators: const ['תוספות הרא"ש על מכות', 'תוספות על מכות'],
      baseCommentators: const [],
    );

    expect(selection, ['תוספות על מכות']);
  });

  test('צורת הדף בהיקף קטגוריה נטענת כאותו מפרש בספר אחר', () async {
    await PageShapeSettingsManager.saveConfiguration(
      'ברכות',
      {
        'left': 'תוספות על ברכות',
        'right': null,
        'bottom': null,
        'bottomRight': null,
      },
      saveToCategory: 'תלמוד בבלי',
    );

    final config = PageShapeSettingsManager.loadConfiguration(
      'מכות',
      heCategories: _bavliCategories,
    );

    expect(
      resolvePageShapeCommentatorSelection(
        selection: config?['left'],
        availableCommentators: const [
          'תוספות הרא"ש על מכות',
          'תוספות על מכות',
        ],
        commentedBookTitle: 'מכות',
      ),
      'תוספות על מכות',
    );
  });
}
