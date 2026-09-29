#include "zvfs_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <bcrypt.h>
#include <process.h>
#if defined(_MSC_VER)
#pragma comment(lib, "bcrypt.lib")
#endif
#else
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#if defined(__ANDROID__) && !defined(__LP64__)
/* Bionic 32-bit: off_t stays 32-bit, the *64 variants take off64_t. */
#define ZPREAD pread64
#define ZPWRITE pwrite64
#define ZOFF off64_t
#else
#define ZPREAD pread
#define ZPWRITE pwrite
#define ZOFF off_t
#endif
#endif

#if defined(_WIN32)

void zplat_mutex_init(zplat_mutex *m) { InitializeSRWLock(m); }
void zplat_mutex_destroy(zplat_mutex *m) { (void)m; }
void zplat_lock(zplat_mutex *m) { AcquireSRWLockExclusive(m); }
void zplat_unlock(zplat_mutex *m) { ReleaseSRWLockExclusive(m); }
void zplat_cond_init(zplat_cond *c) { InitializeConditionVariable(c); }
void zplat_cond_destroy(zplat_cond *c) { (void)c; }
void zplat_cond_wait(zplat_cond *c, zplat_mutex *m) {
  SleepConditionVariableSRW(c, m, INFINITE, 0);
}
void zplat_cond_broadcast(zplat_cond *c) { WakeAllConditionVariable(c); }

typedef struct {
  void (*fn)(void *);
  void *arg;
} thread_start;

static unsigned __stdcall thread_tramp(void *p) {
  thread_start s = *(thread_start *)p;
  free(p);
  s.fn(s.arg);
  return 0;
}

int zplat_thread_start(zplat_thread *t, void (*fn)(void *), void *arg) {
  thread_start *s = (thread_start *)malloc(sizeof *s);
  if (!s) return ZVFS_ERR_NOMEM;
  s->fn = fn;
  s->arg = arg;
  uintptr_t h = _beginthreadex(NULL, 0, thread_tramp, s, 0, NULL);
  if (!h) {
    free(s);
    return ZVFS_ERR_NOMEM;
  }
  *t = (HANDLE)h;
  return ZVFS_OK;
}

void zplat_thread_join(zplat_thread t) {
  WaitForSingleObject(t, INFINITE);
  CloseHandle(t);
}

int64_t zplat_atomic_add(volatile int64_t *p, int64_t v) {
  return InterlockedExchangeAdd64((volatile LONG64 *)p, v) + v;
}
int64_t zplat_atomic_load(volatile int64_t *p) {
  return InterlockedCompareExchange64((volatile LONG64 *)p, 0, 0);
}
void zplat_atomic_store(volatile int64_t *p, int64_t v) {
  InterlockedExchange64((volatile LONG64 *)p, v);
}
int32_t zplat_atomic_load32(volatile int32_t *p) {
  return InterlockedCompareExchange((volatile LONG *)p, 0, 0);
}

struct zplat_file {
  HANDLE h;
};

static wchar_t *widen(const char *s) {
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
  if (n <= 0) return NULL;
  wchar_t *w = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
  if (!w) return NULL;
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, w, n) != n) {
    free(w);
    return NULL;
  }
  return w;
}

