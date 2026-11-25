#ifndef RUNNER_CRASH_RECORD_H_
#define RUNNER_CRASH_RECORD_H_

#include <string>

// רושם ל-errors.txt קריסה נייטיבית שקרתה לפני ש-Sentry עלה (הוא מחליף את המטפל),
// כדי שההפעלה הבאה תציע דוח עם חתימה גם כשאין minidump.
namespace crash_record {

// נקרא מוקדם ב-wWinMain, מה-thread הראשי.
void Install();

// נעילת העלייה לתהליך ה-GUI, אחרי בדיקת המופע היחיד.
void BeginSession();

// המצב המספרי האחרון ש-Dart פרסם, ללא טקסט מהחלון.
void AppendDiagnosticContext(std::string* report);

}  // namespace crash_record

#endif  // RUNNER_CRASH_RECORD_H_
