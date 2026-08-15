#ifndef RUNNER_ANKI_NATIVE_WINDOW_HOST_H_
#define RUNNER_ANKI_NATIVE_WINDOW_HOST_H_

#include <windows.h>

#include <mutex>
#include <string>

class AnkiNativeWindowHost {
 public:
  explicit AnkiNativeWindowHost(HWND flutter_view);
  ~AnkiNativeWindowHost();

  bool Attach(HWND target, DWORD expected_process_id, std::string* error);
  bool SetBounds(int x, int y, int width, int height, std::string* error);
  void SetVisible(bool visible);
  void Detach();
  bool LaunchAnki(std::string* error);

 private:
  bool EnsureContainer(std::string* error);
  bool ValidateAnkiWindow(HWND target, DWORD expected_process_id,
                          std::string* error) const;
  void DetachUnlocked();
  void ResizeAttachedWindow();

  HWND flutter_view_ = nullptr;
  HWND container_ = nullptr;
  HWND target_ = nullptr;
  HWND original_parent_ = nullptr;
  LONG_PTR original_style_ = 0;
  LONG_PTR original_extended_style_ = 0;
  RECT original_rect_{};
  WINDOWPLACEMENT original_placement_{};
  bool original_visible_ = false;
  bool visible_ = true;
  std::mutex mutex_;
};

#endif  // RUNNER_ANKI_NATIVE_WINDOW_HOST_H_
