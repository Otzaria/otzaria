"""Writes Google Play "What's new" for the current version from the changelog.

Usage: play_whats_new.py <output_dir>
Creates <output_dir>/whatsnew-iw-IL for r0adkll/upload-google-play's whatsNewDirectory.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHANGELOG = ROOT / "assets" / "יומן שינויים.md"
VERSION_FILE = ROOT / "tool" / "version" / "version.json"
LOCALE = "iw-IL"
PLAY_LIMIT = 500
DESKTOP_ONLY_MARKER = "(במחשב)"


def changelog_version() -> str:
    data = json.loads(VERSION_FILE.read_text(encoding="utf-8"))
    hotfix = int(data.get("hotfix", 0))
    return f"{data['version']}.{hotfix}" if hotfix > 0 else data["version"]


def section_items(lines: list[str], version: str) -> list[str]:
    header = f"* **{version}**"
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == header)
    except StopIteration:
        sys.exit(f"Error: no '{header}' section in {CHANGELOG.name}")
    items = []
    for line in lines[start + 1 :]:
        if line.startswith("* **"):
            break
        if line.startswith("  - "):
            items.append(line)
    return items


def build_notes(items: list[str]) -> str:
    # Whole items only, in changelog order: stop at the first one that does not fit.
    notes: list[str] = []
    for item in items:
        if DESKTOP_ONLY_MARKER in item:
            continue
        line = "• " + item[4:].replace("**", "").strip()
        if len("\n".join(notes + [line])) > PLAY_LIMIT:
            break
        notes.append(line)
    return "\n".join(notes)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("Usage: play_whats_new.py <output_dir>")
    version = changelog_version()
    lines = CHANGELOG.read_text(encoding="utf-8").splitlines()
    notes = build_notes(section_items(lines, version))
    if not notes:
        sys.exit(f"Error: no changelog items fit for {version}")
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"whatsnew-{LOCALE}").write_text(notes, encoding="utf-8")
    print(f"What's new for {version}: {len(notes.splitlines())} items, {len(notes)} chars")


if __name__ == "__main__":
    main()
