// סקריפט זמני לבדיקת האינדקס הגולמי
// להריץ עם: dart run test_raw_index.dart

import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';

void main() async {
  print('🔍 בודק גישה ישירה לאינדקס Tantivy\n');
  
  // שנה את השאילתה כאן
  final query = 'משנה';
  final limit = 1000;
  
  print('שאילתה: "$query"');
  print('מגבלה: $limit תוצאות\n');
  print('=' * 80);
  
  try {
    final results = await TantivyDataProvider.instance.searchRefs(query, limit, false);
    
    print('📥 נמצאו ${results.length} תוצאות באינדקס\n');
    print('--- כל התוצאות הגולמיות ---\n');
    
    for (int i = 0; i < results.length; i++) {
      print('[$i] title="${results[i].title}" | ref="${results[i].reference}"');
    }
    
    print('\n' + '=' * 80);
    print('✅ סיום');
    
  } catch (e) {
    print('❌ שגיאה: $e');
  }
}
