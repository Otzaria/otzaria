// כלי עזר לבדיקת האינדקס הגולמי - לא חלק מהתוכנה
// להשתמש רק לצורכי debug

import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';

void _log(String message) {
  // הדפסה גם ל-debugPrint וגם ל-developer log
  debugPrint(message);
  developer.log(message, name: 'DEBUG_INDEX');
  // ignore: avoid_print
  print(message); // גם print רגיל למקרה שה-debug לא עובד
}

/// פונקציה לבדיקת מה באמת מאונדקס ב-Tantivy
/// קורא לה עם: await debugViewRawIndex('משנה');
Future<void> debugViewRawIndex(String query, {int limit = 1000}) async {
  _log('\n${'=' * 80}');
  _log('🔍 בדיקת אינדקס גולמי - ללא סינון');
  _log('שאילתה: "$query"');
  _log('מגבלה: $limit תוצאות');
  _log('=' * 80);

  try {
    _log('מתחיל שאילתה...');
    final results = await TantivyDataProvider.instance.searchRefs(query, limit, false);

    _log('\n📥 נמצאו ${results.length} תוצאות באינדקס\n');
    _log('--- כל התוצאות הגולמיות ---\n');

    for (int i = 0; i < results.length; i++) {
      _log('[$i] title="${results[i].title}" | ref="${results[i].reference}"');
    }

    _log('\n' + '=' * 80);
    _log('✅ סיום - סה"כ ${results.length} תוצאות');
    _log('=' * 80 + '\n');
  } catch (e, stackTrace) {
    _log('❌ שגיאה: $e');
    _log('Stack trace: $stackTrace');
    _log('=' * 80 + '\n');
  }
}
