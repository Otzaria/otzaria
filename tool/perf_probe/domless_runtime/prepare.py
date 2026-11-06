#!/usr/bin/env python3
"""Fetch verified experiment inputs and build an isolated, opt-in native host."""

import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent


class Scripts(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.scripts = []
        self.current = None

    def handle_starttag(self, tag, attrs):
        if tag != "script":
            return
        attrs = dict(attrs)
        if attrs.get("type", "text/javascript") != "text/javascript":
            raise ValueError("Only the audited classic scripts are supported")
        self.current = {"path": attrs.get("src"), "source": ""}

    def handle_data(self, data):
        if self.current is not None:
            self.current["source"] += data

    def handle_endtag(self, tag):
        if tag == "script" and self.current is not None:
            self.scripts.append(self.current)
            self.current = None


def checked(path, expected):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != expected:
        raise ValueError(f"SHA-256 mismatch: {path.name}: {digest}")
    return path


def obtain(cache, name, pin, supplied=None):
    path = cache / name
    if supplied:
        shutil.copyfile(checked(Path(supplied), pin["sha256"]), path)
    elif not path.exists():
        with urllib.request.urlopen(pin["url"], timeout=60) as response:
            data = response.read(20 * 1024 * 1024 + 1)
        if len(data) > 20 * 1024 * 1024:
            raise ValueError("Archive exceeds experiment download budget")
        path.write_bytes(data)
    return checked(path, pin["sha256"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", required=True, type=Path)
    parser.add_argument("--engine-archive")
    parser.add_argument("--plugin-archive")
    args = parser.parse_args()
    cache = args.cache.resolve()
    if cache.is_relative_to(HERE.parents[2]):
        raise ValueError("Keep downloaded sources/build products outside the repository")
    cache.mkdir(parents=True, exist_ok=True)
    pins = json.loads((HERE / "pins.json").read_text(encoding="utf-8"))
    engine = obtain(cache, "quickjs-ng.tar.gz", pins["engine"], args.engine_archive)
    plugin = obtain(cache, "store.otzplugin", pins["plugin"], args.plugin_archive)
    with tarfile.open(engine) as archive:
        archive.extractall(cache, filter="data")
    source = cache / ("quickjs-" + pins["engine"]["commit"])
    with zipfile.ZipFile(plugin) as archive:
        files = {}
        for name, digest in pins["plugin"]["files"].items():
            data = archive.read(name)
            if hashlib.sha256(data).hexdigest() != digest:
                raise ValueError(f"Unexpected plugin source: {name}")
            files[name] = data.decode("utf-8-sig")
    scripts = Scripts()
    scripts.feed(files["background.html"])
    if [script["path"] for script in scripts.scripts] != ["i18n/en.js", None]:
        raise ValueError("The audited script graph has changed")
    fixture = {
        "archiveSha256": pins["plugin"]["sha256"],
        "manifest": json.loads(files["manifest.json"]),
        "scripts": [files[s["path"]] if s["path"] else s["source"]
                    for s in scripts.scripts],
    }
    (cache / "fixture.json").write_text(
        json.dumps(fixture, ensure_ascii=False), encoding="utf-8")
    (cache / "defines.json").write_text(json.dumps({
        "OTZARIA_DOMLESS_FIXTURE": json.dumps(fixture, ensure_ascii=False),
        "OTZARIA_DOMLESS_ENVIRONMENT": (HERE / "environment.js").read_text(encoding="utf-8")
    }, ensure_ascii=False), encoding="utf-8")
    build = cache / "build"
    subprocess.run(["cmake", "-S", str(HERE), "-B", str(build),
                    f"-DQUICKJS_SOURCE={source}", "-DCMAKE_BUILD_TYPE=Release"],
                   check=True)
    subprocess.run(["cmake", "--build", str(build), "--config", "Release",
                    "--target", "otzaria_domless_probe", "-j", "2"], check=True)
    print(json.dumps({"cache": str(cache), "engine": pins["engine"],
                      "plugin": pins["plugin"]["id"], "productionRuntime": False}))


if __name__ == "__main__":
    main()
