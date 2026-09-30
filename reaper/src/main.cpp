// MA3 Tools: REAPER extension that sends OSC to a grandMA3 while the project plays.
// - Extras tracks: every MIDI note sends the track's note-on (and optional note-off) command.
// - Markers: each marker can send a Goto to the main cuelist, and a one-shot action labels
//   the cues of the main sequence with the marker names.

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "osc.hpp"
#include "schedule.hpp"
#include "sender.hpp"
#include "template.hpp"
#include "triggers.hpp"

// REAPER headers last: on Windows and with SWELL they define min/max macros.
#define NOMINMAX
#define REAPERAPI_IMPLEMENT
// Load only the functions we use, so older REAPER versions still accept the extension.
#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_Audio_RegHardwareHook
#define REAPERAPI_WANT_CountProjectMarkers
#define REAPERAPI_WANT_CountSelectedTracks
#define REAPERAPI_WANT_CountTrackMediaItems
#define REAPERAPI_WANT_CountTracks
#define REAPERAPI_WANT_EnumProjectMarkers3
#define REAPERAPI_WANT_GetActiveTake
#define REAPERAPI_WANT_GetExtState
#define REAPERAPI_WANT_GetMediaItemInfo_Value
#define REAPERAPI_WANT_GetMediaItemTake_Source
#define REAPERAPI_WANT_GetMediaSourceLength
#define REAPERAPI_WANT_GetOutputLatency
#define REAPERAPI_WANT_GetPlayPosition2Ex
#define REAPERAPI_WANT_GetPlayStateEx
#define REAPERAPI_WANT_GetProjectStateChangeCount
#define REAPERAPI_WANT_GetSelectedTrack
#define REAPERAPI_WANT_GetSetMediaItemTakeInfo_String
#define REAPERAPI_WANT_GetSetMediaTrackInfo_String
#define REAPERAPI_WANT_GetTrack
#define REAPERAPI_WANT_GetTrackMediaItem
#define REAPERAPI_WANT_GetTrackName
#define REAPERAPI_WANT_GetUserInputs
#define REAPERAPI_WANT_GetMainHwnd
#define REAPERAPI_WANT_MIDI_CountEvts
#define REAPERAPI_WANT_MIDI_GetNote
#define REAPERAPI_WANT_MIDI_GetPPQPosFromProjQN
#define REAPERAPI_WANT_MIDI_GetProjTimeFromPPQPos
#define REAPERAPI_WANT_SetExtState
#define REAPERAPI_WANT_ShowConsoleMsg
#define REAPERAPI_WANT_ShowMessageBox
#define REAPERAPI_WANT_TakeIsMIDI
#define REAPERAPI_WANT_TimeMap2_timeToQN
#include "reaper_plugin_functions.h"
#undef min
#undef max

using namespace ma3;

