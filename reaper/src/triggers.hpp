// Trigger presets offered in the track setup menu: what a MIDI note on an
// extras track should do on the grandMA3. Independent of REAPER (unit tested).
#pragma once

#include <string>
#include <vector>

namespace ma3 {

enum class Target { Sequence, Executor, Macro };

struct TriggerPreset {
  int id;             // menu command id, unique
  Target target;
  const char* label;  // menu text (French)
  const char* on;     // command at note start; {N} sequence/macro, {P} page, {E} executor
  const char* off;    // command at note end, or "" for none
};

const std::vector<TriggerPreset>& TriggerPresets();
const TriggerPreset* FindPreset(int id);
const char* TargetLabel(Target t);

struct TrackTrigger {
  std::string on, off, description;
};

// Fills {N}/{P}/{E} with the chosen numbers. Runtime variables such as {page}
// and {velpct} are kept for the extension to expand per note.
TrackTrigger BuildTrigger(const TriggerPreset& p, const std::string& number, const std::string& page,
                          const std::string& exec);

}  // namespace ma3
