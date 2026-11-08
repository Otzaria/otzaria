import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../flutter_test_config.dart' as root;
import '../support/golden_fonts.dart';
import 'golden_harness.dart';

/// Flutter משתמש רק בקובץ הקונפיגורציה הקרוב ביותר, ולכן זה משרשר את
/// הקונפיגורציה של `test/` (מנוע החיפוש, תיקיית נתונים זמנית) ומוסיף לה את
/// הגופנים ואת ה-comparator של ה-goldens.
Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    root.testExecutable(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await loadGoldenFonts();
      final current = goldenFileComparator;
      if (current is LocalFileComparator) {
        goldenFileComparator = TolerantGoldenFileComparator(
          current.basedir.resolve('golden_test.dart'),
        );
      }
      await testMain();
    });
