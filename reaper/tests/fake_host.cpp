// End-to-end test: loads the built extension with a fake REAPER API, plays a
// small fake project in real time and lets the extension send OSC over UDP.
// A Python listener (tests/e2e.py) checks what arrives.
#include <dlfcn.h>

#include <chrono>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <thread>
#include <vector>

#define NOMINMAX
#include "reaper_plugin.h"

struct Note { double sppq, eppq; int pitch; };
struct Item { double pos, len; bool loop; double src_qn; std::string name; std::vector<Note> notes; };
struct Track { std::string name; std::map<std::string, std::string> ext; std::vector<Item> items; };
struct Marker { double pos; std::string name; };

static std::vector<Track> g_tracks;
static std::vector<Marker> g_markers;
static std::map<std::string, std::string> g_extstate;
static int g_playstate = 0;
static double g_playpos = 0;
static audio_hook_register_t* g_hook = nullptr;
static bool (*g_onaction)(KbdSectionInfo*, int, int, int, int, HWND) = nullptr;
static void (*g_timer)() = nullptr;
static std::map<std::string, int> g_actions;
static int g_next_cmd = 40000;

// 120 BPM: 1 QN = 0.5 s, 960 ticks per QN, ticks measured from the item start.
static const double kQN = 0.5, kPPQ = 960;
static Item* ItemOf(void* take) { return static_cast<Item*>(take); }

