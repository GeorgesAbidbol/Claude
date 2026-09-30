// Placeholder expansion for user commands, e.g. "Go+ Sequence {seq} Cue {n}".
#pragma once

#include <map>
#include <string>

namespace ma3 {

// Replaces every {key} found in vars. Unknown {keys} are left as they are.
std::string ExpandTemplate(const std::string& tpl, const std::map<std::string, std::string>& vars);

// First run of digits in s ("page 12" -> "12"), or "" if none.
std::string FirstNumber(const std::string& s);

// Escapes a name for use inside a double-quoted grandMA3 argument.
std::string QuoteForMa3(const std::string& s);

}  // namespace ma3
