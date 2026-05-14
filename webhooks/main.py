import json
import os

from pyluach import dates
from yemot_api.yemot_api import Yemot
from yemot_api.input_types import RunTzintukMethod
from yemot_api.exceptions import YemotAPIError

from mitmachim import MitmachimClient
# from yemot import split_and_send


def heb_date() -> str:
    today = dates.HebrewDate.today()
    date_str = today.hebrew_date_string()
    return date_str


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


date_str = heb_date()
RELEASE_TAG = os.getenv("RELEASE_TAG", "Unknown")
RELEASE_NAME = os.getenv("RELEASE_NAME", "No Name")
RELEASE_BODY = os.getenv("RELEASE_BODY", "")
RELEASE_URL = os.getenv("RELEASE_URL", "")
GITHUB_EVENT_PATH = os.getenv("GITHUB_EVENT_PATH")
username = require_env("USER_NAME")
password = require_env("PASSWORD")
yemot_token = require_env("TOKEN_YEMOT")
asset_links = load_asset_links(GITHUB_EVENT_PATH)
date_yemot = f"עדכון {date_str}\n"
yemot_path = "ivr2:/2"
tzintuk_list_name = "software update"
yemot_message = f"עדכון {date_str}\nשחרור {RELEASE_NAME}\nפרטים: {RELEASE_BODY}\n"
asset_section = ""
if asset_links:
    asset_section = "\nקבצים מצורפים:\n* " + "\n* ".join(asset_links)
content_mitmachim = (
    f"עדכון {date_str}\n"
    f"שחרור {RELEASE_NAME}\n"
    f"תג: {RELEASE_TAG}\n"
    f"פרטים: {RELEASE_BODY}\n"
    f"{RELEASE_URL}"
    f"{asset_section}"
)

errors = []
client = None

try:
    client = MitmachimClient(username.replace(" ", "+"), password)
    client.login()
    topic_id = 87961
    client.send_post(content_mitmachim, topic_id)
except Exception as error:
    errors.append(f"Mitmachim announcement failed: {error}")
finally:
    if client is not None:
        try:
            client.logout()
        except Exception as error:
            errors.append(f"Mitmachim logout failed: {error}")

# try:
#     split_and_send(yemot_message, date_yemot, yemot_token, yemot_path, tzintuk_list_name)
# except Exception as error:
#     errors.append(f"Yemot announcement failed: {error}")
ins = Yemot(yemot_token)
tzintuk_list_name = "software update"
caller_id = "0773420857"
try:
    ins.run_tzintuk(RunTzintukMethod.TZL, [tzintuk_list_name], caller_id=caller_id, tzintuk_time_out=16)
except YemotAPIError as e:
    print(f"Error: {e}")

if errors:
    raise RuntimeError("\n".join(errors))
