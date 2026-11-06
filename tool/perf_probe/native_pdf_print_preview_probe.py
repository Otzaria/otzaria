"""Linux PDFium file/memory baseline; no Flutter, ui.Image, or simulated cache."""

import argparse
import ctypes
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import sys
import threading
import time


def memory_sample():
    fields = {}
    for line in Path("/proc/self/smaps_rollup").read_text().splitlines()[1:]:
        name, value = line.split(":", 1)
        fields[name] = int(value.split()[0]) * 1024
    return fields["Rss"], fields["Private_Clean"] + fields["Private_Dirty"]


class MemorySampler:
    def __init__(self):
        self.baseline = memory_sample()
        self.peak = list(self.baseline)
        self.stopping = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)

    def sample(self):
        current = memory_sample()
        self.peak = [max(a, b) for a, b in zip(self.peak, current)]
        return current

    def run(self):
        while not self.stopping.wait(0.01):
            self.sample()

    def stop(self):
        self.stopping.set()
        self.thread.join()
        self.sample()


def pdfium_library(path):
    library = ctypes.CDLL(str(path))
    pointer, integer = ctypes.c_void_p, ctypes.c_int
    signatures = {
        "FPDF_InitLibrary": (None, []),
        "FPDF_DestroyLibrary": (None, []),
        "FPDF_LoadDocument": (pointer, [ctypes.c_char_p, ctypes.c_char_p]),
        "FPDF_LoadMemDocument64": (
            pointer, [pointer, ctypes.c_size_t, ctypes.c_char_p]
        ),
        "FPDF_GetLastError": (ctypes.c_ulong, []),
        "FPDF_CloseDocument": (None, [pointer]),
        "FPDF_GetPageCount": (integer, [pointer]),
        "FPDF_LoadPage": (pointer, [pointer, integer]),
        "FPDF_ClosePage": (None, [pointer]),
        "FPDF_GetPageWidth": (ctypes.c_double, [pointer]),
        "FPDF_GetPageHeight": (ctypes.c_double, [pointer]),
        "FPDF_GetPageSizeByIndex": (
            integer,
            [pointer, integer, ctypes.POINTER(ctypes.c_double),
             ctypes.POINTER(ctypes.c_double)],
        ),
        "FPDFBitmap_Create": (pointer, [integer, integer, integer]),
        "FPDFBitmap_Destroy": (None, [pointer]),
        "FPDFBitmap_FillRect": (
            None, [pointer, integer, integer, integer, integer, ctypes.c_ulong]
        ),
        "FPDFBitmap_GetBuffer": (pointer, [pointer]),
        "FPDFBitmap_GetStride": (integer, [pointer]),
        "FPDF_RenderPageBitmap": (None, [pointer, pointer] + [integer] * 6),
    }
    for name, (result, arguments) in signatures.items():
        function = getattr(library, name)
        function.restype = result
        function.argtypes = arguments
    return library


