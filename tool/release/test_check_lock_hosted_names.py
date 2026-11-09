import unittest

from check_lock_hosted_names import validate_hosted_names


def lock(body: str) -> str:
    return "packages:\n" + body + "sdks:\n  dart: \"^3.12.0\"\n"


GOOD = """  flutter_markdown_plus:
    dependency: "direct main"
    description:
      name: flutter_markdown_plus
      sha256: "aaaa"
      url: "https://pub.dev"
    source: hosted
    version: "1.0.12"
  a_fork:
    dependency: "direct main"
    description:
      path: packages/a_fork
      ref: abc123
      resolved-ref: def456
      url: "https://github.com/Otzaria/a_fork"
    source: git
    version: "0.5.2"
"""


class HostedPackageLockMetadataTests(unittest.TestCase):
    def test_valid_hosted_and_git_package(self):
        self.assertEqual(validate_hosted_names(lock(GOOD)), [])

    def test_catches_original_markdown_rebase_regression(self):
        bad = GOOD.replace("      name: flutter_markdown_plus", "      name: flutter_markdown")
        errors = validate_hosted_names(lock(bad))
        self.assertEqual(len(errors), 1)
        self.assertIn("description.name 'flutter_markdown'", errors[0])

    def test_missing_hosted_name_fails(self):
        bad = GOOD.replace("      name: flutter_markdown_plus\n", "")
        self.assertEqual(len(validate_hosted_names(lock(bad))), 1)

    def test_missing_hosted_version_fails(self):
        bad = GOOD.replace('    version: "1.0.12"\n', "")
        self.assertEqual(len(validate_hosted_names(lock(bad))), 1)

    def test_git_name_is_not_checked_as_hosted(self):
        custom = GOOD.replace(
            "    source: git\n",
            "      name: a-different-remote-name\n    source: git\n",
        )
        self.assertEqual(validate_hosted_names(lock(custom)), [])

    def test_invalid_hosted_version_fails(self):
        for value in (
            "nonsense", "1.0", "^1.0.0", "1.2.3+bad..build",
            "1.2.3-", "1.2.3+", "1.2.3-dev..1", "1.2.3-dev_1",
            "1.2.3+build_1", "1.2.3+build+2",
        ):
            with self.subTest(value=value):
                bad = GOOD.replace('version: "1.0.12"', f"version: {value}")
                errors = validate_hosted_names(lock(bad))
                self.assertEqual(len(errors), 1)
                self.assertIn("invalid version", errors[0])

    def test_valid_prerelease_and_build_version(self):
        for value in ("0.0.0", "1.2.3-dev.1", "2.1.0+42", "3.4.5-rc.1+build.2"):
            with self.subTest(value=value):
                good = GOOD.replace('version: "1.0.12"', f'version: "{value}"')
                self.assertEqual(validate_hosted_names(lock(good)), [])

    def test_dart_pub_versions_allow_leading_zeros(self):
        for value in (
            "01.2.3", "1.02.3", "1.2.03", "01.02.03",
            "00.00.00", "01.02.03-01.dev-2+001.build-2",
            "1.2.3-01+002", "1.2.3--+-",
        ):
            with self.subTest(value=value):
                good = GOOD.replace('version: "1.0.12"', f'version: "{value}"')
                self.assertEqual(validate_hosted_names(lock(good)), [])

    def test_hosted_name_must_be_inside_description(self):
        bad = GOOD.replace("    description:\n", "    unexpected:\n", 1)
        errors = validate_hosted_names(lock(bad))
        self.assertEqual(len(errors), 1)
        self.assertIn("description.name None", errors[0])

    def test_mixed_hosted_git_path_sdk(self):
        tail = """  local:
    description:
      path: packages/local
    source: path
    version: "1.0.0"
  flutter:
    description: flutter
    source: sdk
    version: "0.0.0"
"""
        self.assertEqual(validate_hosted_names(lock(GOOD + tail)), [])

    def test_missing_packages_section_fails(self):
        self.assertTrue(validate_hosted_names("sdks:\n  dart: ^3.12.0\n"))

    def test_lockfile_with_only_nonhosted_packages_is_valid(self):
        nonhosted = (
            "  only_git:\n    source: git\n    version: \"0.3.0\"\n"
            "  only_path:\n    source: path\n    version: \"1.0.0\"\n"
            "  flutter:\n    description: flutter\n    source: sdk\n"
            "    version: \"0.0.0\"\n"
        )
        self.assertEqual(validate_hosted_names(lock(nonhosted)), [])
        self.assertEqual(validate_hosted_names(lock("")), [])

    def test_final_package_validated_without_sdks(self):
        self.assertEqual(validate_hosted_names("packages:\n" + GOOD), [])

    def test_duplicate_packages_section_fails(self):
        self.assertTrue(
            any("duplicate packages section" in e for e in
                validate_hosted_names(lock(GOOD) + "packages:\n" + GOOD))
        )


if __name__ == "__main__":
    unittest.main()
