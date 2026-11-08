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

    def test_missing_packages_section_fails(self):
        self.assertTrue(validate_hosted_names("sdks:\n  dart: ^3.12.0\n"))

    def test_empty_hosted_map_fails(self):
        self.assertTrue(validate_hosted_names(lock("  only_git:\n    source: git\n")))

    def test_final_package_validated_without_sdks(self):
        self.assertEqual(validate_hosted_names("packages:\n" + GOOD), [])

    def test_duplicate_packages_section_fails(self):
        self.assertTrue(
            any("duplicate packages section" in e for e in
                validate_hosted_names(lock(GOOD) + "packages:\n" + GOOD))
        )


if __name__ == "__main__":
    unittest.main()
