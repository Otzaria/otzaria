import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';

void main() {
  group('PageProgress (dynamic columns)', () {
    test('legacy constructor maps to default column ids', () {
      final progress = PageProgress(learn: true, review2: true);

      expect(progress.getProperty('learn'), isTrue);
      expect(progress.getProperty('review2'), isTrue);
      expect(progress.getProperty('review1'), isFalse);
      expect(progress.completedCount, 2);
    });

    test('toJson stores only checked columns and round-trips', () {
      final progress = PageProgress(learn: true);
      progress.setProperty('rashi', true);

      final json = progress.toJson();
      expect(json, {'learn': true, 'rashi': true});

      final restored = PageProgress.fromJson(json);
      expect(restored.getProperty('learn'), isTrue);
      expect(restored.getProperty('rashi'), isTrue);
    });

    test('fromJson ignores false/missing values', () {
      final progress = PageProgress.fromJson({'learn': true, 'review1': false});
      expect(progress.getProperty('learn'), isTrue);
      expect(progress.getProperty('review1'), isFalse);
      expect(progress.completedCount, 1);
    });

    test('setProperty false removes the column (kept empty)', () {
      final progress = PageProgress(learn: true);
      progress.setProperty('learn', false);
      expect(progress.isEmpty, isTrue);
      expect(progress.toJson(), isEmpty);
    });

    test('isCompleteFor checks all given columns', () {
      final progress = PageProgress();
      progress.setProperty('learn', true);
      progress.setProperty('rashi', true);

      expect(progress.isCompleteFor(['learn', 'rashi']), isTrue);
      expect(progress.isCompleteFor(['learn', 'rashi', 'tosafot']), isFalse);
      expect(progress.completedCountFor(['learn', 'rashi', 'tosafot']), 2);
    });

    test('removeColumn drops a single column', () {
      final progress = PageProgress(learn: true, review1: true);
      progress.removeColumn('review1');
      expect(progress.getProperty('learn'), isTrue);
      expect(progress.getProperty('review1'), isFalse);
    });

    test('equality is based on checked columns', () {
      final a = PageProgress(learn: true);
      final b = PageProgress(learn: true);
      final c = PageProgress(learn: true, review1: true);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('ProgressColumn', () {
    test('json round-trip', () {
      const column = ProgressColumn(id: 'rashi', label: 'רש"י');
      expect(ProgressColumn.fromJson(column.toJson()), column);
    });

    test('copyWith changes label but keeps id', () {
      const column = ProgressColumn(id: 'review1', label: 'חזרה 1');
      final renamed = column.copyWith(label: 'תוספות');
      expect(renamed.id, 'review1');
      expect(renamed.label, 'תוספות');
    });

    test('default columns match historical ids', () {
      expect(kDefaultProgressColumns.map((c) => c.id).toList(),
          ['learn', 'review1', 'review2', 'review3']);
    });
  });
}
