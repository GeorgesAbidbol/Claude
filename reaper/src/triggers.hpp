// Trigger presets offered in the track setup menu: what a MIDI note on an
// extras track should do on the grandMA3. Independent of REAPER (unit tested).
#pragma once

#include <string>
#include <vector>

namespace ma3 {

// Where a preset sits in the menu: executor buttons first, the rest in submenus.
enum class Target { Button, Sequence, Macro };

// What the setup dialog asks after the menu choice.
enum class Ask { None, Executor, Number };

struct TriggerPreset {
  int id;             // menu command id, unique
  Target target;
  Ask ask;
  const char* label;  // menu text (French)
  const char* on;     // command at note start; {N} sequence/macro, {E} executor
  const char* off;    // command at note end, or "" for none
};

const std::vector<TriggerPreset>& TriggerPresets();
const TriggerPreset* FindPreset(int id);
const char* TargetLabel(Target t);

struct TrackTrigger {
  std::string on, off, description;
};

// Fills {N}/{E} with the chosen number. Runtime variables such as {note},
// {page} and {velpct} are kept for the extension to expand per note.
TrackTrigger BuildTrigger(const TriggerPreset& p, const std::string& number);

}  // namespace ma3
