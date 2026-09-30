// Minimal OSC 1.0 message encoding (no bundles).
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace ma3 {

struct OscArg {
  enum class Type { Int, Float, String } type = Type::String;
  int32_t i = 0;
  float f = 0.f;
  std::string s;

  static OscArg Int(int32_t v) { OscArg a; a.type = Type::Int; a.i = v; return a; }
  static OscArg Float(float v) { OscArg a; a.type = Type::Float; a.f = v; return a; }
  static OscArg Str(std::string v) { OscArg a; a.type = Type::String; a.s = std::move(v); return a; }
};

std::vector<uint8_t> EncodeOsc(const std::string& address, const std::vector<OscArg>& args);

// Turns a user command into an OSC packet.
// - Text starting with '/' is a raw message: "/address arg1 arg2 ...".
//   Arguments are ints, floats, or strings ("double quotes" keep spaces).
// - Anything else is a grandMA3 command line, sent as "/<prefix>/cmd" with one
//   string argument ("/cmd" when the prefix is empty).
// Returns an empty vector for empty or invalid input.
std::vector<uint8_t> CommandToOsc(const std::string& command, const std::string& prefix);

}  // namespace ma3
