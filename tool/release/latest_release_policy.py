"""מדיניות פרסום והפצה: רק Latest מוסמך להפעיל עדכונים."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.error import HTTPError
from urllib.request import Request, urlopen


_VERSION = re.compile(r"v?(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?(?:\+[0-9A-Za-z.-]+)?")


def version_tuple(tag):
    match = _VERSION.fullmatch(tag)
    if match is None:
        raise ValueError(f"Invalid release version: {tag}")
    return tuple(int(part or 0) for part in match.groups())


class Github:
    def __init__(self, repository=None):
        self.repository = repository or os.environ["GITHUB_REPOSITORY"]

    def request(self, path, *, method="GET", data=None, missing_ok=False):
        headers = {"Accept": "application/vnd.github+json", "User-Agent": "Otzaria-release"}
        token = os.getenv("GH_TOKEN") or os.getenv("GITHUB_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if data is not None:
            headers["Content-Type"] = "application/json"
        body = None if data is None else json.dumps(data).encode()
        request = Request(f"https://api.github.com/repos/{self.repository}/{path}",
                          data=body, headers=headers, method=method)
        try:
            with urlopen(request, timeout=30) as response:
                return json.load(response)
        except HTTPError as error:
            if error.code == 404 and missing_ok:
                return None
            raise

    def latest(self):
        release = self.request("releases/latest", missing_ok=True)
        if release is not None:
            if release.get("draft") is not False or release.get("prerelease") is not False:
                raise ValueError("Invalid Latest release")
            version_tuple(release["tag_name"])
        return release


def is_latest_release(release, github):
    if not release or not isinstance(release.get("id"), int):
        return False
    latest = github.latest()
    return latest is not None and release["id"] == latest["id"]


def publish(github, release_id, title, body):
    release = github.request(f"releases/{release_id}")
    if release.get("draft") is not True:
        raise ValueError("Only a draft release can be published")
    candidate = version_tuple(release["tag_name"])
    latest = github.latest()
    promote = latest is None or candidate > version_tuple(latest["tag_name"])
    github.request(f"releases/{release_id}", method="PATCH", data={
        "name": title, "body": body, "draft": False,
        "prerelease": False, "make_latest": "true" if promote else "false",
    })
    return promote and is_latest_release(release, github)


def assert_current_checkout(github):
    latest = github.latest()
    if latest is None:
        raise ValueError("No Latest release is available for deployment")
    commit = github.request(f"commits/{latest['tag_name']}")["sha"]
    current = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if commit != current:
        raise ValueError("Deployment requires the commit published as Latest")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", type=int)
    parser.add_argument("--title")
    parser.add_argument("--body-file", type=Path)
    parser.add_argument("--assert-current-checkout", action="store_true")
    args = parser.parse_args()
    github = Github()
    if args.assert_current_checkout:
        assert_current_checkout(github)
    elif args.publish is not None and args.title and args.body_file:
        latest = publish(github, args.publish, args.title,
                         args.body_file.read_text(encoding="utf-8"))
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"is_latest={str(latest).lower()}\n")
    else:
        parser.error("Specify --assert-current-checkout or --publish with title and body")


if __name__ == "__main__":
    main()
