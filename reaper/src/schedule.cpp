#include "schedule.hpp"

#include <algorithm>

namespace ma3 {

Schedule::Schedule(std::vector<ScheduledEvent> events) : events_(std::move(events)) {
  std::stable_sort(events_.begin(), events_.end(),
                   [](const ScheduledEvent& a, const ScheduledEvent& b) { return a.time < b.time; });
}

size_t Schedule::LowerBound(double t) const {
  auto it = std::lower_bound(events_.begin(), events_.end(), t,
                             [](const ScheduledEvent& e, double v) { return e.time < v; });
  return size_t(it - events_.begin());
}

}  // namespace ma3
