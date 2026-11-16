#ifndef RUNNER_IMAGE_IDENTITY_H_
#define RUNNER_IMAGE_IDENTITY_H_

#include <windows.h>

#include <functional>
#include <string>

// מזהי קובצי הסמלים של מודול בזיכרון. הקריאה דרך [MemoryReader], כדי שגם מודול
// ה-WER, שרץ ב-WerFault, יקרא אותם מהתהליך שקרס.
namespace image_identity {

using MemoryReader = std::function<bool(ULONG_PTR address, void* out, size_t size)>;

// ה-build-id של app.so, או ריק.
std::string DartBuildId(const MemoryReader& read, ULONG_PTR base);

// "<pdb> <GUID><age>" של מודול PE, או ריק.
std::string ModulePdbKey(const MemoryReader& read, ULONG_PTR base);

}  // namespace image_identity

#endif  // RUNNER_IMAGE_IDENTITY_H_
