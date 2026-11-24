#ifndef RUNNER_ACTIVATION_GATE_H_
#define RUNNER_ACTIVATION_GATE_H_

#include <string>

namespace otzaria {

// כמה זמן בחירת המשתמש "מוגנת" מפני הפעלה תוכניתית של חלון אחר שלנו.
//
// חלון בסדר גודל של חצי שנייה: ארוך מספיק כדי לכסות את ההפעלה החוזרת
// שהמנוע מייצר (נמדדה תוך ~30ms), וקצר מספיק שלא יחסום העלאה לגיטימית
// (כרטיסיה שהועברה, `otzaria://`) שמגיעה אחרי אינטראקציה אמיתית.
constexpr unsigned long long kUserChoiceGraceMs = 500;

// חלון אוצריא לפי מחלקת החלון.
inline bool IsOtzariaWindowClass(const std::wstring& name) {
  return name == L"FLUTTER_RUNNER_WIN32_WINDOW";
}

// השער של [Win32Window::ShouldVetoActivation], בלי Win32 כדי שייבדק לבד.
// [class_of] מחזיר את מחלקת החלון, [shown] — האם החלון קיים ומוצג.
template <typename Window>
class ActivationGate {
 public:
  void NoteUserActivation(Window window, unsigned long long now) {
    user_activated_ = window;
    user_activated_at_ = now;
  }

  template <typename ClassOf, typename Shown>
  bool ShouldVetoActivation(Window window,
                            unsigned long long now,
                            ClassOf class_of,
                            Shown shown) const {
    if (user_activated_ == Window{}) return false;
    if (window == user_activated_) return false;
    if (window == Window{} || !IsOtzariaWindowClass(class_of(window)) ||
        !IsOtzariaWindowClass(class_of(user_activated_))) {
      return false;
    }
    if (!shown(user_activated_)) return false;
    return now - user_activated_at_ < kUserChoiceGraceMs;
  }

 private:
  Window user_activated_{};
  unsigned long long user_activated_at_ = 0;
};

}  // namespace otzaria

#endif  // RUNNER_ACTIVATION_GATE_H_
