import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/native_incident_context.dart';

void main() {
  test('הקידוד תואם לרשומת התקיעה בלי כותרת חלון או ספר', () {
    final word = NativeIncidentContext.encode({
      'screen': 'reading',
      'currentTab': 'PdfBookTab',
      'currentTitle': 'כותרת פרטית',
      'tabs': 4,
    }, true);
    expect(word, 3 | (2 << 4) | (1 << 8) | (4 << 9));
  });

  test('שמות לא מוכרים ומספר טאבים חריג אינם נכתבים כלשונם', () {
    final word = NativeIncidentContext.encode({
      'screen': 'search',
      'currentTab': 'private custom tab',
      'tabs': 10000000,
    }, false);
    expect(word, 4 | (8 << 4) | (0xffff << 9));
    expect(NativeIncidentContext.encode({}, false), 0);
  });
}
