#ifndef RUNNER_ANKI_NATIVE_WINDOW_HOST_H_
#define RUNNER_ANKI_NATIVE_WINDOW_HOST_H_

#include <windows.h>

#include <mutex>
#include <string>

class AnkiNativeWindowHost {
 public:
  explicit AnkiNativeWindowHost(HWND flutter_view);
  ~AnkiNativeWindowHost();

  bool Prepare(HWND* container, std::string* error);
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

  HWND flutter_view_ = nullptr;
  HWND container_ = nullptr;
  HWND target_ = nullptr;
  bool visible_ = true;
  std::mutex mutex_;
};

#endif  // RUNNER_ANKI_NATIVE_WINDOW_HOST_H_
