#ifndef RUNNER_WINDOW_CENTERING_H_
#define RUNNER_WINDOW_CENTERING_H_

#include <cmath>
#include <limits>

namespace otzaria {

// Rectangles and positions use physical screen pixels throughout.
template <typename Rect, typename ReadBounds, typename MoveWindow>
bool CenterWindowInWorkArea(const Rect& area,
                            ReadBounds read_bounds,
                            MoveWindow move_window) {
  const auto width = [](const Rect& r) {
    return static_cast<double>(r.right) - r.left;
  };
  const auto height = [](const Rect& r) {
    return static_cast<double>(r.bottom) - r.top;
  };
  auto move_centered = [&](const Rect& bounds) {
    if (width(bounds) <= 0 || height(bounds) <= 0 || width(area) <= 0 ||
        height(area) <= 0)
      return false;
    const double x = area.left + (width(area) - width(bounds)) / 2;
    const double y = area.top + (height(area) - height(bounds)) / 2;
    if (!std::isfinite(x) || !std::isfinite(y) ||
        x < (std::numeric_limits<int>::min)() ||
        x > (std::numeric_limits<int>::max)() ||
        y < (std::numeric_limits<int>::min)() ||
        y > (std::numeric_limits<int>::max)())
      return false;
    return move_window(static_cast<int>(x), static_cast<int>(y));
  };

  Rect before{};
  if (!read_bounds(&before) || !move_centered(before)) return false;

  // SetWindowPos synchronously delivers WM_DPICHANGED, which can resize the
  // window. Re-center only if its physical size changed on the destination.
  Rect after{};
  if (!read_bounds(&after)) return false;
  if (width(after) != width(before) || height(after) != height(before))
    return move_centered(after);
  return true;
}

}  // namespace otzaria

#endif  // RUNNER_WINDOW_CENTERING_H_
