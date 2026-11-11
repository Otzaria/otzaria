#ifndef RUNNER_NATIVE_EXCEPTION_RECORDS_H_
#define RUNNER_NATIVE_EXCEPTION_RECORDS_H_

#include <algorithm>
#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <optional>

namespace native_exception_log {

struct Record {
  std::uint64_t awake_ms = 0;
  std::uintptr_t address = 0;
  std::uint32_t code = 0;
};

inline constexpr std::size_t kRecordLimit = 8;

struct Snapshot {
  std::array<Record, kRecordLimit> records{};
  std::size_t size = 0;
};

class RecentRecords {
 public:
  bool TryRecord(const Record& record) {
    if (busy_.test_and_set(std::memory_order_acquire)) return false;
    ring_[next_] = record;
    next_ = (next_ + 1) % ring_.size();
    if (size_ < ring_.size()) ++size_;
    busy_.clear(std::memory_order_release);
    return true;
  }

  Snapshot TrySnapshot() {
    Snapshot snapshot;
    if (busy_.test_and_set(std::memory_order_acquire)) return snapshot;
    const std::size_t first = (next_ + ring_.size() - size_) % ring_.size();
    for (std::size_t i = 0; i < size_; ++i) {
      snapshot.records[i] = ring_[(first + i) % ring_.size()];
    }
    snapshot.size = size_;
    busy_.clear(std::memory_order_release);
    return snapshot;
  }

 private:
  // הכותב והקורא מוותרים על הלכידה אם התא תפוס. איש מהם אינו ממתין.
  std::atomic_flag busy_ = ATOMIC_FLAG_INIT;
  std::array<Record, kRecordLimit> ring_{};
  std::size_t next_ = 0;
  std::size_t size_ = 0;
};

template <typename Frames>
std::optional<Record> FindStackMatch(const Snapshot& snapshot,
                                    const Frames& frames,
                                    std::uint64_t earliest_ms,
                                    std::uint64_t detected_ms) {
  for (std::size_t i = 0; i < snapshot.size; ++i) {
    const Record& record = snapshot.records[i];
    if (record.awake_ms >= earliest_ms && record.awake_ms <= detected_ms &&
        record.address != 0 &&
        std::find(frames.begin(), frames.end(), record.address) != frames.end()) {
      return record;
    }
  }
  return std::nullopt;
}

}  // namespace native_exception_log

#endif  // RUNNER_NATIVE_EXCEPTION_RECORDS_H_
