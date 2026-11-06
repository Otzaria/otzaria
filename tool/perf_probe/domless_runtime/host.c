#define _POSIX_C_SOURCE 200809L
#include "quickjs.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#include <psapi.h>
#else
#include <sys/resource.h>
#endif

#define MAX_LINE (1024 * 1024)
#define MAX_RPC_BYTES (64 * 1024)
#define MAX_PENDING 64
#define MAX_JOBS 2048
#define HEAP_BYTES (16 * 1024 * 1024)
#define STACK_BYTES (512 * 1024)
#define TURN_MS 100

typedef struct {
  int64_t id;
  JSValue resolve;
  JSValue reject;
} Pending;

typedef struct {
  JSRuntime *runtime;
  JSContext *context;
  Pending pending[MAX_PENDING];
  int64_t next_id;
  int pending_count;
  int closing;
  int interrupted;
  int turns;
  int jobs;
  double start_ms;
  double deadline_ms;
} Host;

static double now_ms(void) {
#ifdef _WIN32
  LARGE_INTEGER counter, frequency;
  QueryPerformanceCounter(&counter);
  QueryPerformanceFrequency(&frequency);
  return (double)counter.QuadPart * 1000 / (double)frequency.QuadPart;
#else
  struct timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);
  return value.tv_sec * 1000.0 + value.tv_nsec / 1000000.0;
#endif
}

