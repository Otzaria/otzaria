"""Fetch Jastrow's list of Hebrew/Aramaic abbreviations from Sefaria.

  py tool/acronyms_pipeline/collect_jastrow.py jastrow_raw.json

Version: Jastrow, London, Luzac, 1903 (license in Sefaria's metadata: Public Domain).  The raw line and its 1-based
number are kept, so every candidate can cite "Jastrow, Hebrew or Aramaic Abbreviations, שורה N".
Needs `requests` (and `truststore` behind a TLS-inspecting proxy; optional).
"""
import json
import sys

import requests

try:
    import truststore

    truststore.inject_into_ssl()
except ImportError:
    pass

URL = "https://www.sefaria.org/api/v3/texts/Jastrow%2C_Hebrew_or_Aramaic_Abbreviations"


def main(out):
    r = requests.get(URL, headers={"User-Agent": "otzaria-acronyms-research"}, timeout=120)
    r.raise_for_status()
    rows = []
    for v in r.json()["versions"]:
        if isinstance(v["text"], list):
            for i, line in enumerate(v["text"], 1):
                rows.append({"line": i, "raw": line, "version": v.get("versionTitle"), "license": v.get("license")})
    with open(out, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=1)
    sys.stdout.reconfigure(encoding="utf-8")
    print(f"{len(rows)} lines -> {out}")


if __name__ == "__main__":
    main(sys.argv[1])
