import os
from pathlib import Path
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

fixture = Path("test/indexing/repository/indexing_repository_test.dart")
original = fixture.read_text(encoding="utf-8")
fixed = "        await CacheDatabaseHolder.instance.close();\n        AppPaths.debugOverrideDataRootPath(null);\n        try {\n          expect(await FindRefDbIsolate.suspendForExternalWrite(), isTrue);\n          await tempDir.delete(recursive: true);\n        } finally {\n          await FindRefDbIsolate.resumeAfterExternalWrite();\n        }"
baseline = "        await CacheDatabaseHolder.instance.close();\n        AppPaths.debugOverrideDataRootPath(null);\n        try {\n          await tempDir.delete(recursive: true);\n        } catch (error) {\n          io.stderr.writeln('QA fixture cleanup failed: $error');\n          try {\n            final remaining = await tempDir\n                .list(recursive: true, followLinks: false)\n                .toList();\n            io.stderr.writeln('QA remaining entries: ${remaining.length}');\n            for (final entry in remaining) {\n              io.stderr.writeln(\n                'QA remaining ${entry.runtimeType}: '\n                '${p.relative(entry.path, from: tempDir.path)}',\n              );\n            }\n          } catch (listingError) {\n            io.stderr.writeln('QA cannot list remaining files: $listingError');\n          }\n          rethrow;\n        }"
fixed_setup = "        await SqliteDataProvider.instance.initialize();\n        await FindRefDbIsolate.resumeAfterExternalWrite();\n        previousRegistry = AttachedLibraryRegistry.instance;"
baseline_setup = "        await SqliteDataProvider.instance.initialize();\n        previousRegistry = AttachedLibraryRegistry.instance;"
assert original.count(fixed) == 1, "Expected exactly one fixture cleanup block"
assert original.count(fixed_setup) == 1
assert original.count("import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';\n") == 1
try:
    before = original.replace(fixed, baseline).replace(fixed_setup, baseline_setup).replace("import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';\n", "")
    fixture.write_text(before, encoding="utf-8")
    command = ["flutter", "test", "--no-pub", "--reporter", "expanded",
               str(fixture), "--name", "מסד שהתרוקן"]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            shell=os.name == "nt")
    output = result.stdout.decode("utf-8", errors="replace")
    Path("fixture-cleanup-before.log").write_text(output, encoding="utf-8")
    print(output)
    assert result.returncode != 0, "Expected old fixture to fail on the held Windows database"
    assert "errno = 32" in output, "Failure was not the observed Windows file-sharing violation"
    assert any(line.startswith("QA remaining ") and line.endswith(": seforim.db") for line in output.splitlines()), "Expected the held seforim.db in the diagnostic output"
    print("EXPECTED NEGATIVE CONTROL: the old fixture leaves seforim.db open.")
finally:
    fixture.write_text(original, encoding="utf-8")
