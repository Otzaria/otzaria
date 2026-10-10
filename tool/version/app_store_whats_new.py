"""Writes App Store "What's New" for the current version from the changelog.

Usage: app_store_whats_new.py <output_file>
Same items as Google Play (play_whats_new.py), within the App Store's 4000-char limit.
"""

import sys
from pathlib import Path

import play_whats_new

APP_STORE_LIMIT = 4000


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("Usage: app_store_whats_new.py <output_file>")
    play_whats_new.PLAY_LIMIT = APP_STORE_LIMIT
    version = play_whats_new.changelog_version()
    lines = play_whats_new.CHANGELOG.read_text(encoding="utf-8").splitlines()
    notes = play_whats_new.build_notes(play_whats_new.section_items(lines, version))
    if not notes:
        sys.exit(f"Error: no changelog items fit for {version}")
    out_file = Path(sys.argv[1])
    out_file.parent.mkdir(parents=True, exist_ok=True)
    out_file.write_text(notes, encoding="utf-8")
    print(f"What's new for {version}: {len(notes.splitlines())} items, {len(notes)} chars")


if __name__ == "__main__":
    main()