extern "C" {
static const char* GetExtState(const char* s, const char* k) {
  auto it = g_extstate.find(std::string(s) + "/" + k);
  return it == g_extstate.end() ? "" : it->second.c_str();
}
static void SetExtState(const char* s, const char* k, const char* v, bool) { g_extstate[std::string(s) + "/" + k] = v; }
static bool GetSetMediaTrackInfo_String(MediaTrack* tr, const char* parm, char* buf, bool set) {
  auto* t = reinterpret_cast<Track*>(tr);
  if (set) t->ext[parm] = buf; else std::strcpy(buf, t->ext[parm].c_str());
  return true;
}
static int CountTracks(ReaProject*) { return int(g_tracks.size()); }
static MediaTrack* GetTrack(ReaProject*, int i) { return reinterpret_cast<MediaTrack*>(&g_tracks[i]); }
static int CountTrackMediaItems(MediaTrack* tr) { return int(reinterpret_cast<Track*>(tr)->items.size()); }
static MediaItem* GetTrackMediaItem(MediaTrack* tr, int i) { return reinterpret_cast<MediaItem*>(&reinterpret_cast<Track*>(tr)->items[i]); }
static double GetMediaItemInfo_Value(MediaItem* it, const char* p) {
  auto* i = reinterpret_cast<Item*>(it);
  if (!std::strcmp(p, "D_POSITION")) return i->pos;
  if (!std::strcmp(p, "D_LENGTH")) return i->len;
  if (!std::strcmp(p, "B_LOOPSRC")) return i->loop;
  return 0;
}
static MediaItem_Take* GetActiveTake(MediaItem* it) { return reinterpret_cast<MediaItem_Take*>(it); }
static bool TakeIsMIDI(MediaItem_Take*) { return true; }
static int MIDI_CountEvts(MediaItem_Take* tk, int* n, int*, int*) { *n = int(ItemOf(tk)->notes.size()); return *n; }
static bool MIDI_GetNote(MediaItem_Take* tk, int i, bool* sel, bool* mut, double* s, double* e, int* ch, int* p, int* v) {
  const Note& n = ItemOf(tk)->notes[i];
  *sel = false; *mut = false; *s = n.sppq; *e = n.eppq; *ch = 0; *p = n.pitch; *v = 127;
  return true;
}
static double MIDI_GetProjTimeFromPPQPos(MediaItem_Take* tk, double ppq) { return ItemOf(tk)->pos + ppq / kPPQ * kQN; }
static double MIDI_GetPPQPosFromProjQN(MediaItem_Take* tk, double qn) { return (qn * kQN - ItemOf(tk)->pos) / kQN * kPPQ; }
static PCM_source* GetMediaItemTake_Source(MediaItem_Take* tk) { return reinterpret_cast<PCM_source*>(tk); }
static double GetMediaSourceLength(PCM_source* src, bool* qn) { *qn = true; return reinterpret_cast<Item*>(src)->src_qn; }
static bool GetSetMediaItemTakeInfo_String(MediaItem_Take* tk, const char*, char* buf, bool) { std::strcpy(buf, ItemOf(tk)->name.c_str()); return true; }
static int CountProjectMarkers(ReaProject*, int* nm, int* nr) { *nm = int(g_markers.size()); *nr = 0; return *nm; }
static int EnumProjectMarkers3(ReaProject*, int i, bool* rgn, double* pos, double* end, const char** name, int* idx, int* col) {
  if (i >= int(g_markers.size())) return 0;
  *rgn = false; *pos = g_markers[i].pos; *end = 0; *name = g_markers[i].name.c_str(); *idx = i + 1; *col = 0;
  return i + 1;
}
static int GetPlayStateEx(ReaProject*) { return g_playstate; }
static double GetPlayPosition2Ex(ReaProject*) { return g_playpos; }
static int GetProjectStateChangeCount(ReaProject*) { return 1; }
static double GetOutputLatency() { return 0.0; }
static int Audio_RegHardwareHook(bool add, audio_hook_register_t* r) { g_hook = add ? r : nullptr; return 1; }
static void ShowConsoleMsg(const char* m) { std::fputs(m, stdout); }
static bool GetTrackName(MediaTrack* tr, char* buf, int) { std::strcpy(buf, reinterpret_cast<Track*>(tr)->name.c_str()); return true; }
static double TimeMap2_timeToQN(ReaProject*, double t) { return t / kQN; }
static std::vector<std::string> g_inputs;  // scripted answers for GetUserInputs
static bool GetUserInputs(const char*, int, const char*, char* buf, int sz) {
  if (g_inputs.empty()) return false;
  std::snprintf(buf, size_t(sz), "%s", g_inputs.front().c_str());
  g_inputs.erase(g_inputs.begin());
  return true;
}
static int ShowMessageBox(const char* msg, const char*, int) { std::printf("[message] %s\n", msg); return 1; }
static Track* g_selected = nullptr;
static int CountSelectedTracks(ReaProject*) { return g_selected ? 1 : 0; }
static MediaTrack* GetSelectedTrack(ReaProject*, int) { return reinterpret_cast<MediaTrack*>(g_selected); }
static HWND GetMainHwnd() { return nullptr; }

// Fake SWELL menus: TrackPopupMenu returns the scripted command id if the menu
// (or a submenu) really contains it, else 0 (menu closed).
struct FakeMenu { std::vector<std::pair<unsigned long, FakeMenu*>> items; std::vector<std::string> labels; };
static int g_menu_choice = 0;
static std::vector<std::string> g_menu_labels;
static HMENU Fake_CreatePopupMenu() { return reinterpret_cast<HMENU>(new FakeMenu); }
static void Fake_SWELL_InsertMenu(HMENU m, int, unsigned int flag, UINT_PTR idx, const char* str) {
  auto* fm = reinterpret_cast<FakeMenu*>(m);
  fm->items.push_back({(unsigned long)idx, (flag & MF_POPUP) ? reinterpret_cast<FakeMenu*>(idx) : nullptr});
  fm->labels.push_back(str ? str : "");
}
static bool MenuHas(FakeMenu* m, int id) {
  for (size_t i = 0; i < m->items.size(); ++i) {
    g_menu_labels.push_back(m->labels[i]);
    if (m->items[i].second ? MenuHas(m->items[i].second, id) : int(m->items[i].first) == id) return true;
  }
  return false;
}
static int Fake_TrackPopupMenu(HMENU m, int, int, int, int, HWND, const RECT*) {
  g_menu_labels.clear();
  return MenuHas(reinterpret_cast<FakeMenu*>(m), g_menu_choice) ? g_menu_choice : 0;
}
static void Fake_DestroyMenu(HMENU) {}
static void Fake_GetCursorPos(POINT* pt) { pt->x = pt->y = 0; }
}

