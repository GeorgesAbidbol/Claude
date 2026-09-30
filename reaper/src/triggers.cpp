#include "triggers.hpp"

#include "template.hpp"

namespace ma3 {

// Sources (grandMA3 manual, "Remote Inputs > OSC"): "/cmd" runs a command line;
// "/13.13.1.6.<n>" with ",si,<key function>,1|0" presses/releases a sequence key;
// "/Page<p>/Key<e>" addresses an executor button; "FaderMaster Page 1.201 At 50" sets a fader.
const std::vector<TriggerPreset>& TriggerPresets() {
  static const std::vector<TriggerPreset> presets = {
      {101, Target::Sequence, "Go+", "Go+ Sequence {N}", ""},
      {102, Target::Sequence, "Goto la cue du numéro de page", "Goto Sequence {N} Cue {page}", ""},
      {103, Target::Sequence, "Flash pendant la note", "/13.13.1.6.{N} Flash 1", "/13.13.1.6.{N} Flash 0"},
      {104, Target::Sequence, "Temp pendant la note", "/13.13.1.6.{N} Temp 1", "/13.13.1.6.{N} Temp 0"},
      {105, Target::Sequence, "On pendant la note, puis Off", "On Sequence {N}", "Off Sequence {N}"},
      {106, Target::Sequence, "Toggle", "Toggle Sequence {N}", ""},
      {107, Target::Sequence, "Top", "Top Sequence {N}", ""},
      {201, Target::Executor, "Bouton appuyé pendant la note", "/Page{P}/Key{E} 1", "/Page{P}/Key{E} 0"},
      {202, Target::Executor, "Go+", "Go+ Page {P}.{E}", ""},
      {203, Target::Executor, "Fader à 100 % pendant la note", "FaderMaster Page {P}.{E} At 100",
       "FaderMaster Page {P}.{E} At 0"},
      {204, Target::Executor, "Fader à la vélocité pendant la note", "FaderMaster Page {P}.{E} At {velpct}",
       "FaderMaster Page {P}.{E} At 0"},
      {301, Target::Macro, "Go+", "Go+ Macro {N}", ""},
  };
  return presets;
}

const TriggerPreset* FindPreset(int id) {
  for (const auto& p : TriggerPresets())
    if (p.id == id) return &p;
  return nullptr;
}

const char* TargetLabel(Target t) {
  switch (t) {
    case Target::Sequence: return "Séquence";
    case Target::Executor: return "Executor";
    case Target::Macro: return "Macro";
  }
  return "";
}

TrackTrigger BuildTrigger(const TriggerPreset& p, const std::string& number, const std::string& page,
                          const std::string& exec) {
  const std::map<std::string, std::string> vars = {{"N", number}, {"P", page}, {"E", exec}};
  TrackTrigger t;
  t.on = ExpandTemplate(p.on, vars);
  t.off = ExpandTemplate(p.off, vars);
  t.description = std::string(TargetLabel(p.target)) + " " +
                  (p.target == Target::Executor ? page + "." + exec : number) + " : " + p.label;
  return t;
}

}  // namespace ma3
