from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname
import ctypes
import json
import os
import subprocess

config = Path(".dart_tool/package_config.json").resolve()
packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
roots = {
    item["name"]: Path(url2pathname(urlparse(urljoin(config.as_uri(), item["rootUri"])).path))
    for item in packages
    if item["name"] in {"zstandard_native", "zstandard_windows"}
}
source = roots["zstandard_native"] / "src" / "zstd"
assert (source / "common").is_dir(), source
build = Path("build/test_zstd").resolve()
environment = dict(os.environ, ZSTD_ROOT=str(source))
subprocess.run(
    ["cmake", "-S", str(roots["zstandard_windows"] / "zstd_build"),
     "-B", str(build), "-A", "x64"],
    env=environment, check=True,
)
subprocess.run(
    ["cmake", "--build", str(build), "--config", "Release"],
    env=environment, check=True,
)
library = build / "Release" / "zstandard_windows.dll"
assert library.is_file(), library
version = ctypes.CDLL(str(library)).ZSTD_versionNumber()
print(f"Built the locked zstandard dependency: version={version}, path={library}")
with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as output:
    output.write(f"OTZARIA_ZSTD_LIB={library}\n")
