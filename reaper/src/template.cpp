#include "template.hpp"

#include <cctype>

namespace ma3 {

std::string ExpandTemplate(const std::string& tpl, const std::map<std::string, std::string>& vars) {
  std::string out;
  size_t i = 0;
  while (i < tpl.size()) {
    if (tpl[i] == '{') {
      size_t close = tpl.find('}', i + 1);
      if (close != std::string::npos) {
        auto it = vars.find(tpl.substr(i + 1, close - i - 1));
        if (it != vars.end()) {
          out += it->second;
          i = close + 1;
          continue;
        }
      }
    }
    out += tpl[i++];
  }
  return out;
}

std::string FirstNumber(const std::string& s) {
  size_t i = 0;
  while (i < s.size() && !std::isdigit((unsigned char)s[i])) ++i;
  size_t j = i;
  while (j < s.size() && std::isdigit((unsigned char)s[j])) ++j;
  return s.substr(i, j - i);
}

std::string QuoteForMa3(const std::string& s) {
  // The grandMA3 command line has no escape for '"', so replace it.
  std::string out = "\"";
  for (char c : s) out += c == '"' ? '\'' : c;
  return out + "\"";
}

}  // namespace ma3
