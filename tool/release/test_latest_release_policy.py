import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parent))
import latest_release_policy as policy


def release(tag="1.0.0+10", id=10, draft=False):
    return {"id": id, "tag_name": tag, "draft": draft, "prerelease": False}


def fake_github(latest):
    github = MagicMock()
    github.latest.return_value = latest
    github.request.return_value = release(draft=True)
    return github


class VersionPolicyTest(unittest.TestCase):
    def test_metadata_does_not_raise_version(self):
        self.assertEqual(policy.version_tuple("v1.0.0+10"), (1, 0, 0, 0))
        self.assertEqual(policy.version_tuple("1.0.0+99"), (1, 0, 0, 0))
        self.assertGreater(policy.version_tuple("1.0.0.2"), policy.version_tuple("1.0.0"))
        self.assertGreater(policy.version_tuple("1.0.1"), policy.version_tuple("1.0.0.99"))

    def test_reject_invalid_tags(self):
        for tag in ["V1", "1.0", "1.0.0-dev", "1.0.0.2.1", "nightly"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                policy.version_tuple(tag)

    def test_publish_same_or_lower_version_is_explicitly_not_latest(self):
        for tag in ["1.0.0+9", "2.0.0+5", "1.0.0.1+1"]:
            github = fake_github(release(tag, id=9))
            self.assertFalse(policy.publish(github, 10, "title", "body"))
            payload = github.request.call_args.kwargs["data"]
            self.assertEqual(payload["make_latest"], "false")
            self.assertFalse(payload["prerelease"])
            self.assertFalse(payload["draft"])

    def test_first_release_and_version_increase_promote(self):
        for latest in [None, release("0.9.99.99+9", id=9)]:
            github = fake_github(latest)
            github.latest.side_effect = [latest, release()]
            self.assertTrue(policy.publish(github, 10, "title", "body"))
            self.assertEqual(github.request.call_args.kwargs["data"]["make_latest"], "true")

    def test_hotfix_promotes(self):
        github = fake_github(release("1.0.0+9", id=9))
        github.request.return_value = release("1.0.0.2+10", draft=True)
        github.latest.side_effect = [release(id=9), release("1.0.0.2+10")]
        self.assertTrue(policy.publish(github, 10, "title", "body"))

    def test_latest_changed_before_publish_prevents_downgrade(self):
        github = fake_github(release("1.1.0+20", id=20))
        self.assertFalse(policy.publish(github, 10, "title", "body"))
        self.assertEqual(github.request.call_args.kwargs["data"]["make_latest"], "false")

    def test_api_failure_never_publishes(self):
        github = fake_github(None)
        github.latest.side_effect = RuntimeError("offline")
        with self.assertRaises(RuntimeError):
            policy.publish(github, 10, "title", "body")
        self.assertEqual(github.request.call_count, 1)

    def test_published_release_is_not_overwritten(self):
        github = fake_github(None)
        github.request.return_value = release()
        with self.assertRaises(ValueError):
            policy.publish(github, 10, "title", "body")
        self.assertEqual(github.request.call_count, 1)

    def test_promotion_requires_observed_latest_id(self):
        github = fake_github(None)
        github.latest.side_effect = [None, release("2.0.0", id=99)]
        self.assertFalse(policy.publish(github, 10, "title", "body"))


class GithubTransportTest(unittest.TestCase):
    def test_only_latest_404_means_first_release(self):
        for status in [401, 403, 404, 429, 500]:
            with self.subTest(status=status):
                error = HTTPError("url", status, "error", {}, None)
                with patch.object(policy, "urlopen", side_effect=error):
                    github = policy.Github("Otzaria/otzaria")
                    if status == 404:
                        self.assertIsNone(github.latest())
                    else:
                        with self.assertRaises(HTTPError):
                            github.latest()
                    with self.assertRaises(HTTPError):
                        github.request("releases/10")
                error.close()

    def test_timeout_and_latest_endpoint(self):
        response = MagicMock()
        response.__enter__.return_value = io.StringIO(json.dumps(release()))
        with patch.object(policy, "urlopen", return_value=response) as request:
            self.assertEqual(policy.Github("Otzaria/otzaria").latest(), release())
            self.assertEqual(request.call_args.kwargs["timeout"], 30)
            self.assertTrue(request.call_args.args[0].full_url.endswith("/releases/latest"))

    def test_patch_uses_json_content_type(self):
        response = MagicMock()
        response.__enter__.return_value = io.StringIO("{}")
        with patch.object(policy, "urlopen", return_value=response) as call:
            policy.Github("Otzaria/otzaria").request("releases/1", method="PATCH", data={"draft": False})
            request = call.call_args.args[0]
            self.assertEqual(request.get_header("Content-type"), "application/json")
            self.assertEqual(json.loads(request.data), {"draft": False})

    def test_reject_draft_or_prerelease_as_latest(self):
        for field in ["draft", "prerelease"]:
            github = policy.Github("Otzaria/otzaria")
            github.request = MagicMock(return_value={**release(), field: True})
            with self.assertRaises(ValueError):
                github.latest()


class DeploymentTest(unittest.TestCase):
    def test_checkout_must_match_commit_of_latest_tag(self):
        github = fake_github(release())
        github.request.return_value = {"sha": "approved"}
        with patch.object(policy.subprocess, "check_output", return_value="other\n"):
            with self.assertRaises(ValueError):
                policy.assert_current_checkout(github)
        with patch.object(policy.subprocess, "check_output", return_value="approved\n"):
            policy.assert_current_checkout(github)
        github.request.assert_called_with("commits/1.0.0+10")

    def test_no_latest_never_deploys(self):
        with self.assertRaises(ValueError):
            policy.assert_current_checkout(fake_github(None))


class AnnouncementTest(unittest.TestCase):
    def test_manual_non_latest_release_skips_before_credentials(self):
        path = Path(__file__).resolve().parents[2] / "webhooks" / "main.py"
        spec = importlib.util.spec_from_file_location("announcement_test", path)
        announcement = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(announcement)
        with tempfile.TemporaryDirectory() as directory:
            event = Path(directory) / "event.json"
            event.write_text(json.dumps({"release": release("9.0.0", id=99)}))
            with patch.dict(announcement.os.environ, {"GITHUB_EVENT_PATH": str(event)}), \
                 patch.object(announcement, "Github", return_value=fake_github(release())), \
                 patch.object(announcement, "require_env") as credentials:
                announcement.main()
                credentials.assert_not_called()

    def test_same_tag_with_wrong_id_is_not_latest(self):
        self.assertFalse(policy.is_latest_release(release(id=99), fake_github(release())))

    def test_latest_id_matches(self):
        self.assertTrue(policy.is_latest_release(release(), fake_github(release())))

    def test_failed_api_cannot_authorize_announcement(self):
        github = fake_github(None)
        github.latest.side_effect = RuntimeError("offline")
        with self.assertRaises(RuntimeError):
            policy.is_latest_release(release(), github)


if __name__ == "__main__":
    unittest.main()
