"""Keep a private, verified PDF case shared by both measured source snapshots."""

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import stat


def _stamp(value):
    return tuple(getattr(value, key) for key in (
        "st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns"))


@dataclass(frozen=True)
class _FileIdentity:
    path: Path
    resolved: Path
    stamp: tuple
    sha256: str
    bytes: int


def _capture(path, *, copy_to=None, maximum=None):
    if copy_to is None:
        return _capture_input(path, maximum=maximum)
    target = copy_to.open("xb")
    try:
        with target:
            return _capture_input(path, target=target, maximum=maximum)
    except BaseException:
        copy_to.unlink(missing_ok=True)
        raise


def _capture_input(path, *, target=None, maximum=None):
    path = path.absolute()
    resolved = path.resolve(strict=True)
    observed = resolved.stat()
    if not stat.S_ISREG(observed.st_mode) or observed.st_size <= 0:
        raise ValueError("PDF case inputs must be nonempty regular files.")
    if maximum is not None and observed.st_size > maximum:
        raise ValueError(f"PDF case manifest exceeds {maximum} bytes.")
    digest = hashlib.sha256()
    # A regular file can be replaced by a FIFO before open. Inspect it without blocking.
    with open(resolved, "rb", opener=lambda name, flags: os.open(
            name, flags | getattr(os, "O_NONBLOCK", 0))) as source:
        before = os.fstat(source.fileno())
        # Windows stat can report birthtime as ctime while fstat reports change time.
        if not stat.S_ISREG(before.st_mode) or _stamp(observed)[:-1] != _stamp(before)[:-1]:
            raise ValueError("PDF case input changed while reading.")
        remaining = before.st_size
        while remaining:
            block = source.read(min(1024 * 1024, remaining))
            if not block:
                raise ValueError("PDF case input changed while reading.")
            digest.update(block)
            if target is not None:
                target.write(block)
            remaining -= len(block)
        if source.read(1):
            raise ValueError("PDF case input changed while reading.")
        after = os.fstat(source.fileno())
    if (_stamp(before) != _stamp(after) or path.resolve(strict=True) != resolved
            or _stamp(path.stat()) != _stamp(observed)):
        raise ValueError("PDF case input changed while reading.")
    return _FileIdentity(path, resolved, _stamp(after), digest.hexdigest(), after.st_size)


def _same_json(left, right):
    return json.dumps(left, sort_keys=True, allow_nan=False) == json.dumps(right, sort_keys=True, allow_nan=False)


class PdfCaseSnapshot:
    @classmethod
    def prepare(cls, input_case, output, canonicalize):
        output = output.resolve(strict=True)
        original = _capture(input_case, maximum=64 * 1024)
        validated = output / "validated-pdf-case.json"
        # The existing Dart parser owns the schema, defaults and relative-path rules.
        canonicalize(input_case, validated)
        if _capture(input_case, maximum=64 * 1024) != original:
            raise ValueError("The requested PDF case changed during validation.")
        case = json.loads(validated.read_text(encoding="utf-8-sig"))
        guards = [original, _capture(validated, maximum=64 * 1024)]
        source = case["source"]
        external = None
        if source["kind"] == "external":
            private = output / "corpus-source.pdf"
            external = _capture(Path(source["path"]), copy_to=private)
            try:
                if external.sha256 != source["sha256"]:
                    raise ValueError("External PDF bytes do not match the requested source.sha256.")
                copied = _capture(private)
                if copied.sha256 != external.sha256 or copied.bytes != external.bytes:
                    raise ValueError("The private PDF copy differs from the requested source.")
            except BaseException:
                private.unlink(missing_ok=True)
                raise
            guards.extend([external, copied])
            source["path"] = str(private)
        path = output / "pdf-case.json"
        with path.open("x", encoding="utf-8") as target:
            target.write(json.dumps(case, ensure_ascii=False, indent=2) + "\n")
        guards.append(_capture(path, maximum=64 * 1024))
        comparison = json.loads(json.dumps(case))
        comparison["source"].pop("path", None)
        comparison["navigation"].update(
            zoomPage=comparison["navigation"]["backwardPage"], zoomAnchor="pageCenter")
        snapshot = cls(path, case, comparison, guards, {
            "inputManifestSha256": original.sha256,
            "manifestSha256": guards[-1].sha256,
            "case": comparison,
            **({"sourceSha256": external.sha256, "sourceBytes": external.bytes} if external else {}),
        })
        snapshot.verify()
        return snapshot

    def __init__(self, path, case, comparison, guards, receipt):
        self.path, self.case, self.comparison = path, case, comparison
        self._guards, self.receipt = guards, receipt

    def verify(self):
        for expected in self._guards:
            if _capture(expected.path) != expected:
                raise ValueError("PDF case input or private snapshot changed.")

    def verify_run(self, directory, report):
        self.verify()
        actual = json.loads((directory / "pdf-case.json").read_text(encoding="utf-8-sig"))
        settings = report.get("metadata", {}).get("settings", {})
        if (not _same_json(actual, self.case)
                or not _same_json(settings.get("pdfReaderCase"), self.comparison)
                or type(settings.get("pdfPageCount")) is not int
                or settings["pdfPageCount"] != self.case["source"]["pageCount"]):
            raise ValueError(f"The runner did not measure the requested canonical PDF case: {directory}")
