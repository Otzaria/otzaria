#ifndef RUNNER_INCIDENT_CONTEXT_H_
#define RUNNER_INCIDENT_CONTEXT_H_

#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <string>

inline void AppendIncidentContext(uint32_t state, std::string* report) {
  // אותו קידוד כמו NativeIncidentContext.encode ב-Dart.
  constexpr const char* screens[] = {
      "unknown", "library", "find", "reading", "search", "settings"};
  constexpr const char* tabs[] = {
      "none", "text", "pdf", "commentators", "pdfCommentators",
      "search", "tool", "combined", "other"};
  const uint32_t screen = state & 0xfu;
  const uint32_t tab = (state >> 4) & 0xfu;
  if (screen == 0 || screen >= ARRAYSIZE(screens) || tab >= ARRAYSIZE(tabs))
    return;
  char line[128];
  snprintf(line, sizeof(line),
           "Context: screen=%s; tabs=%u; tab=%s; semantics=%s\n",
           screens[screen], (state >> 9) & 0xffffu, tabs[tab],
           (state & 0x100u) != 0 ? "on" : "off");
  *report += line;
}

#endif  // RUNNER_INCIDENT_CONTEXT_H_
