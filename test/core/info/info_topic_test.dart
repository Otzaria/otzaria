import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/info/info_topic.dart';

void main() {
  group('InfoTopic.fromSlug', () {
    test('מזהה את כל הנושאים לפי ה-slug', () {
      for (final topic in InfoTopic.values) {
        expect(InfoTopic.fromSlug(topic.slug), topic);
      }
    });

    test('אינו רגיש לאותיות גדולות ולרווחים', () {
      expect(InfoTopic.fromSlug('  APP '), InfoTopic.app);
      expect(InfoTopic.fromSlug('Library'), InfoTopic.library);
    });

    test('תומך ב-aliases', () {
      expect(InfoTopic.fromSlug('software'), InfoTopic.app);
      expect(InfoTopic.fromSlug('version'), InfoTopic.app);
      expect(InfoTopic.fromSlug('books'), InfoTopic.library);
      expect(InfoTopic.fromSlug('plugin'), InfoTopic.plugins);
      expect(InfoTopic.fromSlug('logs'), InfoTopic.errors);
      expect(InfoTopic.fromSlug('personal'), InfoTopic.folders);
      expect(InfoTopic.fromSlug('personal_books'), InfoTopic.folders);
      expect(InfoTopic.fromSlug('custom_folders'), InfoTopic.folders);
    });

    test('נושא לא מוכר מוחזר null', () {
      expect(InfoTopic.fromSlug('banana'), isNull);
      expect(InfoTopic.fromSlug(''), isNull);
    });
  });

  group('InfoTopic.sections', () {
    test('all מתפרס לכל שאר הנושאים בסדר קבוע', () {
      expect(InfoTopic.all.sections, [
        InfoTopic.app,
        InfoTopic.library,
        InfoTopic.folders,
        InfoTopic.plugins,
        InfoTopic.errors,
      ]);
    });

    test('נושא בודד מחזיר את עצמו', () {
      expect(InfoTopic.library.sections, [InfoTopic.library]);
    });
  });
}
