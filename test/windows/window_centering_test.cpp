#include "window_centering.h"

#include <cassert>
#include <iostream>
#include <utility>
#include <vector>

struct Rect {
  int left;
  int top;
  int right;
  int bottom;
};

struct Window {
  Rect bounds;
  int resized_width = 0;
  int resized_height = 0;
  int fail_read = 0;
  int fail_move = 0;
  int reads = 0;
  std::vector<std::pair<int, int>> moves{};

  bool center(Rect area) {
    return otzaria::CenterWindowInWorkArea(
        area,
        [&](Rect* result) {
          if (++reads == fail_read) return false;
          *result = bounds;
          return true;
        },
        [&](int left, int top) {
          moves.emplace_back(left, top);
          if (static_cast<int>(moves.size()) == fail_move) return false;
          int width = bounds.right - bounds.left;
          int height = bounds.bottom - bounds.top;
          if (moves.size() == 1 && resized_width > 0) {
            width = resized_width;
            height = resized_height;
          }
          bounds = {left, top, left + width, top + height};
          return true;
        });
  }
};

int main() {
  const Rect primary{0, 0, 1920, 1040};
  const Rect secondary{1920, 0, 5760, 2080};

  Window primary_window{{0, 0, 800, 600}};
  assert(primary_window.center(primary));
  assert((primary_window.moves == std::vector<std::pair<int, int>>{{560, 220}}));

  // A 200% window on the secondary must not scale the monitor's global origin.
  Window secondary_window{{2000, 100, 3600, 1300}};
  assert(secondary_window.center(secondary));
  assert((secondary_window.moves == std::vector<std::pair<int, int>>{{3040, 440}}));

  Window without_resize{{0, 0, 800, 600}};
  assert(without_resize.center(secondary));
  assert((without_resize.moves == std::vector<std::pair<int, int>>{{3440, 740}}));
  assert(without_resize.reads == 2);
  assert(without_resize.bounds.right - without_resize.bounds.left == 800);
  assert(without_resize.bounds.bottom - without_resize.bounds.top == 600);

  // The cursor selects the other monitor; WM_DPICHANGED preserves logical size.
  Window to_secondary{{0, 0, 800, 600}};
  to_secondary.resized_width = 1600;
  to_secondary.resized_height = 1200;
  assert(to_secondary.center(secondary));
  assert((to_secondary.moves ==
          std::vector<std::pair<int, int>>{{3440, 740}, {3040, 440}}));
  assert(to_secondary.reads == 2);
  assert(to_secondary.bounds.right - to_secondary.bounds.left == 1600);
  assert(to_secondary.bounds.bottom - to_secondary.bounds.top == 1200);

  Window to_primary{{2000, 100, 3600, 1300}};
  to_primary.resized_width = 800;
  to_primary.resized_height = 600;
  assert(to_primary.center(primary));
  assert((to_primary.moves ==
          std::vector<std::pair<int, int>>{{160, -80}, {560, 220}}));
  assert(to_primary.reads == 2);
  assert(to_primary.bounds.right - to_primary.bounds.left == 800);
  assert(to_primary.bounds.bottom - to_primary.bounds.top == 600);

  Window left_monitor{{-2000, 100, -1000, 800}};
  assert(left_monitor.center({-2560, 40, 0, 1440}));
  assert((left_monitor.moves == std::vector<std::pair<int, int>>{{-1780, 390}}));

  Window above_monitor{{-1800, -1100, -1000, -500}};
  assert(above_monitor.center({-1920, -1160, 0, -80}));
  assert((above_monitor.moves == std::vector<std::pair<int, int>>{{-1360, -920}}));

  // A fractional DPI is already reflected in the physical size from Win32.
  Window fractional{{2000, 100, 3000, 850}};
  assert(fractional.center({1920, 40, 4480, 1440}));
  assert((fractional.moves == std::vector<std::pair<int, int>>{{2700, 365}}));

  for (int failed_read : {1, 2}) {
    Window window{{0, 0, 800, 600}};
    window.fail_read = failed_read;
    assert(!window.center(primary));
    assert(window.moves.size() == static_cast<size_t>(failed_read - 1));
    assert(window.reads == failed_read);
  }
  for (int failed_move : {1, 2}) {
    Window window{{0, 0, 800, 600}};
    window.resized_width = 1600;
    window.resized_height = 1200;
    window.fail_move = failed_move;
    assert(!window.center(secondary));
    assert(window.moves.size() == static_cast<size_t>(failed_move));
    assert(window.reads == failed_move);
  }

  Window empty_window{{0, 0, 0, 0}};
  assert(!empty_window.center(primary));
  assert(empty_window.moves.empty());
  Window empty_area{{0, 0, 800, 600}};
  assert(!empty_area.center({0, 0, 0, 0}));
  assert(empty_area.moves.empty());

  std::cout << "Physical window centering cases passed\n";
}
