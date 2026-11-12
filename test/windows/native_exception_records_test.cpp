#include "native_exception_records.h"

#include <cassert>
#include <thread>

int main() {
  using native_exception_log::FindStackMatch;
  using native_exception_log::RecentRecords;

  RecentRecords recent;
  const std::array<std::uintptr_t, 2> frames{0x2000, 0x1000};
  assert(!FindStackMatch(recent.TrySnapshot(), frames, 10, 19));
  assert(recent.TryRecord({9, 0x2000, 1}));
  assert(recent.TryRecord({10, 0x1000, 2}));
  for (unsigned int i = 11; i < 16; ++i) {
    assert(recent.TryRecord({i, 0x3000, 3}));
  }
  assert(recent.TryRecord({20, 0x2000, 4}));

  const auto full = recent.TrySnapshot();
  assert(full.size == 8);
  const auto match = FindStackMatch(full, frames, 10, 19);
  assert(match && match->code == 2);
  assert(!FindStackMatch(full, frames, 11, 19));
  assert(FindStackMatch(full, frames, 11, 20)->code == 4);
  assert(recent.TryRecord({21, 0x3000, 5}));
  assert(recent.TryRecord({22, 0x3000, 5}));
  const auto wrapped = recent.TrySnapshot();
  assert(wrapped.size == 8);
  assert(wrapped.records[0].awake_ms == 11);
  assert(!FindStackMatch(wrapped, frames, 10, 19));

  RecentRecords concurrent;
  std::atomic<bool> finished{false};
  std::thread writer([&] {
    for (unsigned int i = 1; i <= 100000; ++i) {
      concurrent.TryRecord({i, i * 2, i * 3});
    }
    finished.store(true, std::memory_order_release);
  });
  do {
    const auto snapshot = concurrent.TrySnapshot();
    std::uint64_t previous = 0;
    for (std::size_t i = 0; i < snapshot.size; ++i) {
      const auto& record = snapshot.records[i];
      assert(record.awake_ms > previous);
      assert(record.address == record.awake_ms * 2);
      assert(record.code == record.awake_ms * 3);
      previous = record.awake_ms;
    }
  } while (!finished.load(std::memory_order_acquire));
  writer.join();
}