namespace {

const char* kSection = "MA3Tools";
const char* kTrackOn = "P_EXT:MA3Tools_on";
const char* kTrackOff = "P_EXT:MA3Tools_off";
const char* kTrackDesc = "P_EXT:MA3Tools_desc";
const char* kTitle = "MA3 Tools";

// ---------------------------------------------------------------- settings

struct Settings {
  std::string host = "127.0.0.1";
  int port = 8000;
  std::string prefix;
  double offset_ms = 0;
  bool enabled = false;
  bool markers_go = false;
  int markers_seq = 1;
  double markers_first_cue = 1;
  std::string markers_go_cmd = "Goto Sequence {seq} Cue {cue}";
  std::string markers_label_cmd = "Label Sequence {seq} Cue {cue} {qname}";
};

std::string GetStr(const char* key, const std::string& def) {
  const char* v = GetExtState(kSection, key);
  return v && *v ? std::string(v) : def;
}

void SetStr(const char* key, const std::string& v) { SetExtState(kSection, key, v.c_str(), true); }

std::string NumberToString(double v) {
  char buf[64];
  std::snprintf(buf, sizeof buf, "%g", v);
  return buf;
}

Settings LoadSettings() {
  Settings s;
  s.host = GetStr("host", s.host);
  s.port = std::atoi(GetStr("port", std::to_string(s.port)).c_str());
  s.prefix = GetStr("prefix", "");
  s.offset_ms = std::atof(GetStr("offset_ms", "0").c_str());
  s.enabled = GetStr("enabled", "0") == "1";
  s.markers_go = GetStr("markers_go", "0") == "1";
  s.markers_seq = std::atoi(GetStr("markers_seq", "1").c_str());
  s.markers_first_cue = std::atof(GetStr("markers_first_cue", "1").c_str());
  s.markers_go_cmd = GetStr("markers_go_cmd", s.markers_go_cmd);
  s.markers_label_cmd = GetStr("markers_label_cmd", s.markers_label_cmd);
  return s;
}

void SaveSettings(const Settings& s) {
  SetStr("host", s.host);
  SetStr("port", std::to_string(s.port));
  SetStr("prefix", s.prefix);
  SetStr("offset_ms", NumberToString(s.offset_ms));
  SetStr("enabled", s.enabled ? "1" : "0");
  SetStr("markers_go", s.markers_go ? "1" : "0");
  SetStr("markers_seq", std::to_string(s.markers_seq));
  SetStr("markers_first_cue", NumberToString(s.markers_first_cue));
  SetStr("markers_go_cmd", s.markers_go_cmd);
  SetStr("markers_label_cmd", s.markers_label_cmd);
}

// ---------------------------------------------------------------- state

Settings g_settings;
std::unique_ptr<Sender> g_sender;
std::atomic<Schedule*> g_schedule{nullptr};
struct Retired {
  Schedule* schedule;
  std::chrono::steady_clock::time_point at;
};
std::vector<Retired> g_retired;  // main thread only
std::atomic<bool> g_enabled{false};
std::atomic<double> g_delay_s{0};  // output latency + user offset
int g_last_state_count = -1;
bool g_was_playing = false;
Dispatcher g_dispatcher;           // audio thread only
Schedule* g_dispatch_schedule = nullptr;  // audio thread only

int g_cmd_settings, g_cmd_setup, g_cmd_track, g_cmd_markers, g_cmd_label, g_cmd_toggle, g_cmd_test, g_cmd_report;

// ---------------------------------------------------------------- schedule building

struct BuildStats {
  int note_events = 0;
  int marker_events = 0;
  int skipped = 0;  // commands that produced no packet
};

std::string TrackString(MediaTrack* tr, const char* key) {
  char buf[4096] = "";
  GetSetMediaTrackInfo_String(tr, key, buf, false);
  return buf;
}

void AddEvent(std::vector<ScheduledEvent>& out, double t, const std::string& cmd, int& counter,
              BuildStats& st, bool release = false) {
  auto pkt = CommandToOsc(cmd, g_settings.prefix);
  if (pkt.empty()) {
    ++st.skipped;
    return;
  }
  out.push_back({t, std::move(pkt), release});
  ++counter;
}

void AddTrackNotes(MediaTrack* tr, std::vector<ScheduledEvent>& out, BuildStats& st) {
  const std::string on_cmd = TrackString(tr, kTrackOn), off_cmd = TrackString(tr, kTrackOff);
  if (on_cmd.empty() && off_cmd.empty()) return;
  char tname[512] = "";
  GetTrackName(tr, tname, sizeof tname);

  for (int ii = 0; ii < CountTrackMediaItems(tr); ++ii) {
    MediaItem* item = GetTrackMediaItem(tr, ii);
    if (GetMediaItemInfo_Value(item, "B_MUTE") != 0) continue;
    MediaItem_Take* take = GetActiveTake(item);
    if (!take || !TakeIsMIDI(take)) continue;
    const double ipos = GetMediaItemInfo_Value(item, "D_POSITION");
    const double iend = ipos + GetMediaItemInfo_Value(item, "D_LENGTH");
    char takename[512] = "";
    GetSetMediaItemTakeInfo_String(take, "P_NAME", takename, false);

    // Looped items repeat their source: find the loop length in ticks.
    double loop_ticks = 0;
    if (GetMediaItemInfo_Value(item, "B_LOOPSRC") != 0) {
      bool is_qn = false;
      const double src_len = GetMediaSourceLength(GetMediaItemTake_Source(take), &is_qn);
      if (is_qn && src_len > 0) {
        const double q0 = TimeMap2_timeToQN(nullptr, ipos);
        const double ticks_per_qn = MIDI_GetPPQPosFromProjQN(take, q0 + 1) - MIDI_GetPPQPosFromProjQN(take, q0);
        loop_ticks = src_len * ticks_per_qn;
      }
    }

    int notes = 0;
    MIDI_CountEvts(take, &notes, nullptr, nullptr);
    for (int n = 0; n < notes; ++n) {
      bool sel = false, muted = false;
      double sppq = 0, eppq = 0;
      int chan = 0, pitch = 0, vel = 0;
      if (!MIDI_GetNote(take, n, &sel, &muted, &sppq, &eppq, &chan, &pitch, &vel) || muted) continue;
      const std::string page = FirstNumber(takename);
      const std::map<std::string, std::string> vars = {
          {"note", std::to_string(pitch)},
          {"vel", std::to_string(vel)},
          {"chan", std::to_string(chan + 1)},
          {"item", takename},
          {"page", page.empty() ? std::to_string(pitch) : page},
          {"track", tname},
          {"velpct", std::to_string((vel * 100 + 63) / 127)},
      };
      const std::string on = ExpandTemplate(on_cmd, vars), off = ExpandTemplate(off_cmd, vars);
      const int k_first = loop_ticks > 0 ? -2 : 0, k_last = loop_ticks > 0 ? 100000 : 0;
      for (int k = k_first; k <= k_last; ++k) {
        const double t_on = MIDI_GetProjTimeFromPPQPos(take, sppq + k * loop_ticks);
        if (t_on >= iend - 1e-9) break;
        if (t_on < ipos - 1e-9) continue;
        if (!on.empty()) AddEvent(out, t_on, on, st.note_events, st);
        if (!off.empty()) {
          double t_off = MIDI_GetProjTimeFromPPQPos(take, eppq + k * loop_ticks);
          if (t_off > iend) t_off = iend;
          // Hold at least 1 ms so the release never overtakes its own press.
          t_off = std::max(t_off, t_on + 2 * Schedule::kTie);
          AddEvent(out, t_off, off, st.note_events, st, true);
        }
      }
    }
  }
}

struct Marker {
  double pos;
  std::string name;
};

std::vector<Marker> ProjectMarkers() {
  std::vector<Marker> out;
  int nm = 0, nr = 0;
  CountProjectMarkers(nullptr, &nm, &nr);
  for (int i = 0; i < nm + nr; ++i) {
    bool isrgn = false;
    double pos = 0, end = 0;
    const char* name = nullptr;
    int idx = 0, color = 0;
    if (!EnumProjectMarkers3(nullptr, i, &isrgn, &pos, &end, &name, &idx, &color) || isrgn) continue;
    std::string nm_s = name ? name : "";
    while (!nm_s.empty() && nm_s.back() == ' ') nm_s.pop_back();
    out.push_back({pos, nm_s});
  }
  return out;
}

std::map<std::string, std::string> MarkerVars(size_t i, const Marker& m) {
  return {
      {"seq", std::to_string(g_settings.markers_seq)},
      {"cue", NumberToString(g_settings.markers_first_cue + double(i))},
      {"n", std::to_string(i + 1)},
      {"name", m.name},
      {"qname", QuoteForMa3(m.name)},
  };
}

std::unique_ptr<Schedule> BuildSchedule(BuildStats& st) {
  std::vector<ScheduledEvent> events;
  for (int ti = 0; ti < CountTracks(nullptr); ++ti) AddTrackNotes(GetTrack(nullptr, ti), events, st);
  if (g_settings.markers_go) {
    auto markers = ProjectMarkers();
    for (size_t i = 0; i < markers.size(); ++i)
      AddEvent(events, markers[i].pos, ExpandTemplate(g_settings.markers_go_cmd, MarkerVars(i, markers[i])),
               st.marker_events, st);
  }
  return std::make_unique<Schedule>(std::move(events));
}

void Rebuild() {
  BuildStats st;
  Schedule* fresh = BuildSchedule(st).release();
  Schedule* old = g_schedule.exchange(fresh);
  // The audio thread may still be walking the old schedule, and the sender may
  // still hold pointers to its packets: free it later.
  if (old) g_retired.push_back({old, std::chrono::steady_clock::now()});
}

void ApplyTarget() {
  if (!g_sender->SetTarget(g_settings.host, g_settings.port)) {
    char msg[512];
    std::snprintf(msg, sizeof msg, "Adresse de la console introuvable : %s:%d", g_settings.host.c_str(),
                  g_settings.port);
    ShowMessageBox(msg, kTitle, 0);
  }
}

void UpdateDelay() {
  // Clamped: queued packets must be sent long before their schedule is freed (10 s).
  const double offset_s = std::max(-2.0, std::min(2.0, g_settings.offset_ms / 1000.0));
  g_delay_s = GetOutputLatency() + offset_s;
}

// ---------------------------------------------------------------- audio thread

void OnAudioBuffer(bool is_post, int len, double srate, audio_hook_register_t*) {
  if (is_post || srate <= 0) return;
  const int state = GetPlayStateEx(nullptr);
  Schedule* s = g_schedule.load(std::memory_order_acquire);
  const bool playing = (state & 1) && !(state & 2);
  if (!g_enabled.load(std::memory_order_relaxed) || !playing || !s) {
    g_dispatcher.Reset();
    return;
  }
  if (s != g_dispatch_schedule) {
    g_dispatch_schedule = s;
    g_dispatcher.Reset();
  }
  const double pos = GetPlayPosition2Ex(nullptr);
  const auto now = Sender::Clock::now();
  const double base = g_delay_s.load(std::memory_order_relaxed);
  g_dispatcher.Advance(*s, pos, len / srate, [&](size_t i, double delay) {
    const auto due = now + std::chrono::duration_cast<Sender::Clock::duration>(
                               std::chrono::duration<double>(delay + base));
    g_sender->Enqueue(&s->events()[i].packet, due);
  });
}

audio_hook_register_t g_audio_hook = {OnAudioBuffer, nullptr, nullptr, 0, 0, nullptr};

// ---------------------------------------------------------------- main thread timer

void OnTimer() {
  const int count = GetProjectStateChangeCount(nullptr);
  const int state = GetPlayStateEx(nullptr);
  const bool playing = state & 1;
  if (count != g_last_state_count || (playing && !g_was_playing)) {
    g_last_state_count = count;
    UpdateDelay();
    Rebuild();
  }
  g_was_playing = playing;

  const auto now = std::chrono::steady_clock::now();
  for (size_t i = 0; i < g_retired.size();) {
    if (now - g_retired[i].at > std::chrono::seconds(10)) {
      delete g_retired[i].schedule;
      g_retired.erase(g_retired.begin() + long(i));
    } else {
      ++i;
    }
  }
}

// ---------------------------------------------------------------- actions

// Dialogs use '|' between fields (GetUserInputs "separator=|"), so commands may contain commas.
std::vector<std::string> SplitFields(const char* s, size_t n) {
  std::vector<std::string> out(1);
  for (const char* p = s; *p; ++p) {
    if (*p == '|' && out.size() < n) out.emplace_back();
    else out.back() += *p;
  }
  while (out.size() < n) out.emplace_back();
  return out;
}

bool YesNo(const std::string& s) { return !s.empty() && (s[0] == 'o' || s[0] == 'O' || s[0] == 'y' || s[0] == 'Y' || s[0] == '1'); }

void ActionSettings() {
  char buf[4096];
  std::snprintf(buf, sizeof buf, "%s|%d|%s|%s|%s", g_settings.host.c_str(), g_settings.port,
                g_settings.prefix.c_str(), NumberToString(g_settings.offset_ms).c_str(),
                g_settings.enabled ? "o" : "n");
  if (!GetUserInputs("MA3 Tools : réglages de la console", 5,
                     "IP de la console,Port OSC,Préfixe OSC (vide = aucun),Décalage (ms, -2000 à 2000),Envoi actif (o/n),separator=|,extrawidth=120",
                     buf, sizeof buf))
    return;
  auto v = SplitFields(buf, 5);
  g_settings.host = v[0];
  g_settings.port = std::atoi(v[1].c_str());
  g_settings.prefix = v[2];
  g_settings.offset_ms = std::atof(v[3].c_str());
  g_settings.enabled = YesNo(v[4]);
  g_enabled = g_settings.enabled;
  SaveSettings(g_settings);
  ApplyTarget();
  UpdateDelay();
  Rebuild();
}

void SetSelectedTracksTrigger(const std::string& on, const std::string& off, const std::string& desc) {
  for (int i = 0; i < CountSelectedTracks(nullptr); ++i) {
    MediaTrack* tr = GetSelectedTrack(nullptr, i);
    GetSetMediaTrackInfo_String(tr, kTrackOn, const_cast<char*>(on.c_str()), true);
    GetSetMediaTrackInfo_String(tr, kTrackOff, const_cast<char*>(off.c_str()), true);
    GetSetMediaTrackInfo_String(tr, kTrackDesc, const_cast<char*>(desc.c_str()), true);
  }
  Rebuild();
}

bool RequireSelectedTracks() {
  if (CountSelectedTracks(nullptr) > 0) return true;
  ShowMessageBox("Sélectionnez d'abord la ou les pistes d'extras.", kTitle, 0);
  return false;
}

void ActionTrackCommands() {
  if (!RequireSelectedTracks()) return;
  MediaTrack* first = GetSelectedTrack(nullptr, 0);
  std::string on = TrackString(first, kTrackOn), off = TrackString(first, kTrackOff);
  char buf[4096];
  std::snprintf(buf, sizeof buf, "%s|%s", on.c_str(), off.c_str());
  if (!GetUserInputs("MA3 Tools : commande des pistes sélectionnées", 2,
                     "Début de note (ex. Go+ Sequence 12),Fin de note (vide = rien),separator=|,extrawidth=260", buf, sizeof buf))
    return;
  auto v = SplitFields(buf, 2);
  SetSelectedTracksTrigger(v[0], v[1], v[0].empty() && v[1].empty() ? "" : "Commande libre");
}

const int kMenuFree = 1, kMenuNone = 2;

// Menu text is UTF-8. Windows menus need UTF-16 for the accents to show.
void AddMenuItem(HMENU menu, int pos, unsigned int flags, UINT_PTR id, const char* text) {
#ifdef _WIN32
  if (text) {
    wchar_t wide[512];
    if (MultiByteToWideChar(CP_UTF8, 0, text, -1, wide, 512) > 0) {
      InsertMenuW(menu, pos, flags, id, wide);
      return;
    }
  }
#endif
  InsertMenu(menu, pos, flags, id, text);
}

// Setup popup: choose what a note does on the console, then the target number.
void ActionTrackSetup() {
  if (!RequireSelectedTracks()) return;
  const std::string current = TrackString(GetSelectedTrack(nullptr, 0), kTrackDesc);

  HMENU menu = CreatePopupMenu();
  int pos = 0;
  if (!current.empty()) {
    AddMenuItem(menu, pos++, MF_BYPOSITION | MF_STRING | MF_GRAYED, 0, ("Actuel : " + current).c_str());
    AddMenuItem(menu, pos++, MF_BYPOSITION | MF_SEPARATOR, 0, nullptr);
  }
  // Executor buttons first (the key does what it is set to on the console),
  // then the other targets in submenus.
  for (const auto& p : TriggerPresets())
    if (p.target == Target::Button) AddMenuItem(menu, pos++, MF_BYPOSITION | MF_STRING, p.id, p.label);
  AddMenuItem(menu, pos++, MF_BYPOSITION | MF_SEPARATOR, 0, nullptr);
  for (Target t : {Target::Sequence, Target::Macro}) {
    HMENU sub = CreatePopupMenu();
    int spos = 0;
    for (const auto& p : TriggerPresets())
      if (p.target == t) AddMenuItem(sub, spos++, MF_BYPOSITION | MF_STRING, p.id, p.label);
    AddMenuItem(menu, pos++, MF_BYPOSITION | MF_POPUP | MF_STRING, (UINT_PTR)sub, TargetLabel(t));
  }
  AddMenuItem(menu, pos++, MF_BYPOSITION | MF_SEPARATOR, 0, nullptr);
  AddMenuItem(menu, pos++, MF_BYPOSITION | MF_STRING, kMenuFree, "Commande libre...");
  AddMenuItem(menu, pos++, MF_BYPOSITION | MF_STRING, kMenuNone, "Ne rien envoyer");
  POINT pt;
  GetCursorPos(&pt);
  const int choice = TrackPopupMenu(menu, TPM_NONOTIFY | TPM_RETURNCMD, pt.x, pt.y, 0, GetMainHwnd(), nullptr);
  DestroyMenu(menu);  // also destroys the submenus

  if (choice == kMenuFree) return ActionTrackCommands();
  if (choice == kMenuNone) return SetSelectedTracksTrigger("", "", "");
  const TriggerPreset* preset = FindPreset(choice);
  if (!preset) return;  // menu closed

  std::string number;
  if (preset->ask != Ask::None) {
    char buf[256] = "";
    const char* cap = preset->ask == Ask::Executor ? "Numéro d'executor (ex. 201)"
                      : preset->target == Target::Macro ? "Numéro de macro"
                                                        : "Numéro de séquence";
    std::snprintf(buf, sizeof buf, "%s", preset->ask == Ask::Executor ? "201" : "1");
    if (!GetUserInputs("MA3 Tools : cible", 1, cap, buf, sizeof buf)) return;
    number = buf;
    while (!number.empty() && number.back() == ' ') number.pop_back();
    while (!number.empty() && number.front() == ' ') number.erase(0, 1);
    if (number.empty()) return;
  }
  auto t = BuildTrigger(*preset, number);
  SetSelectedTracksTrigger(t.on, t.off, t.description);
}

void ActionMarkerSettings() {
  char buf[4096];
  std::snprintf(buf, sizeof buf, "%s|%d|%s|%s|%s", g_settings.markers_go ? "o" : "n", g_settings.markers_seq,
                NumberToString(g_settings.markers_first_cue).c_str(), g_settings.markers_go_cmd.c_str(),
                g_settings.markers_label_cmd.c_str());
  if (!GetUserInputs("MA3 Tools : cuelist principale (marqueurs)", 5,
                     "Envoyer une cue à chaque marqueur (o/n),Séquence principale,Numéro de la 1re cue,"
                     "Commande au passage,Commande pour nommer,separator=|,extrawidth=260",
                     buf, sizeof buf))
    return;
  auto v = SplitFields(buf, 5);
  g_settings.markers_go = YesNo(v[0]);
  g_settings.markers_seq = std::atoi(v[1].c_str());
  g_settings.markers_first_cue = std::atof(v[2].c_str());
  if (!v[3].empty()) g_settings.markers_go_cmd = v[3];
  if (!v[4].empty()) g_settings.markers_label_cmd = v[4];
  SaveSettings(g_settings);
  Rebuild();
}

void ActionLabelCues() {
  auto markers = ProjectMarkers();
  if (markers.empty()) {
    ShowMessageBox("Aucun marqueur dans le projet.", kTitle, 0);
    return;
  }
  char msg[1024];
  std::snprintf(msg, sizeof msg,
                "Envoyer %d commandes à la console %s:%d ?\n\nExemple : %s\n\n"
                "Les cues doivent exister dans la séquence %d.",
                int(markers.size()), g_settings.host.c_str(), g_settings.port,
                ExpandTemplate(g_settings.markers_label_cmd, MarkerVars(0, markers[0])).c_str(),
                g_settings.markers_seq);
  if (ShowMessageBox(msg, kTitle, 1) != 1) return;  // 1 = OK
  int ok = 0;
  for (size_t i = 0; i < markers.size(); ++i) {
    auto pkt = CommandToOsc(ExpandTemplate(g_settings.markers_label_cmd, MarkerVars(i, markers[i])), g_settings.prefix);
    if (!pkt.empty() && g_sender->SendNow(pkt)) ++ok;
  }
  std::snprintf(msg, sizeof msg, "%d commande(s) envoyée(s) sur %d.", ok, int(markers.size()));
  ShowMessageBox(msg, kTitle, 0);
}

void ActionToggle() {
  g_settings.enabled = !g_settings.enabled;
  g_enabled = g_settings.enabled;
  SaveSettings(g_settings);
}

void ActionTest() {
  char buf[4096] = "Go+ Sequence 1";
  if (!GetUserInputs("MA3 Tools : envoyer une commande de test", 1, "Commande ou /adresse arguments,separator=|,extrawidth=260", buf,
                     sizeof buf))
    return;
  auto pkt = CommandToOsc(buf, g_settings.prefix);
  ShowMessageBox(!pkt.empty() && g_sender->SendNow(pkt) ? "Envoyé." : "Échec de l'envoi.", kTitle, 0);
}

void ActionReport() {
  BuildStats st;
  auto s = BuildSchedule(st);
  std::string out = "MA3 Tools : ";
  out += g_settings.enabled ? "envoi ACTIF" : "envoi INACTIF";
  out += " vers " + g_settings.host + ":" + std::to_string(g_settings.port) + "\n";
  out += std::to_string(st.note_events) + " message(s) de notes, " + std::to_string(st.marker_events) +
         " message(s) de marqueurs";
  if (st.skipped) out += ", " + std::to_string(st.skipped) + " commande(s) vide(s) ignorée(s)";
  out += "\nEnvoyés depuis le chargement : " + std::to_string(g_sender->sent()) +
         ", perdus : " + std::to_string(g_sender->dropped()) + "\n";
  for (int ti = 0; ti < CountTracks(nullptr); ++ti) {
    MediaTrack* tr = GetTrack(nullptr, ti);
    std::string on = TrackString(tr, kTrackOn), off = TrackString(tr, kTrackOff);
    if (on.empty() && off.empty()) continue;
    char name[512] = "";
    GetTrackName(tr, name, sizeof name);
    const std::string desc = TrackString(tr, kTrackDesc);
    out += "  " + std::string(name) + (desc.empty() ? "" : " (" + desc + ")") + " : début = [" + on + "]";
    if (!off.empty()) out += ", fin = [" + off + "]";
    out += "\n";
  }
  ShowConsoleMsg((out + "\n").c_str());
}

bool OnAction(KbdSectionInfo*, int cmd, int, int, int, HWND) {
  if (cmd == g_cmd_settings) ActionSettings();
  else if (cmd == g_cmd_setup) ActionTrackSetup();
  else if (cmd == g_cmd_track) ActionTrackCommands();
  else if (cmd == g_cmd_markers) ActionMarkerSettings();
  else if (cmd == g_cmd_label) ActionLabelCues();
  else if (cmd == g_cmd_toggle) ActionToggle();
  else if (cmd == g_cmd_test) ActionTest();
  else if (cmd == g_cmd_report) ActionReport();
  else return false;
  return true;
}

int ToggleState(int cmd) {
  if (cmd == g_cmd_toggle) return g_settings.enabled ? 1 : 0;
  return -1;
}

int RegisterAction(reaper_plugin_info_t* rec, const char* id, const char* name) {
  custom_action_register_t ca = {0, id, name, nullptr};
  return rec->Register("custom_action", &ca);
}

}  // namespace

