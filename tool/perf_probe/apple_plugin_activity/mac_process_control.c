#include "mac_process_control.h"

/* Normal documented SDK calls; deprecated status is preserved in compiler output.
 * No availability overrides, private symbols, dynamic lookup or global app action.
 */
int32_t OQGetProcessForPID(int32_t pid, ProcessSerialNumber *psn) {
    return GetProcessForPID((pid_t)pid, psn);
}
int32_t OQGetProcessPID(const ProcessSerialNumber *psn, int32_t *pid) {
    pid_t actual = 0;
    OSStatus status = GetProcessPID(psn, &actual);
    *pid = (int32_t)actual;
    return status;
}
int32_t OQSameProcess(const ProcessSerialNumber *first, const ProcessSerialNumber *second, int32_t *same) {
    Boolean actual = false;
    OSErr status = SameProcess(first, second, &actual);
    *same = actual ? 1 : 0;
    return status;
}
int32_t OQShowHideProcess(const ProcessSerialNumber *psn, int32_t visible) {
    return ShowHideProcess(psn, visible ? true : false);
}
