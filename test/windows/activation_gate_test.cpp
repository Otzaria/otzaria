#include "activation_gate.h"

#include <iostream>
#include <map>
#include <string>

namespace {

// חלונות מדומים: ראשי, חלונות Dart, וחלון של תוכנה אחרת.
constexpr int kMain = 1;
constexpr int kDartWindow = 2;
constexpr int kForeign = 3;
constexpr int kHidden = 4;
constexpr int kSecondDartWindow = 5;

const std::map<int, std::wstring> kClasses = {
    {kMain, L"FLUTTER_RUNNER_WIN32_WINDOW"},
    {kDartWindow, L"FLUTTER_HOST_WINDOW"},
    {kForeign, L"Notepad"},
    {kHidden, L"FLUTTER_HOST_WINDOW"},
    {kSecondDartWindow, L"FLUTTER_HOST_WINDOW"},
};

std::wstring ClassOf(int window) {
  const auto it = kClasses.find(window);
  return it == kClasses.end() ? std::wstring() : it->second;
}

bool Shown(int window) { return window != kHidden && kClasses.count(window); }

int failures = 0;

void Expect(bool actual, bool expected, const char* name) {
  std::cout << (actual == expected ? "ok   " : "FAIL ") << name
            << " (veto=" << actual << ", expected=" << expected << ")\n";
  if (actual != expected) ++failures;
}

bool Veto(int chosen, int activated, unsigned long long elapsed) {
  otzaria::ActivationGate<int> gate;
  if (chosen != 0) gate.NoteUserActivation(chosen, 1000);
  return gate.ShouldVetoActivation(activated, 1000 + elapsed, ClassOf, Shown);
}

}  // namespace

int main() {
  // issue #5743: לחיצה על חלון Dart; המנוע מפעיל מחדש את הראשי — נחסם.
  Expect(Veto(kDartWindow, kMain, 30), true,
         "click Dart window, main re-activates");
  Expect(Veto(kMain, kDartWindow, 30), true,
         "click main, Dart window re-activates");
  Expect(Veto(kDartWindow, kSecondDartWindow, 30), true,
         "click Dart window, another Dart window re-activates");

  // ההתנהגות הקיימת נשמרת.
  Expect(Veto(kMain, kMain, 30), false, "same window");
  Expect(Veto(0, kMain, 30), false, "no user choice");
  Expect(Veto(kDartWindow, kMain, 500), false, "after the grace period");
  Expect(Veto(kDartWindow, kForeign, 30), false, "foreign window activates");
  Expect(Veto(kForeign, kMain, 30), false, "user chose a foreign window");
  Expect(Veto(kHidden, kMain, 30), false, "chosen window is hidden");
  Expect(Veto(kDartWindow, 0, 30), false, "null window");

  // העלאה מכוונת (חשיפת חלון Dart, `focus`) ממש אחרי לחיצה על הראשי נרשמת
  // ולכן עוברת, והפעלה חוזרת של הראשי אחריה נחסמת.
  otzaria::ActivationGate<int> gate;
  gate.NoteUserActivation(kMain, 1000);
  Expect(gate.ShouldVetoActivation(kDartWindow, 1100, ClassOf, Shown), true,
         "unnoted raise right after a click on main");
  gate.NoteUserActivation(kDartWindow, 1100);
  Expect(gate.ShouldVetoActivation(kDartWindow, 1100, ClassOf, Shown), false,
         "noted raise right after a click on main");
  Expect(gate.ShouldVetoActivation(kMain, 1130, ClassOf, Shown), true,
         "main re-activates after the noted raise");

  if (failures != 0) {
    std::cout << failures << " activation gate case(s) failed\n";
    return 1;
  }
  std::cout << "Activation gate cases passed\n";
}
