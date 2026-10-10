"""גרסת iOS: major.minor.(patch * 100 + hotfix), בכל פרסום רגיל או תיקון."""

import json
import re
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("שימוש: app_store_build_name.py <pubspec.yaml> <version.json>")
    data = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    version = data["version"]
    hotfix_text = str(data.get("hotfix", 0))
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or not re.fullmatch(
        r"0|[1-9][0-9]?", hotfix_text
    ):
        sys.exit("גרסה או מספר תיקון לא תקינים ב-version.json")
    major, minor, patch = map(int, version.split("."))
    hotfix = int(hotfix_text)
    if minor > 99 or patch > 99:
        sys.exit("רכיבי minor ו-patch חייבים להיות בין 0 ל-99")
    code = major * 1000000 + minor * 10000 + patch * 100 + hotfix
    release = re.search(
        r"^version:[ \t]*(\S+)[ \t]*$",
        Path(sys.argv[1]).read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if release is None or release[1] != f"{version}+{code}":
        sys.exit("גרסת pubspec ומספר הבנייה אינם תואמים ל-version.json")
    build_name = f"{major}.{minor}.{patch * 100 + hotfix}"
    if len(build_name) > 18:
        sys.exit("מספר גרסת App Store ארוך מדי")
    print(build_name)


if __name__ == "__main__":
    main()
