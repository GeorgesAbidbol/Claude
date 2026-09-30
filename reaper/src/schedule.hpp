// Time-sorted list of OSC packets and the logic deciding which ones are due
// for each audio block. Independent of REAPER so it can be unit tested.
#pragma once

#include <cstdint>
#include <vector>

namespace ma3 {

struct ScheduledEvent {
  double time = 0;           // project time in seconds
  std::vector<uint8_t> packet;
};

class Schedule {
 public:
  explicit Schedule(std::vector<ScheduledEvent> events);
  const std::vector<ScheduledEvent>& events() const { return events_; }
  // Index of the first event at or after t.
  size_t LowerBound(double t) const;

 private:
  std::vector<ScheduledEvent> events_;
};

// Walks a Schedule as playback advances. Call Advance() once per audio block
// with the block's start position and duration. Events are reported only when
// playback runs through them: seeks and loops re-position silently.
class Dispatcher {
 public:
  // A jump larger than this (forward) or any backward move counts as a seek.
  static constexpr double kSeekTolerance = 0.25;

  void Reset() { valid_ = false; }

  // Calls emit(index, delay_seconds) for events in [pos, pos + duration).
  template <typename Emit>
  void Advance(const Schedule& s, double pos, double duration, Emit&& emit) {
    if (!valid_ || pos < expected_ - 1e-6 || pos > expected_ + kSeekTolerance) {
      cursor_ = s.LowerBound(pos);
      valid_ = true;
    }
    const auto& ev = s.events();
    const double end = pos + duration;
    while (cursor_ < ev.size() && ev[cursor_].time < end) {
      if (ev[cursor_].time >= pos - 1e-9) emit(cursor_, ev[cursor_].time - pos);
      ++cursor_;
    }
    expected_ = end;
  }

 private:
  bool valid_ = false;
  size_t cursor_ = 0;
  double expected_ = 0;
};

}  // namespace ma3