static std::map<std::string, void*> g_funcs = {
#define F(x) {#x, (void*)x}
    F(GetExtState), F(SetExtState), F(GetSetMediaTrackInfo_String), F(CountTracks), F(GetTrack),
    F(CountTrackMediaItems), F(GetTrackMediaItem), F(GetMediaItemInfo_Value), F(GetActiveTake), F(TakeIsMIDI),
    F(MIDI_CountEvts), F(MIDI_GetNote), F(MIDI_GetProjTimeFromPPQPos), F(MIDI_GetPPQPosFromProjQN),
    F(GetMediaItemTake_Source), F(GetMediaSourceLength), F(GetSetMediaItemTakeInfo_String), F(CountProjectMarkers),
    F(EnumProjectMarkers3), F(GetPlayStateEx), F(GetPlayPosition2Ex), F(GetProjectStateChangeCount),
    F(GetOutputLatency), F(Audio_RegHardwareHook), F(ShowConsoleMsg), F(GetTrackName), F(TimeMap2_timeToQN),
    F(GetUserInputs), F(ShowMessageBox), F(CountSelectedTracks), F(GetSelectedTrack), F(GetMainHwnd),
#undef F
};

static std::map<std::string, void*> g_swell_funcs = {
    {"CreatePopupMenu", (void*)Fake_CreatePopupMenu}, {"SWELL_InsertMenu", (void*)Fake_SWELL_InsertMenu},
    {"TrackPopupMenu", (void*)Fake_TrackPopupMenu}, {"DestroyMenu", (void*)Fake_DestroyMenu},
    {"GetCursorPos", (void*)Fake_GetCursorPos},
};
static void* GetSwellFunc(const char* name) {
  auto it = g_swell_funcs.find(name ? name : "");
  return it == g_swell_funcs.end() ? nullptr : it->second;
}

static void* GetFunc(const char* name) {
  auto it = g_funcs.find(name);
  if (it == g_funcs.end()) std::printf("[host] missing function %s\n", name);
  return it == g_funcs.end() ? nullptr : it->second;
}

static int Register(const char* name, void* info) {
  std::string n = name;
  if (n == "custom_action") {
    auto* ca = static_cast<custom_action_register_t*>(info);
    g_actions[ca->idStr] = ++g_next_cmd;
    return g_next_cmd;
  }
  if (n == "hookcommand2") g_onaction = (bool (*)(KbdSectionInfo*, int, int, int, int, HWND))info;
  if (n == "timer") g_timer = (void (*)())info;
  return 1;
}

// Plays [from, to) in real time with 256-sample blocks at 48 kHz.
static void Play(double from, double to) {
  const double block = 256.0 / 48000.0;
  g_playstate = 1;
  g_timer();
  auto start = std::chrono::steady_clock::now();
  int n = 0;
  for (double p = from; p < to; p += block, ++n) {
    g_playpos = p;
    g_hook->OnAudioBuffer(false, 256, 48000, g_hook);
    g_hook->OnAudioBuffer(true, 256, 48000, g_hook);
    if (n % 40 == 0) g_timer();
    std::this_thread::sleep_until(start + std::chrono::duration<double>((n + 1) * block));
  }
}

