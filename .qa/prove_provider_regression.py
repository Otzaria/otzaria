from pathlib import Path
import subprocess

target = Path("lib/data/data_providers/tantivy_data_provider.dart")
original = target.read_text()
try:
    target.write_text(Path(".qa/tantivy_data_provider_before.txt").read_text())
    result = subprocess.run(
        ["flutter", "test", "--no-pub",
         "test/data/data_providers/tantivy_data_provider_lifecycle_test.dart",
         "--plain-name", "concurrent and repeated disposal close each engine once",
         "--reporter", "expanded"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
finally:
    target.write_text(original)
Path("provider-before.log").write_text(result.stdout)
print(result.stdout)
assert result.returncode != 0, "The baseline unexpectedly passed"
assert "Expected:" in result.stdout, "Expected an assertion failure, not an infrastructure failure"
assert "Failed to load" not in result.stdout, "The baseline did not compile"
assert "concurrent and repeated disposal close each engine once" in result.stdout
print("Confirmed: the same disposal regression fails before the lifecycle change")
