import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:otzaria/tools/shamor_zachor/services/progress_service.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';
import 'dart:convert';

void main() {
  group('Progress Migration Tests', () {
    late ProgressService progressService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      progressService = ProgressService();
    });

    tearDown(() async {
      await progressService.clearAllProgress();
      await progressService.resetMigrationFlag();
    });

    test('Migration should transfer old progress data to new format', () async {
      // Arrange: Create old format data
      final oldProgress = {
        'תלמוד בבלי': {
          'ברכות': {
            '1': PageProgress(learn: true, review1: true),
            '2': PageProgress(learn: true),
            '5': PageProgress(learn: true, review1: true, review2: true),
          },
          'שבת': {
            '1': PageProgress(learn: true),
            '10': PageProgress(learn: true, review1: true),
          }
        },
        'תנ"ך': {
          'בראשית': {
            '1': PageProgress(
                learn: true, review1: true, review2: true, review3: true),
          }
        }
      };

      // Save old format data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'sz:progress_data', _encodeOldProgress(oldProgress));

      // Mock book ID finder
      Future<int?> findBookId(String category, String book) async {
        final bookIds = {
          'תלמוד בבלי/ברכות': 1,
          'תלמוד בבלי/שבת': 2,
          'תנ"ך/בראשית': 3,
        };
        return bookIds['$category/$book'];
      }

      // Act: Run migration
      final result = await progressService.migrateOldProgressToNewFormat(
        findBookIdByName: findBookId,
      );

      // Assert: Check migration succeeded
      expect(result, isTrue);

      // Verify migration flag is set
      final migrationCompleted = prefs.getBool('sz:migration_completed');
      expect(migrationCompleted, isTrue);

      // Verify new format data
      final newProgress = await progressService.loadProgressDataById();
      expect(newProgress.length, equals(3)); // 3 books

      // Check ברכות (ID: 1)
      expect(newProgress[1], isNotNull);
      expect(newProgress[1]!.length, equals(3)); // 3 items
      expect(newProgress[1]!['1']!.learn, isTrue);
      expect(newProgress[1]!['1']!.review1, isTrue);
      expect(newProgress[1]!['2']!.learn, isTrue);
      expect(newProgress[1]!['5']!.review2, isTrue);

      // Check שבת (ID: 2)
      expect(newProgress[2], isNotNull);
      expect(newProgress[2]!.length, equals(2)); // 2 items

      // Check בראשית (ID: 3)
      expect(newProgress[3], isNotNull);
      expect(newProgress[3]!['1']!.learn, isTrue);
      expect(newProgress[3]!['1']!.review3, isTrue);
    });

    test('Migration should not run twice', () async {
      // Arrange: Create old format data
      final oldProgress = {
        'תלמוד בבלי': {
          'ברכות': {
            '1': PageProgress(learn: true),
          }
        }
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'sz:progress_data', _encodeOldProgress(oldProgress));

      Future<int?> findBookId(String category, String book) async {
        return 1;
      }

      // Act: Run migration first time
      await progressService.migrateOldProgressToNewFormat(
        findBookIdByName: findBookId,
      );

      // Clear new data to test if migration runs again
      await prefs.remove('sz:progress_by_id');

      // Run migration second time
      final result = await progressService.migrateOldProgressToNewFormat(
        findBookIdByName: findBookId,
      );

      // Assert: Migration should skip (return true but not migrate)
      expect(result, isTrue);

      // New data should still be empty (migration didn't run)
      final newProgress = await progressService.loadProgressDataById();
      expect(newProgress.isEmpty, isTrue);
    });

    test('Migration should handle books not found in DB', () async {
      // Arrange: Create old format data with books that don't exist
      final oldProgress = {
        'קטגוריה': {
          'ספר לא קיים': {
            '1': PageProgress(learn: true),
          },
          'ספר קיים': {
            '1': PageProgress(learn: true),
          }
        }
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'sz:progress_data', _encodeOldProgress(oldProgress));

      Future<int?> findBookId(String category, String book) async {
        if (book == 'ספר קיים') return 100;
        return null; // Book not found
      }

      // Act: Run migration
      final result = await progressService.migrateOldProgressToNewFormat(
        findBookIdByName: findBookId,
      );

      // Assert: Migration should succeed but skip missing books
      expect(result, isTrue);

      final newProgress = await progressService.loadProgressDataById();
      expect(newProgress.length, equals(1)); // Only the existing book
      expect(newProgress[100], isNotNull);
    });

    test('Migration should skip if no old data exists', () async {
      // Arrange: No old data

      Future<int?> findBookId(String category, String book) async {
        return 1;
      }

      // Act: Run migration
      final result = await progressService.migrateOldProgressToNewFormat(
        findBookIdByName: findBookId,
      );

      // Assert: Should succeed and mark as completed
      expect(result, isTrue);

      final prefs = await SharedPreferences.getInstance();
      final migrationCompleted = prefs.getBool('sz:migration_completed');
      expect(migrationCompleted, isTrue);
    });
  });
}

// Helper function to encode old progress format
String _encodeOldProgress(
    Map<String, Map<String, Map<String, PageProgress>>> progress) {
  final encoded = <String, dynamic>{};

  progress.forEach((category, books) {
    encoded[category] = <String, dynamic>{};
    books.forEach((book, items) {
      encoded[category][book] = <String, dynamic>{};
      items.forEach((item, pageProgress) {
        encoded[category][book][item] = pageProgress.toJson();
      });
    });
  });

  return json.encode(encoded);
}