static double cpu_seconds(void) {
#ifdef _WIN32
  FILETIME creation, exit, kernel, user;
  ULARGE_INTEGER k, u;
  if (!GetProcessTimes(GetCurrentProcess(), &creation, &exit, &kernel, &user)) return -1;
  k.LowPart = kernel.dwLowDateTime; k.HighPart = kernel.dwHighDateTime;
  u.LowPart = user.dwLowDateTime; u.HighPart = user.dwHighDateTime;
  return (double)(k.QuadPart + u.QuadPart) / 10000000.0;
#else
  struct rusage usage;
  if (getrusage(RUSAGE_SELF, &usage)) return -1;
  return usage.ru_utime.tv_sec + usage.ru_stime.tv_sec +
    (usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000000.0;
#endif
}

static uint64_t peak_rss_bytes(void) {
#ifdef _WIN32
  PROCESS_MEMORY_COUNTERS usage;
  if (!GetProcessMemoryInfo(GetCurrentProcess(), &usage, sizeof(usage))) return 0;
  return usage.PeakWorkingSetSize;
#elif defined(__linux__)
  FILE *status = fopen("/proc/self/status", "r");
  if (!status) return 0;
  char line[256];
  uint64_t kib = 0;
  while (fgets(line, sizeof(line), status)) {
    if (sscanf(line, "VmHWM: %" SCNu64 " kB", &kib) == 1) break;
  }
  fclose(status);
  return kib * 1024;
#else
  return 0;
#endif
}

static int interrupt(JSContext *context, void *opaque) {
  (void)context;
  Host *host = opaque;
  if (now_ms() <= host->deadline_ms) return 0;
  host->interrupted = 1;
  return 1;
}

static void fatal(const char *code) {
  printf("{\"kind\":\"fatal\",\"code\":\"%s\"}\n", code);
  fflush(stdout);
}

static JSValue rpc(JSContext *context, JSValueConst receiver,
                   int argc, JSValueConst *argv) {
  (void)receiver;
  Host *host = JS_GetContextOpaque(context);
  if (host->closing) return JS_ThrowInternalError(context, "experiment.closed");
  if (argc != 1) return JS_ThrowTypeError(context, "One RPC envelope required");
  if (host->pending_count == MAX_PENDING)
    return JS_ThrowRangeError(context, "experiment.pending_rpc_limit");
  JSValue json = JS_JSONStringify(context, argv[0], JS_UNDEFINED, JS_UNDEFINED);
  if (JS_IsException(json)) return json;
  size_t size;
  const char *text = JS_ToCStringLen(context, &size, json);
  if (!text) { JS_FreeValue(context, json); return JS_EXCEPTION; }
  if (size > MAX_RPC_BYTES || JS_IsUndefined(json)) {
    JS_FreeCString(context, text); JS_FreeValue(context, json);
    return JS_ThrowRangeError(context, "experiment.rpc_size_limit");
  }
  JSValue callbacks[2];
  JSValue promise = JS_NewPromiseCapability(context, callbacks);
  if (!JS_IsException(promise)) {
    int slot = 0;
    while (host->pending[slot].id) slot++;
    Pending *pending = &host->pending[slot];
    pending->id = ++host->next_id;
    pending->resolve = callbacks[0]; pending->reject = callbacks[1];
    host->pending_count++;
    printf("{\"kind\":\"rpc\",\"id\":%" PRId64 ",\"request\":%s}\n",
           pending->id, text);
    fflush(stdout);
  }
  JS_FreeCString(context, text); JS_FreeValue(context, json);
  return promise;
}

static int drain(Host *host) {
  JSContext *context;
  for (int i = 0; JS_IsJobPending(host->runtime); i++) {
    if (i == MAX_JOBS) { fatal("job_budget"); return 0; }
    int result = JS_ExecutePendingJob(host->runtime, &context);
    host->jobs++;
    if (result < 0 || host->interrupted) {
      JSValue error = JS_GetException(context);
      JS_FreeValue(context, error);
      fatal(host->interrupted ? "turn_deadline" : "job_exception");
      return 0;
    }
  }
  return 1;
}

static void release_pending(Host *host, Pending *pending) {
  JS_FreeValue(host->context, pending->resolve);
  JS_FreeValue(host->context, pending->reject);
  pending->id = 0;
  host->pending_count--;
}

static void reject_pending(Host *host) {
  for (int i = 0; i < MAX_PENDING; i++) {
    Pending *pending = &host->pending[i];
    if (!pending->id) continue;
    JSValue reason = JS_NewString(host->context, "experiment.closed");
    JSValue result = JS_Call(host->context, pending->reject,
                            JS_UNDEFINED, 1, &reason);
    JS_FreeValue(host->context, result); JS_FreeValue(host->context, reason);
    release_pending(host, pending);
  }
}

static void stats(Host *host, int64_t id) {
  JSMemoryUsage usage;
  JS_ComputeMemoryUsage(host->runtime, &usage);
  char peak[32], cpu[32];
  uint64_t rss = peak_rss_bytes();
  double seconds = cpu_seconds();
  if (rss) snprintf(peak, sizeof(peak), "%" PRIu64, rss);
  else strcpy(peak, "null");
  if (seconds >= 0) snprintf(cpu, sizeof(cpu), "%.6f", seconds);
  else strcpy(cpu, "null");
  printf("{\"kind\":\"result\",\"id\":%" PRId64 ",\"ok\":true,\"value\":{"
         "\"heapUsedBytes\":%" PRId64 ",\"heapAllocatedBytes\":%" PRId64 ","
         "\"heapLimitBytes\":%d,\"stackLimitBytes\":%d,\"peakRssBytes\":%s,"
         "\"cpuSeconds\":%s,\"elapsedMs\":%.3f,\"pendingRpc\":%d,"
         "\"turns\":%d,\"jobs\":%d}}\n",
         id, usage.memory_used_size, usage.malloc_size, HEAP_BYTES, STACK_BYTES,
         peak, cpu, now_ms() - host->start_ms,
         host->pending_count, host->turns, host->jobs);
  fflush(stdout);
}

static int send_result(Host *host, int64_t id, JSValue value) {
  if (JS_IsException(value)) {
    JSValue error = JS_GetException(host->context);
    JS_FreeValue(host->context, error);
    fatal(host->interrupted ? "turn_deadline" : "evaluation_exception");
    return 0;
  }
  if (JS_IsUndefined(value)) value = JS_NULL;
  JSValue json = JS_JSONStringify(host->context, value, JS_UNDEFINED, JS_UNDEFINED);
  JS_FreeValue(host->context, value);
  if (JS_IsException(json)) { fatal("result_serialization"); return 0; }
  size_t size;
  const char *text = JS_ToCStringLen(host->context, &size, json);
  if (!text || size > MAX_LINE || JS_IsUndefined(json)) {
    if (text) JS_FreeCString(host->context, text);
    JS_FreeValue(host->context, json); fatal("result_size"); return 0;
  }
  printf("{\"kind\":\"result\",\"id\":%" PRId64 ",\"ok\":true,\"value\":%s}\n", id, text);
  fflush(stdout);
  JS_FreeCString(host->context, text); JS_FreeValue(host->context, json);
  return 1;
}

static int command(Host *host, const char *line, size_t size) {
  JSContext *context = host->context;
  JSValue message = JS_ParseJSON(context, line, size, "host-command");
  if (JS_IsException(message)) { fatal("invalid_command"); return 0; }
  JSValue id_value = JS_GetPropertyStr(context, message, "id");
  int64_t id = 0;
  JS_ToInt64(context, &id, id_value);
  JS_FreeValue(context, id_value);
  JSValue op_value = JS_GetPropertyStr(context, message, "op");
  const char *op = JS_ToCString(context, op_value);
  JS_FreeValue(context, op_value);
  int keep_running = 1;
  if (op && !strcmp(op, "eval")) {
    JSValue source_value = JS_GetPropertyStr(context, message, "source");
    size_t source_size;
    const char *source = JS_ToCStringLen(context, &source_size, source_value);
    if (!source) { fatal("source_invalid"); keep_running = 0; }
    else {
      JSValue result = JS_Eval(context, source, source_size, "experiment.js", JS_EVAL_TYPE_GLOBAL);
      keep_running = send_result(host, id, result);
      JS_FreeCString(context, source);
    }
    JS_FreeValue(context, source_value);
  } else if (op && !strcmp(op, "reply")) {
    for (int i = 0; i < MAX_PENDING; i++) {
      Pending *pending = &host->pending[i];
      if (!pending->id || pending->id != id) continue;
      JSValue value = JS_GetPropertyStr(context, message, "value");
      JSValue result = JS_Call(context, pending->resolve, JS_UNDEFINED, 1, &value);
      JS_FreeValue(context, value); JS_FreeValue(context, result);
      release_pending(host, pending);
      break;
    }
  } else if (op && !strcmp(op, "event")) {
    JSValue source = JS_GetPropertyStr(context, message, "source");
    const char *text = JS_ToCString(context, source);
    if (!text) { fatal("event_invalid"); keep_running = 0; }
    else {
      JSValue result = JS_Eval(context, text, strlen(text), "host-event.js", JS_EVAL_TYPE_GLOBAL);
      keep_running = send_result(host, id, result);
      JS_FreeCString(context, text);
    }
    JS_FreeValue(context, source);
  } else if (op && !strcmp(op, "stats")) {
    stats(host, id);
  } else if (op && !strcmp(op, "cpu")) {
    double seconds = cpu_seconds();
    if (seconds >= 0)
      printf("{\"kind\":\"result\",\"id\":%" PRId64 ",\"ok\":true,\"value\":%.6f}\n", id, seconds);
    else
      printf("{\"kind\":\"result\",\"id\":%" PRId64 ",\"ok\":true,\"value\":null}\n", id);
    fflush(stdout);
  } else if (op && !strcmp(op, "close")) {
    host->closing = 1;
    reject_pending(host);
    keep_running = drain(host);
    if (keep_running) stats(host, id);
    keep_running = 0;
  } else {
    fatal("unknown_command"); keep_running = 0;
  }
  if (op) JS_FreeCString(context, op);
  JS_FreeValue(context, message);
  return keep_running && drain(host);
}

int main(void) {
  Host host = {0};
  host.start_ms = now_ms();
  host.deadline_ms = host.start_ms + TURN_MS;
  host.runtime = JS_NewRuntime();
  if (!host.runtime) return 2;
  JS_SetMemoryLimit(host.runtime, HEAP_BYTES);
  JS_SetMaxStackSize(host.runtime, STACK_BYTES);
  JS_SetInterruptHandler(host.runtime, interrupt, &host);
  host.context = JS_NewContext(host.runtime);
  if (!host.context) { JS_FreeRuntime(host.runtime); return 2; }
  JS_SetContextOpaque(host.context, &host);
  JSValue global = JS_GetGlobalObject(host.context);
  JS_SetPropertyStr(host.context, global, "__otzariaNativeRpc",
                   JS_NewCFunction(host.context, rpc, "__otzariaNativeRpc", 1));
  JS_FreeValue(host.context, global);
  char *line = malloc(MAX_LINE + 2);
  if (!line) { JS_FreeContext(host.context); JS_FreeRuntime(host.runtime); return 2; }
  printf("{\"kind\":\"ready\"}\n"); fflush(stdout);
  while (fgets(line, MAX_LINE + 2, stdin)) {
    size_t size = strlen(line);
    if (!size || line[size - 1] != '\n') { fatal("input_size"); break; }
    host.deadline_ms = now_ms() + TURN_MS;
    host.interrupted = 0;
    host.turns++;
    if (!command(&host, line, size)) break;
  }
  host.closing = 1;
  for (int i = 0; i < MAX_PENDING; i++) {
    if (host.pending[i].id) release_pending(&host, &host.pending[i]);
  }
  free(line);
  JS_FreeContext(host.context);
  JS_FreeRuntime(host.runtime);
  return 0;
}
