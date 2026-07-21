import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';

void main() {
  group('קישורים לתצוגה מקדימה', () {
    test('קישור start/end מפוענח לקישור יעד', () {
      final link = inlineLinkFromPreviewUrl(
        'otzaria://inline-link?path=%D7%9E%D7%A7%D7%95%D7%A8%20%D7%90&index=2&ref=%D7%9E%D7%A7%D7%95%D7%A8%20%D7%90%2C%20%D7%91',
      );

      expect(link, isNotNull);
      expect(link!.path2, 'מקור א');
      expect(link.index2, 2);
      expect(link.heRef, 'מקור א, ב');
    });

    test('קישור לא תקין אינו הופך לתצוגה מקדימה', () {
      expect(
        inlineLinkFromPreviewUrl('otzaria://inline-link?path=מקור&index=0'),
        isNull,
      );
    });

    test('כל סוגי הקישורים הרלוונטיים מאפשרים ריחוף', () {
      expect(
        isPreviewHoverableUrl('otzaria://inline-link?path=מקור&index=1'),
        isTrue,
      );
      expect(isPreviewHoverableUrl('https://example.com'), isFalse);
    });
  });
}