extern "C" REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE, reaper_plugin_info_t* rec) {
  if (!rec) {  // unload
    Audio_RegHardwareHook(false, &g_audio_hook);
    g_sender.reset();
    delete g_schedule.exchange(nullptr);
    for (auto& r : g_retired) delete r.schedule;
    g_retired.clear();
    return 0;
  }
  if (rec->caller_version != REAPER_PLUGIN_VERSION || REAPERAPI_LoadAPI(rec->GetFunc) != 0) return 0;

  g_settings = LoadSettings();
  g_enabled = g_settings.enabled;
  g_sender = std::make_unique<Sender>();
  g_sender->SetTarget(g_settings.host, g_settings.port);

  g_cmd_settings = RegisterAction(rec, "MA3TOOLS_SETTINGS", "MA3 Tools : réglages de la console (IP, port, envoi)");
  g_cmd_setup = RegisterAction(rec, "MA3TOOLS_TRACK_SETUP", "MA3 Tools : régler le déclenchement des pistes sélectionnées");
  g_cmd_track = RegisterAction(rec, "MA3TOOLS_TRACK_CMD", "MA3 Tools : commande libre des pistes sélectionnées");
  g_cmd_markers = RegisterAction(rec, "MA3TOOLS_MARKERS", "MA3 Tools : réglages de la cuelist principale (marqueurs)");
  g_cmd_label = RegisterAction(rec, "MA3TOOLS_LABEL", "MA3 Tools : nommer les cues avec les noms des marqueurs");
  g_cmd_toggle = RegisterAction(rec, "MA3TOOLS_TOGGLE", "MA3 Tools : activer/désactiver l'envoi");
  g_cmd_test = RegisterAction(rec, "MA3TOOLS_TEST", "MA3 Tools : envoyer une commande de test");
  g_cmd_report = RegisterAction(rec, "MA3TOOLS_REPORT", "MA3 Tools : afficher le résumé dans la console REAPER");

  rec->Register("hookcommand2", (void*)OnAction);
  rec->Register("toggleaction", (void*)ToggleState);
  rec->Register("timer", (void*)OnTimer);
  rec->Register("ext_name", (void*)"MA3 Tools");
  Audio_RegHardwareHook(true, &g_audio_hook);
  return 1;
}
