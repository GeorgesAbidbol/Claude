// Unit tests for the REAPER-independent parts. Run with ctest.
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "osc.hpp"
#include "schedule.hpp"
#include "template.hpp"
#include "triggers.hpp"

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

static void TestTriggers() {
  const TriggerPreset* p = FindPreset(201);
  CHECK(p && p->target == Target::Button && p->ask == Ask::Executor);
  auto t = BuildTrigger(*p, "112");
  CHECK(t.on == "Press Executor 112");
  CHECK(t.off == "Unpress Executor 112");
  CHECK(t.description == "Bouton de l'executor 112 (page courante), tenu pendant la note");
  auto n = BuildTrigger(*FindPreset(202), "");
  CHECK(n.on == "Press Executor {note}");  // {note} stays for per-note expansion
  auto g = BuildTrigger(*FindPreset(102), "5");
  CHECK(g.on == "Goto Sequence 5 Cue {page}");
  CHECK(FindPreset(999) == nullptr);
  // Ids are unique and never collide with the menu's own entries (1, 2).
  for (const auto& a : TriggerPresets()) {
    CHECK(a.id > 2);
    int k = 0;
    for (const auto& b : TriggerPresets()) k += a.id == b.id;
    CHECK(k == 1);
  }
  // Every preset produces valid OSC.
  for (const auto& a : TriggerPresets()) {
    auto b = BuildTrigger(a, "201");
    CHECK(!CommandToOsc(ExpandTemplate(b.on, {{"page", "1"}, {"note", "36"}, {"velpct", "100"}}), "").empty());
  }
}

// Back-to-back notes on one key: the release of the first goes out before the
// press of the second, even when float rounding puts it a hair later.
static void TestReleaseBeforePress() {
  auto ev = [](double t, uint8_t tag, bool rel) { return ScheduledEvent{t, {tag}, rel}; };
  Schedule s({ev(1.0, 1, false), ev(2.0, 3, false), ev(2.0001, 2, true), ev(3.0, 4, true), ev(3.0, 5, false)});
  std::vector<uint8_t> order;
  for (const auto& e : s.events()) order.push_back(e.packet[0]);
  CHECK((order == std::vector<uint8_t>{1, 2, 3, 4, 5}));
  CHECK(s.events()[1].time == 2.0);
  // A real gap (1 ms) is left alone.
  Schedule g({ev(1.0, 1, false), ev(1.001, 2, true)});
  CHECK(g.events()[0].packet[0] == 1);
}

int main() {
  TestTriggers();
  TestReleaseBeforePress();
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
