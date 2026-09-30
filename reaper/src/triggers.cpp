#include "triggers.hpp"

#include "template.hpp"

namespace ma3 {

// Sources (grandMA3 manual): keywords "Press" / "Unpress" simulate holding and
// releasing a key, and run whatever the executor's key is set to (Flash, Temp,
// Go+...). "Executor 201" without a page means the current page. "/cmd" runs a
// command line; "/13.13.1.6.<n>" with ",si,<key function>,1|0" presses a sequence key.
const std::vector<TriggerPreset>& TriggerPresets() {
  static const std::vector<TriggerPreset> presets = {
      {201, Target::Button, Ask::Executor, "Bouton d'un executor (page courante)...", "Press Executor {E}",
       "Unpress Executor {E}"},
      {202, Target::Button, Ask::None, "Bouton de l'executor = numéro de la note", "Press Executor {note}",
       "Unpress Executor {note}"},
      {101, Target::Sequence, Ask::Number, "Go+", "Go+ Sequence {N}", ""},
      {102, Target::Sequence, Ask::Number, "Goto la cue du numéro de page", "Goto Sequence {N} Cue {page}", ""},
      {103, Target::Sequence, Ask::Number, "Flash pendant la note", "/13.13.1.6.{N} Flash 1", "/13.13.1.6.{N} Flash 0"},
      {104, Target::Sequence, Ask::Number, "Temp pendant la note", "/13.13.1.6.{N} Temp 1", "/13.13.1.6.{N} Temp 0"},
      {105, Target::Sequence, Ask::Number, "On pendant la note, puis Off", "On Sequence {N}", "Off Sequence {N}"},
      {106, Target::Sequence, Ask::Number, "Toggle", "Toggle Sequence {N}", ""},
      {107, Target::Sequence, Ask::Number, "Top", "Top Sequence {N}", ""},
      {301, Target::Macro, Ask::Number, "Go+", "Go+ Macro {N}", ""},
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
    case Target::Button: return "Bouton";
    case Target::Sequence: return "Séquence";
    case Target::Macro: return "Macro";
  }
  return "";
}

TrackTrigger BuildTrigger(const TriggerPreset& p, const std::string& number) {
  const std::map<std::string, std::string> vars = {{"N", number}, {"E", number}};
  TrackTrigger t;
  t.on = ExpandTemplate(p.on, vars);
  t.off = ExpandTemplate(p.off, vars);
  switch (p.ask) {
    case Ask::Executor: t.description = "Bouton de l'executor " + number + " (page courante), tenu pendant la note"; break;
    case Ask::None: t.description = std::string(p.label) + ", tenu pendant la note"; break;
    case Ask::Number: t.description = std::string(TargetLabel(p.target)) + " " + number + " : " + p.label; break;
  }
  return t;
}

}  // namespace ma3
