"""Read CPU/RSS and lifetime identity for one owned process, never a guessed tree."""

import ctypes
from dataclasses import dataclass
import errno
import os
from pathlib import Path
import sys


@dataclass(frozen=True)
class ProcessObservation:
    start_ticks: int
    cpu_seconds: float
    resident_bytes: int
    threads: int | None = None


def parse_linux_stat(source, *, expected_pid, clock_ticks, page_size):
    left, right = source.find("("), source.rfind(")")
    if left <= 0 or right <= left or int(source[:left]) != expected_pid:
        raise ValueError("Invalid /proc process identity")
    fields = source[right + 1:].split()
    if len(fields) < 22 or fields[0] in ("Z", "X", "x"):
        raise ProcessLookupError(expected_pid)
    # Field 3 begins after comm, which can itself contain spaces or parentheses.
    user, system, threads, start, rss = (int(fields[i]) for i in (11, 12, 17, 19, 21))
    if min(user, system, rss) < 0 or min(threads, start, clock_ticks, page_size) <= 0:
        raise ValueError("Invalid /proc resource counters")
    return ProcessObservation(start, (user + system) / clock_ticks, rss * page_size, threads)


class LinuxProcessReader:
    source = "/proc/<pid>/stat:utime+stime,starttime,rss,num_threads"

    def __init__(self, root=Path("/proc")):
        self.root = root
        self.clock_ticks = os.sysconf("SC_CLK_TCK")
        self.page_size = os.sysconf("SC_PAGE_SIZE")

    def read(self, pid):
        return parse_linux_stat(
            (self.root / str(pid) / "stat").read_text(), expected_pid=pid,
            clock_ticks=self.clock_ticks, page_size=self.page_size,
        )

    def metadata(self):
        return {"source": self.source, "clockTicksPerSecond": self.clock_ticks,
                "pageBytes": self.page_size,
                "rssLimit": "Kernel resident-page counters are an approximate snapshot."}


class RUsageInfoV0(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64) for name in (
            "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups",
            "pageins", "wired_size", "resident_size", "phys_footprint",
            "proc_start_abstime", "proc_exit_abstime",
        )
    ]


class MachTimebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


def darwin_observation(info, numer, denom):
    if info.proc_exit_abstime:
        raise ProcessLookupError("Process has exited")
    if not info.proc_start_abstime or min(numer, denom) <= 0:
        raise ValueError("Invalid Mach process identity or timebase")
    # XNU reports Mach time, not nanoseconds; Apple Silicon is not a 1:1 timebase.
    seconds = (info.user_time + info.system_time) * numer / denom / 1_000_000_000
    return ProcessObservation(info.proc_start_abstime, seconds, info.resident_size)


class DarwinProcessReader:
    source = "proc_pid_rusage(RUSAGE_INFO_V0) + mach_timebase_info"

    def __init__(self):
        self.library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        self.rusage = self.library.proc_pid_rusage
        self.rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
        self.rusage.restype = ctypes.c_int
        system = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
        timebase = system.mach_timebase_info
        timebase.argtypes = [ctypes.POINTER(MachTimebase)]
        timebase.restype = ctypes.c_int
        value = MachTimebase()
        if timebase(ctypes.byref(value)) != 0 or min(value.numer, value.denom) <= 0:
            raise RuntimeError("Cannot determine the Mach CPU timebase")
        self.numer, self.denom = value.numer, value.denom

    def read(self, pid):
        value = RUsageInfoV0()
        if self.rusage(pid, 0, ctypes.byref(value)) != 0:
            error = ctypes.get_errno()
            if error == errno.ESRCH:
                raise ProcessLookupError(pid)
            raise OSError(error, os.strerror(error))
        return darwin_observation(value, self.numer, self.denom)

    def metadata(self):
        return {"source": self.source, "machTimebaseNumer": self.numer,
                "machTimebaseDenom": self.denom,
                "rssLimit": "Resident size; physical footprint is not relabeled as private commit."}


def process_reader():
    if sys.platform == "linux":
        return LinuxProcessReader()
    if sys.platform == "darwin":
        return DarwinProcessReader()
    raise RuntimeError("This sampler supports Linux and macOS only")
