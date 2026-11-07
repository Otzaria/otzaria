#ifndef OTZARIA_OWNED_PROCESS_CONTROL_H
#define OTZARIA_OWNED_PROCESS_CONTROL_H
#include <ApplicationServices/ApplicationServices.h>
#include <stdint.h>
int32_t OQGetProcessForPID(int32_t pid, ProcessSerialNumber *psn);
int32_t OQGetProcessPID(const ProcessSerialNumber *psn, int32_t *pid);
int32_t OQSameProcess(const ProcessSerialNumber *first, const ProcessSerialNumber *second, int32_t *same);
int32_t OQShowHideProcess(const ProcessSerialNumber *psn, int32_t visible);
#endif
