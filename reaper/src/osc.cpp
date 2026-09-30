#include "osc.hpp"

#include <cctype>
#include <cstdlib>
#include <cstring>

namespace ma3 {
namespace {

void PutPaddedString(std::vector<uint8_t>& out, const std::string& s) {
  out.insert(out.end(), s.begin(), s.end());
  out.push_back(0);
  while (out.size() % 4) out.push_back(0);
}

void PutBigEndian32(std::vector<uint8_t>& out, uint32_t v) {
  out.push_back(uint8_t(v >> 24));
  out.push_back(uint8_t(v >> 16));
  out.push_back(uint8_t(v >> 8));
  out.push_back(uint8_t(v));
}

std::string Trim(const std::string& s) {
  size_t a = 0, b = s.size();
  while (a < b && std::isspace((unsigned char)s[a])) ++a;
  while (b > a && std::isspace((unsigned char)s[b - 1])) --b;
  return s.substr(a, b - a);
}

// Splits on spaces, keeping "quoted text" together. Sets quoted[i] for quoted tokens.
std::vector<std::string> Tokenize(const std::string& s, std::vector<bool>& quoted) {
  std::vector<std::string> out;
  size_t i = 0;
  while (i < s.size()) {
    while (i < s.size() && std::isspace((unsigned char)s[i])) ++i;
    if (i >= s.size()) break;
    std::string tok;
    bool q = false;
    if (s[i] == '"') {
      q = true;
      ++i;
      while (i < s.size() && s[i] != '"') tok += s[i++];
      if (i < s.size()) ++i;  // closing quote
    } else {
      while (i < s.size() && !std::isspace((unsigned char)s[i])) tok += s[i++];
    }
    out.push_back(tok);
    quoted.push_back(q);
  }
  return out;
}

OscArg ParseArg(const std::string& tok, bool quoted) {
  if (!quoted && !tok.empty()) {
    char* end = nullptr;
    long iv = std::strtol(tok.c_str(), &end, 10);
    if (end && *end == 0) return OscArg::Int(int32_t(iv));
    double dv = std::strtod(tok.c_str(), &end);
    if (end && *end == 0) return OscArg::Float(float(dv));
  }
  return OscArg::Str(tok);
}

}  // namespace

std::vector<uint8_t> EncodeOsc(const std::string& address, const std::vector<OscArg>& args) {
  std::vector<uint8_t> out;
  PutPaddedString(out, address);
  std::string tags = ",";
  for (const auto& a : args)
    tags += a.type == OscArg::Type::Int ? 'i' : a.type == OscArg::Type::Float ? 'f' : 's';
  PutPaddedString(out, tags);
  for (const auto& a : args) {
    switch (a.type) {
      case OscArg::Type::Int: PutBigEndian32(out, uint32_t(a.i)); break;
      case OscArg::Type::Float: {
        uint32_t bits;
        std::memcpy(&bits, &a.f, 4);
        PutBigEndian32(out, bits);
        break;
      }
      case OscArg::Type::String: PutPaddedString(out, a.s); break;
    }
  }
  return out;
}

std::vector<uint8_t> CommandToOsc(const std::string& command, const std::string& prefix) {
  const std::string cmd = Trim(command);
  if (cmd.empty()) return {};
  if (cmd[0] == '/') {
    std::vector<bool> quoted;
    auto toks = Tokenize(cmd, quoted);
    std::vector<OscArg> args;
    for (size_t i = 1; i < toks.size(); ++i) args.push_back(ParseArg(toks[i], quoted[i]));
    return EncodeOsc(toks[0], args);
  }
  std::string p = Trim(prefix);
  while (!p.empty() && p.front() == '/') p.erase(p.begin());
  while (!p.empty() && p.back() == '/') p.pop_back();
  return EncodeOsc(p.empty() ? "/cmd" : "/" + p + "/cmd", {OscArg::Str(cmd)});
}

}  // namespace ma3
