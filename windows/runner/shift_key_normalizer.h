#ifndef RUNNER_SHIFT_KEY_NORMALIZER_H_
#define RUNNER_SHIFT_KEY_NORMALIZER_H_

#include <windows.h>

// מתקן קודי סריקה חסרים של Ctrl/V והודעות Shift חריגות לפני מיפוי ה-engine,
// כדי שמקשים שונים לא יירשמו כאותו מקש פיזי לא מוכר.
void InstallShiftKeyNormalizer(HWND flutter_view);

// רץ לפני TranslateMessage כדי שגם הודעות התו יקבלו את קוד הסריקה התקין.
void NormalizeFlutterKeyboardMessage(MSG& message);

#endif  // RUNNER_SHIFT_KEY_NORMALIZER_H_