int main(int argc, char** argv) {
  if (argc < 3) { std::printf("usage: fake_host extension.so port\n"); return 2; }
  const std::string port = argv[2];
  g_extstate = {{"MA3Tools/host", "127.0.0.1"}, {"MA3Tools/port", port}, {"MA3Tools/enabled", "1"},
                {"MA3Tools/markers_go", "1"}, {"MA3Tools/markers_seq", "1"}, {"MA3Tools/markers_first_cue", "1"}};

  Track kick{"extra 1 kick", {{"P_EXT:MA3Tools_on", "Go+ Sequence 12"}}, {}};
  kick.items.push_back({0.5, 0.1, false, 0, "page 2", {{0, 96, 1}}});
  kick.items.push_back({1.0, 0.1, false, 0, "page 2", {{0, 96, 1}}});
  // Looped item: 1 QN source with one note, item lasts 2 QN -> hits at 2.0 and 2.5.
  kick.items.push_back({2.0, 1.0, true, 1.0, "page 2", {{0, 96, 1}}});
  Track snare{"extra 4 snare", {{"P_EXT:MA3Tools_on", "/13.13.1.6.5 Flash 1"}, {"P_EXT:MA3Tools_off", "/13.13.1.6.5 Flash 0"}}, {}};
  snare.items.push_back({0.75, 0.25, false, 0, "page 5", {{0, 240, 1}}});  // on 0.75, off 0.875
  Track plain{"AUDIO", {}, {{0, 3, false, 0, "x", {{0, 10, 60}}}}};         // no command: ignored
  g_tracks = {kick, snare, plain};
  g_markers = {{0.25, "intro"}, {1.5, "refrain \"1\""}};

  void* lib = dlopen(argv[1], RTLD_NOW);
  if (!lib) { std::printf("dlopen: %s\n", dlerror()); return 2; }
#ifdef __linux__
  // REAPER hands its SWELL functions to extensions through SWELL_dllMain (Linux).
  auto swell_main = (int (*)(HINSTANCE, DWORD, LPVOID))dlsym(lib, "SWELL_dllMain");
  if (swell_main) {
    std::fflush(stdout);
    FILE* keep = stdout;
    stdout = std::fopen("/dev/null", "w");  // silence "SWELL API not found" for the ones we don't fake
    swell_main(nullptr, DLL_PROCESS_ATTACH, (LPVOID)GetSwellFunc);
    std::fclose(stdout);
    stdout = keep;
  }
#endif
  auto entry = (int (*)(REAPER_PLUGIN_HINSTANCE, reaper_plugin_info_t*))dlsym(lib, "ReaperPluginEntry");
  reaper_plugin_info_t rec{};
  rec.caller_version = REAPER_PLUGIN_VERSION;
  rec.Register = Register;
  rec.GetFunc = GetFunc;
  if (!entry || entry(nullptr, &rec) != 1) { std::printf("[host] extension refused to load\n"); return 1; }
  std::printf("[host] loaded, %d actions\n", int(g_actions.size()));

  std::printf("[host] PLAY 0.0 -> 1.2\n");
  Play(0.0, 1.2);
  std::printf("[host] SEEK back, PLAY 0.9 -> 3.2\n");
  Play(0.9, 3.2);
  g_playstate = 0;
  g_hook->OnAudioBuffer(false, 256, 48000, g_hook);
  std::this_thread::sleep_for(std::chrono::milliseconds(200));

  std::printf("[host] action: label cues\n");
  g_onaction(nullptr, g_actions["MA3TOOLS_LABEL"], 0, 0, 0, nullptr);
  std::printf("[host] action: report\n");
  g_onaction(nullptr, g_actions["MA3TOOLS_REPORT"], 0, 0, 0, nullptr);
  std::this_thread::sleep_for(std::chrono::milliseconds(200));

  int failures = 0;
#ifdef __linux__
  // Setup menu: pick a preset, answer the number dialog, check what the track stores.
  auto setup = [&](int choice, std::vector<std::string> answers) {
    g_menu_choice = choice;
    g_inputs = answers;
    g_onaction(nullptr, g_actions["MA3TOOLS_TRACK_SETUP"], 0, 0, 0, nullptr);
    return std::make_pair(g_selected->ext["P_EXT:MA3Tools_on"], g_selected->ext["P_EXT:MA3Tools_off"]);
  };
  auto expect = [&](std::pair<std::string, std::string> got, const char* on, const char* off) {
    const bool ok = got.first == on && got.second == off;
    std::printf("[host] setup -> on=[%s] off=[%s] %s\n", got.first.c_str(), got.second.c_str(), ok ? "OK" : "MISMATCH");
    if (!ok) ++failures;
  };
  g_selected = &g_tracks[0];
  expect(setup(103, {"7"}), "/13.13.1.6.7 Flash 1", "/13.13.1.6.7 Flash 0");
  expect(setup(203, {"2|205"}), "FaderMaster Page 2.205 At 100", "FaderMaster Page 2.205 At 0");
  expect(setup(301, {"4"}), "Go+ Macro 4", "");
  expect(setup(0, {}), "Go+ Macro 4", "");           // menu closed: unchanged
  expect(setup(202, {}), "Go+ Macro 4", "");         // number dialog cancelled: unchanged
  expect(setup(2, {}), "", "");                      // "Ne rien envoyer"
  std::printf("[host] menu labels seen: %d\n", int(g_menu_labels.size()));
#endif

  entry(nullptr, nullptr);
  return failures ? 1 : 0;
}
