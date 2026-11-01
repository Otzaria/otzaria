"""פרסום הכרזה על גרסה חדשה: פורום אוצריא + צינתוק ימות."""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tool" / "release"))
from latest_release_policy import Github, is_latest_release


CHANGELOG_PATH = Path("assets/יומן שינויים.md")
FORUM_BASE_URL = "https://otzaria.org/forum"
FORUM_TOPIC_ID = 1373
ISRAEL_TZ = ZoneInfo("Asia/Jerusalem")


def heb_date(now: datetime | None = None) -> str:
    """התאריך העברי לפי שעון ישראל; אחרי השקיעה בירושלים — "אור ל" היום הבא."""
    from astral import LocationInfo
    from astral.sun import sunset
    from pyluach import dates

    now = now or datetime.now(ISRAEL_TZ)
    jerusalem = LocationInfo("Jerusalem", "Israel", "Asia/Jerusalem", 31.778, 35.235)
    day = dates.GregorianDate.from_pydate(now.date()).to_heb()
    if now >= sunset(jerusalem.observer, now.date(), tzinfo=ISRAEL_TZ):
        return f"אור ל{(day + 1).hebrew_date_string()}"
    return day.hebrew_date_string()


def require_env(name: str) -> str:
    value = os.getenv(name)
    if value is None or not value.strip():
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value.strip()


def load_asset_links(event_path: str | None) -> list[str]:
    if not event_path:
        return []
    with open(event_path, "r", encoding="utf-8") as file:
        event_data = json.load(file)
    assets = event_data.get("release", {}).get("assets", [])
    return [f"[{asset['name']}]({asset['browser_download_url']})" for asset in assets]


def extract_version(tag: str) -> str:
    """מחלץ את הגרסה מתוך תג ('0.9.92+631' → '0.9.92', '0.9.97.2' → '0.9.97.2')."""
    match = re.match(r"(\d+\.\d+\.\d+(?:\.\d+)?)", tag)
    return match.group(1) if match else tag


def load_changelog_section(version: str) -> str:
    """שולף את הסעיף של הגרסה מתוך 'יומן שינויים.md'.

    מצפה למבנה ``* **<גרסה>**`` ואחריו רשימת בולטים בהזחה,
    ומסיים ברגע שמתחיל סעיף הגרסה הבא או בסוף הקובץ.
    """
    if not CHANGELOG_PATH.is_file():
        return ""
    text = CHANGELOG_PATH.read_text(encoding="utf-8")
    pattern = re.compile(
        rf"^\* \*\*{re.escape(version)}\*\*[ \t]*\n(.*?)(?=^\* \*\*|\Z)",
        re.DOTALL | re.MULTILINE,
    )
    match = pattern.search(text)
    if not match:
        return ""
    # ניקוי הזחה משורות הבולטים (מ-"  - " ל-"- ")
    body = match.group(1).rstrip()
    return re.sub(r"^[ \t]+-\s", "- ", body, flags=re.MULTILINE)


def build_forum_message(
    version: str,
    release_name: str,
    release_url: str,
    changelog: str,
    assets: list[str],
) -> str:
    title = release_name.strip() if release_name.strip() else f"גרסה {version}"
    parts = [
        f"## {title}",
        f"_עדכון {heb_date()}_",
        "",
    ]
    if changelog:
        parts.append("### מה חדש")
        parts.append(changelog)
        parts.append("")
    if release_url:
        parts.append(f"[לדף השחרור בגיטהאב]({release_url})")
        parts.append("")
    if assets:
        parts.append("### קבצים להורדה")
        parts.extend(f"* {asset}" for asset in assets)
    return "\n".join(parts).rstrip() + "\n"


def main() -> None:
    release_tag = os.getenv("RELEASE_TAG", "Unknown")
    release_name = os.getenv("RELEASE_NAME", "")
    release_url = os.getenv("RELEASE_URL", "")
    event_path = os.getenv("GITHUB_EVENT_PATH")

    if not event_path:
        raise RuntimeError("A release event is required before announcing")
    with open(event_path, encoding="utf-8") as source:
        release = json.load(source).get("release")
    if not is_latest_release(release, Github()):
        print("Release is not Latest; announcement skipped")
        return

    from yemot_api.yemot_api import Yemot
    from yemot_api.input_types import RunTzintukMethod
    from yemot_api.exceptions import YemotAPIError
    from forum import NodeBBClient

    username = require_env("USER_NAME")
    password = require_env("PASSWORD")
    yemot_token = require_env("TOKEN_YEMOT")

    version = extract_version(release_tag)
    changelog = load_changelog_section(version)
    if not changelog:
        print(f"Warning: no changelog section found for version {version}")
    asset_links = load_asset_links(event_path)
    content = build_forum_message(
        version, release_name, release_url, changelog, asset_links
    )

    errors: list[str] = []

    client: NodeBBClient | None = None
    try:
        client = NodeBBClient(FORUM_BASE_URL, username.replace(" ", "+"), password)
        client.login()
        client.send_post(content, FORUM_TOPIC_ID)
        print(f"Forum announcement posted to topic {FORUM_TOPIC_ID}")
    except Exception as error:
        errors.append(f"Forum announcement failed: {error}")
    finally:
        if client is not None:
            try:
                client.logout()
            except Exception as error:
                errors.append(f"Forum logout failed: {error}")

    yemot = Yemot(yemot_token)
    try:
        yemot.run_tzintuk(
            RunTzintukMethod.TZL,
            ["software update"],
            caller_id="0773420857",
            tzintuk_time_out=16,
        )
    except YemotAPIError as error:
        print(f"Yemot error: {error}")

    if errors:
        raise RuntimeError("\n".join(errors))


if __name__ == "__main__":
    main()
