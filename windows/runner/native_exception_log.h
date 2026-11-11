#ifndef RUNNER_NATIVE_EXCEPTION_LOG_H_
#define RUNNER_NATIVE_EXCEPTION_LOG_H_

#include <windows.h>

#include "native_exception_records.h"

namespace native_exception_log {

// רושם מטפל עבור ה-thread שהחלון הראשי שייך לו. נקרא פעם אחת בתחילת הניטור.
void Install(DWORD thread_id);

Snapshot ReadRecent();

}  // namespace native_exception_log

#endif  // RUNNER_NATIVE_EXCEPTION_LOG_H_
