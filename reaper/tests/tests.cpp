// Unit tests for the REAPER-independent parts. Run with ctest.
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "osc.hpp"
#include "schedule.hpp"
#include "template.hpp"

using namespace ma3;

static int g_failures = 0;
#define CHECK(cond)                                                   \
  do {                                                                \
    if (!(cond)) {                                                    \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);     \
      ++g_failures;                                                   \
    }                                                                 \
  } while (0)

static std::vector<uint8_t> Bytes(const char* s, size_t n) { return std::vector<uint8_t>(s, s + n); }

static void TestEncodeCmd() {
  // "/cmd" ",s" "Go+ Sequence 1" with 4-byte padding.
  auto p = CommandToOsc("Go+ Sequence 1", "");
  const char expect[] = "/cmd\0\0\0\0,s\0\0Go+ Sequence 1\0\0";
  CHECK(p == Bytes(expect, sizeof expect - 1));
  CHECK(p.size() % 4 == 0);
}

static void TestPrefix() {
  auto p = CommandToOsc("Go+", "/gma3/");
  const char expect[] = "/gma3/cmd\0\0\0,s\0\0Go+\0";
  CHECK(p == Bytes(expect, sizeof expect - 1));
}

static void TestRawMessage() {
  // "/13.13.1.6.1" "Flash" 1 -> ",si"
  auto p = CommandToOsc("/13.13.1.6.1 Flash 1", "ignored");
  std::vector<uint8_t> e;
  auto put = [&](const char* s, size_t n) { e.insert(e.end(), s, s + n); };
  put("/13.13.1.6.1\0\0\0\0", 16);
  put(",si\0", 4);
  put("Flash\0\0\0", 8);
  put("\0\0\0\1", 4);
  CHECK(p == e);

  auto q = CommandToOsc("/x \"a b\" 0.5", "");
  const char ex[] = "/x\0\0,sf\0a b\0\x3f\x00\x00\x00";
  CHECK(q == Bytes(ex, sizeof ex - 1));

  CHECK(CommandToOsc("   ", "").empty());
}

static void TestTemplates() {
  CHECK(ExpandTemplate("Go+ Sequence {seq} Cue {cue}", {{"seq", "5"}, {"cue", "3"}}) == "Go+ Sequence 5 Cue 3");
  CHECK(ExpandTemplate("{unknown} {seq", {{"seq", "5"}}) == "{unknown} {seq");
  CHECK(FirstNumber("page 12") == "12");
  CHECK(FirstNumber("page") == "");
  CHECK(QuoteForMa3("refrain \"1\"") == "\"refrain '1'\"");
}

static Schedule MakeSchedule(std::vector<double> times) {
  std::vector<ScheduledEvent> ev;
  for (double t : times) ev.push_back({t, {uint8_t(t * 10)}});
  return Schedule(std::move(ev));
}

static std::vector<size_t> Run(Dispatcher& d, const Schedule& s, double pos, double dur) {
  std::vector<size_t> out;
  d.Advance(s, pos, dur, [&](size_t i, double delay) {
    out.push_back(i);
    CHECK(delay >= 0 && delay < dur);
  });
  return out;
}

static void TestDispatcher() {
  Schedule s = MakeSchedule({1.0, 0.5, 2.0, 2.0});  // sorted to 0.5, 1.0, 2.0, 2.0
  CHECK(s.events()[0].time == 0.5);
  Dispatcher d;
  // Start at 0.9: the event at 0.5 is before the start and never sent.
  CHECK(Run(d, s, 0.9, 0.1).empty());
  CHECK((Run(d, s, 1.0, 0.1) == std::vector<size_t>{1}));
  // Contiguous blocks up to 2.0 send both events at 2.0 exactly once.
  std::vector<size_t> got;
  for (double p = 1.1; p < 2.5; p += 0.1) {
    auto r = Run(d, s, p, 0.1);
    got.insert(got.end(), r.begin(), r.end());
  }
  CHECK((got == std::vector<size_t>{2, 3}));
  // Seek back to 0.4: 0.5 plays again.
  CHECK((Run(d, s, 0.4, 0.2) == std::vector<size_t>{0}));
  // Jump forward over 1.0 (a seek): nothing sent for the skipped event.
  CHECK(Run(d, s, 1.5, 0.1).empty());
  // Reset then continue from a position between events.
  d.Reset();
  CHECK(Run(d, s, 1.95, 0.1).size() == 2);
}

int main() {
  TestEncodeCmd();
  TestPrefix();
  TestRawMessage();
  TestTemplates();
  TestDispatcher();
  if (g_failures) {
    std::printf("%d failure(s)\n", g_failures);
    return 1;
  }
  std::printf("all tests passed\n");
  return 0;
}