static int open_common(const char *path, int write, zplat_file **out) {
  wchar_t *w = widen(path);
  if (!w) return ZVFS_ERR_INVALID;
  HANDLE h = CreateFileW(
      w, write ? GENERIC_READ | GENERIC_WRITE : GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
      write ? CREATE_ALWAYS : OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  free(w);
  if (h == INVALID_HANDLE_VALUE) return ZVFS_ERR_IO;
  zplat_file *f = (zplat_file *)malloc(sizeof *f);
  if (!f) {
    CloseHandle(h);
    return ZVFS_ERR_NOMEM;
  }
  f->h = h;
  *out = f;
  return ZVFS_OK;
}

int zplat_open_read(const char *p, zplat_file **o) { return open_common(p, 0, o); }
int zplat_open_write(const char *p, zplat_file **o) { return open_common(p, 1, o); }

int zplat_pread(zplat_file *f, void *buf, size_t n, uint64_t off, size_t *got) {
  size_t done = 0;
  while (done < n) {
    DWORD chunk = (DWORD)((n - done) > (1u << 30) ? (1u << 30) : (n - done));
    OVERLAPPED o;
    memset(&o, 0, sizeof o);
    uint64_t at = off + done;
    o.Offset = (DWORD)at;
    o.OffsetHigh = (DWORD)(at >> 32);
    DWORD r = 0;
    if (!ReadFile(f->h, (char *)buf + done, chunk, &r, &o)) {
      if (GetLastError() == ERROR_HANDLE_EOF) break;
      *got = done;
      return ZVFS_ERR_IO;
    }
    if (r == 0) break;
    done += r;
  }
  *got = done;
  return ZVFS_OK;
}

int zplat_pwrite(zplat_file *f, const void *buf, size_t n, uint64_t off) {
  size_t done = 0;
  while (done < n) {
    DWORD chunk = (DWORD)((n - done) > (1u << 30) ? (1u << 30) : (n - done));
    OVERLAPPED o;
    memset(&o, 0, sizeof o);
    uint64_t at = off + done;
    o.Offset = (DWORD)at;
    o.OffsetHigh = (DWORD)(at >> 32);
    DWORD w = 0;
    if (!WriteFile(f->h, (const char *)buf + done, chunk, &w, &o) || w == 0)
      return ZVFS_ERR_IO;
    done += w;
  }
  return ZVFS_OK;
}

int zplat_size(zplat_file *f, uint64_t *size) {
  LARGE_INTEGER li;
  if (!GetFileSizeEx(f->h, &li)) return ZVFS_ERR_IO;
  *size = (uint64_t)li.QuadPart;
  return ZVFS_OK;
}

int zplat_sync(zplat_file *f) {
  return FlushFileBuffers(f->h) ? ZVFS_OK : ZVFS_ERR_IO;
}

void zplat_close(zplat_file *f) {
  if (!f) return;
  CloseHandle(f->h);
  free(f);
}

void zplat_random(void *buf, size_t n) {
  if (BCryptGenRandom(NULL, (PUCHAR)buf, (ULONG)n,
                      BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
    LARGE_INTEGER c;
    QueryPerformanceCounter(&c);
    uint64_t x = (uint64_t)c.QuadPart ^ (uint64_t)GetCurrentProcessId() << 32;
    for (size_t i = 0; i < n; i++) {
      x = x * 6364136223846793005ull + 1442695040888963407ull;
      ((uint8_t *)buf)[i] = (uint8_t)(x >> 56);
    }
  }
}

uint64_t zplat_now_ms(void) {
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
  return (t - 116444736000000000ull) / 10000ull;
}

int zplat_exists(const char *path) {
  wchar_t *w = widen(path);
  if (!w) return -1;
  DWORD a = GetFileAttributesW(w);
  DWORD e = a == INVALID_FILE_ATTRIBUTES ? GetLastError() : 0;
  free(w);
  if (a != INVALID_FILE_ATTRIBUTES) return 1;
  return e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND ? 0 : -1;
}

int zplat_rename_durable(const char *from, const char *to) {
  wchar_t *a = widen(from), *b = widen(to);
  int ok = a && b &&
           MoveFileExW(a, b, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
  free(a);
  free(b);
  return ok ? ZVFS_OK : ZVFS_ERR_IO;
}

int zplat_delete_durable(const char *path) {
  wchar_t *w = widen(path);
  if (!w) return ZVFS_ERR_INVALID;
  BOOL ok = DeleteFileW(w);
  DWORD e = ok ? 0 : GetLastError();
  free(w);
  if (ok || e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND)
    return ZVFS_OK;
  return ZVFS_ERR_IO;
}

#else /* POSIX */

void zplat_mutex_init(zplat_mutex *m) { pthread_mutex_init(m, NULL); }
void zplat_mutex_destroy(zplat_mutex *m) { pthread_mutex_destroy(m); }
void zplat_lock(zplat_mutex *m) { pthread_mutex_lock(m); }
void zplat_unlock(zplat_mutex *m) { pthread_mutex_unlock(m); }
void zplat_cond_init(zplat_cond *c) { pthread_cond_init(c, NULL); }
void zplat_cond_destroy(zplat_cond *c) { pthread_cond_destroy(c); }
void zplat_cond_wait(zplat_cond *c, zplat_mutex *m) { pthread_cond_wait(c, m); }
void zplat_cond_broadcast(zplat_cond *c) { pthread_cond_broadcast(c); }

typedef struct {
  void (*fn)(void *);
  void *arg;
} thread_start;

static void *thread_tramp(void *p) {
  thread_start s = *(thread_start *)p;
  free(p);
  s.fn(s.arg);
  return NULL;
}

int zplat_thread_start(zplat_thread *t, void (*fn)(void *), void *arg) {
  thread_start *s = (thread_start *)malloc(sizeof *s);
  if (!s) return ZVFS_ERR_NOMEM;
  s->fn = fn;
  s->arg = arg;
  if (pthread_create(t, NULL, thread_tramp, s) != 0) {
    free(s);
    return ZVFS_ERR_NOMEM;
  }
  return ZVFS_OK;
}

void zplat_thread_join(zplat_thread t) { pthread_join(t, NULL); }

int64_t zplat_atomic_add(volatile int64_t *p, int64_t v) {
  return __atomic_add_fetch(p, v, __ATOMIC_SEQ_CST);
}
int64_t zplat_atomic_load(volatile int64_t *p) {
  return __atomic_load_n(p, __ATOMIC_SEQ_CST);
}
void zplat_atomic_store(volatile int64_t *p, int64_t v) {
  __atomic_store_n(p, v, __ATOMIC_SEQ_CST);
}
int32_t zplat_atomic_load32(volatile int32_t *p) {
  return __atomic_load_n(p, __ATOMIC_SEQ_CST);
}

struct zplat_file {
  int fd;
};

static int open_common(const char *path, int flags, zplat_file **out) {
  int fd;
  do {
    fd = open(path, flags | O_CLOEXEC, 0644);
  } while (fd < 0 && errno == EINTR);
  if (fd < 0) return ZVFS_ERR_IO;
  zplat_file *f = (zplat_file *)malloc(sizeof *f);
  if (!f) {
    close(fd);
    return ZVFS_ERR_NOMEM;
  }
  f->fd = fd;
  *out = f;
  return ZVFS_OK;
}

int zplat_open_read(const char *p, zplat_file **o) {
  return open_common(p, O_RDONLY, o);
}
int zplat_open_write(const char *p, zplat_file **o) {
  return open_common(p, O_RDWR | O_CREAT | O_TRUNC, o);
}

int zplat_pread(zplat_file *f, void *buf, size_t n, uint64_t off, size_t *got) {
  size_t done = 0;
  while (done < n) {
    size_t chunk = (n - done) > (1u << 30) ? (1u << 30) : (n - done);
    ssize_t r = ZPREAD(f->fd, (char *)buf + done, chunk, (ZOFF)(off + done));
    if (r < 0) {
      if (errno == EINTR) continue;
      *got = done;
      return ZVFS_ERR_IO;
    }
    if (r == 0) break;
    done += (size_t)r;
  }
  *got = done;
  return ZVFS_OK;
}

int zplat_pwrite(zplat_file *f, const void *buf, size_t n, uint64_t off) {
  size_t done = 0;
  while (done < n) {
    size_t chunk = (n - done) > (1u << 30) ? (1u << 30) : (n - done);
    ssize_t w =
        ZPWRITE(f->fd, (const char *)buf + done, chunk, (ZOFF)(off + done));
    if (w < 0) {
      if (errno == EINTR) continue;
      return ZVFS_ERR_IO;
    }
    if (w == 0) return ZVFS_ERR_IO;
    done += (size_t)w;
  }
  return ZVFS_OK;
}

int zplat_size(zplat_file *f, uint64_t *size) {
#if defined(__ANDROID__) && !defined(__LP64__)
  struct stat64 st;
  if (fstat64(f->fd, &st) != 0) return ZVFS_ERR_IO;
#else
  struct stat st;
  if (fstat(f->fd, &st) != 0) return ZVFS_ERR_IO;
#endif
  *size = (uint64_t)st.st_size;
  return ZVFS_OK;
}

int zplat_sync(zplat_file *f) { return fsync(f->fd) == 0 ? ZVFS_OK : ZVFS_ERR_IO; }

void zplat_close(zplat_file *f) {
  if (!f) return;
  close(f->fd);
  free(f);
}

void zplat_random(void *buf, size_t n) {
  size_t got = 0;
  int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
  if (fd >= 0) {
    while (got < n) {
      ssize_t r = read(fd, (char *)buf + got, n - got);
      if (r <= 0) break;
      got += (size_t)r;
    }
    close(fd);
  }
  if (got < n) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    uint64_t x = ((uint64_t)tv.tv_sec << 20) ^ (uint64_t)tv.tv_usec ^
                 ((uint64_t)getpid() << 40);
    for (size_t i = got; i < n; i++) {
      x = x * 6364136223846793005ull + 1442695040888963407ull;
      ((uint8_t *)buf)[i] = (uint8_t)(x >> 56);
    }
  }
}

uint64_t zplat_now_ms(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (uint64_t)tv.tv_sec * 1000ull + (uint64_t)tv.tv_usec / 1000ull;
}

int zplat_exists(const char *path) {
  if (access(path, F_OK) == 0) return 1;
  return errno == ENOENT || errno == ENOTDIR ? 0 : -1;
}

/* A rename or unlink is durable only once its directory is synced. */
static int sync_parent(const char *path) {
  size_t n = strlen(path);
  while (n > 0 && path[n - 1] != '/') n--;
  char *dir = (char *)malloc(n + 2);
  if (!dir) return ZVFS_ERR_NOMEM;
  if (n == 0) {
    dir[0] = '.';
    dir[1] = 0;
  } else {
    memcpy(dir, path, n);
    dir[n] = 0;
  }
  int fd = open(dir, O_RDONLY | O_CLOEXEC);
  free(dir);
  if (fd < 0) return ZVFS_ERR_IO;
  int rc = fsync(fd) == 0 ? ZVFS_OK : ZVFS_ERR_IO;
  close(fd);
  return rc;
}

int zplat_rename_durable(const char *from, const char *to) {
  if (rename(from, to) != 0) return ZVFS_ERR_IO;
  return sync_parent(to);
}

int zplat_delete_durable(const char *path) {
  if (unlink(path) != 0) return errno == ENOENT ? ZVFS_OK : ZVFS_ERR_IO;
  return sync_parent(path);
}

#endif