def measure(arguments):
    library = pdfium_library(arguments.library)
    library.FPDF_InitLibrary()
    sampler = MemorySampler()
    sampler.thread.start()
    started = time.perf_counter()
    document = None
    cached_bytes = None
    native_copy = None
    phases = {}
    samples = {}
    first_ready = None
    page_results = []
    try:
        if arguments.source == "bytes":
            cached_bytes = arguments.file.read_bytes()
            phases["fileReadMs"] = (time.perf_counter() - started) * 1000
            samples["afterRead"] = sampler.sample()
            copied = time.perf_counter()
            native_copy = ctypes.create_string_buffer(cached_bytes, len(cached_bytes))
            phases["nativeCopyMs"] = (time.perf_counter() - copied) * 1000
            samples["afterNativeCopy"] = sampler.sample()
            document = library.FPDF_LoadMemDocument64(
                native_copy, len(cached_bytes), None
            )
        else:
            document = library.FPDF_LoadDocument(os.fsencode(arguments.file), None)
        if not document:
            raise RuntimeError(f"PDFium open failed: {library.FPDF_GetLastError()}")
        phases["openIncludingReadAndCopyMs"] = (time.perf_counter() - started) * 1000
        samples["afterOpen"] = sampler.sample()
        count = library.FPDF_GetPageCount(document)
        if count <= 0:
            raise RuntimeError("PDF has no pages")
        first = min(max(arguments.start - 1, 0), count - 1)
        metadata_pages = (
            range(count) if arguments.metadata == "all"
            else sorted({0, *range(first, min(first + arguments.count, count))})
        )
        metadata_started = time.perf_counter()
        width, height = ctypes.c_double(), ctypes.c_double()
        for index in metadata_pages:
            if not library.FPDF_GetPageSizeByIndex(
                document, index, ctypes.byref(width), ctypes.byref(height)
            ):
                raise RuntimeError(f"Cannot read page {index + 1} dimensions")
        phases["pageDimensionsMs"] = (time.perf_counter() - metadata_started) * 1000
        for index in range(first, min(first + arguments.count, count)):
            page = library.FPDF_LoadPage(document, index)
            if not page:
                raise RuntimeError(f"Cannot load page {index + 1}")
            bitmap = None
            try:
                width = math.ceil(library.FPDF_GetPageWidth(page) * arguments.scale)
                height = math.ceil(library.FPDF_GetPageHeight(page) * arguments.scale)
                render_started = time.perf_counter()
                bitmap = library.FPDFBitmap_Create(width, height, 0)
                if not bitmap:
                    raise RuntimeError("Cannot allocate bitmap")
                library.FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF)
                library.FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 1)
                render_ms = (time.perf_counter() - render_started) * 1000
                if first_ready is None:
                    first_ready = (time.perf_counter() - started) * 1000
                sampler.sample()
                size = library.FPDFBitmap_GetStride(bitmap) * height
                buffer = (ctypes.c_ubyte * size).from_address(
                    library.FPDFBitmap_GetBuffer(bitmap)
                )
                page_results.append({
                    "page": index + 1, "width": width, "height": height,
                    "renderMs": render_ms,
                    "pixelsSha256": hashlib.sha256(buffer).hexdigest(),
                })
            finally:
                if bitmap:
                    library.FPDFBitmap_Destroy(bitmap)
                library.FPDF_ClosePage(page)
        closing = time.perf_counter()
        library.FPDF_CloseDocument(document)
        document = None
        native_copy = None
        phases["closeMs"] = (time.perf_counter() - closing) * 1000
        elapsed = (time.perf_counter() - started) * 1000
        sampler.stop()
        return {
            "scope": "native PDFium only; excludes Flutter, Dart and UI paint",
            "pid": os.getpid(), "platform": sys.platform,
            "file": arguments.file.name, "fileBytes": arguments.file.stat().st_size,
            "source": arguments.source, "pageCount": count,
            "metadata": arguments.metadata, "metadataPagesRead": len(metadata_pages),
            "firstPageRasterReadyMs": first_ready,
            "totalIncludingPixelChecksMs": elapsed,
            "cachedSourceBytes": len(cached_bytes) if cached_bytes else 0,
            "baselineRssBytes": sampler.baseline[0],
            "sampledPeakRssBytes": sampler.peak[0],
            "baselinePrivateResidentBytes": sampler.baseline[1],
            "sampledPeakPrivateResidentBytes": sampler.peak[1],
            "processLifetimePeakRssBytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * 1024,
            "memorySampleIntervalMs": 10,
            "phaseMemoryRssPrivateBytes": samples, "phases": phases,
            "renderedPages": page_results,
        }
    finally:
        if not sampler.stopping.is_set():
            sampler.stop()
        if document:
            library.FPDF_CloseDocument(document)
        library.FPDF_DestroyLibrary()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--source", choices=["file", "bytes"], required=True)
    parser.add_argument("--metadata", choices=["all", "selected"], default="all")
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--count", type=int, default=2)
    parser.add_argument("--scale", type=float, default=1.5)
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if sys.platform != "linux":
        parser.error("Private-resident sampling in this probe requires Linux")
    if (arguments.start < 1 or arguments.count < 1
            or not math.isfinite(arguments.scale) or arguments.scale <= 0):
        parser.error("start, count and scale must be positive")
    result = json.dumps(measure(arguments))
    print(result, flush=True)
    if arguments.output:
        arguments.output.write_text(result + "\n")


if __name__ == "__main__":
    main()
