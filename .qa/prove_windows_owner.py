import os
from pathlib import Path
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
fixture = Path("test/settings/dialogs/library_setup_dialog_test.dart")
original = fixture.read_text(encoding="utf-8")
owner = "  DialogOwner.mainWindowHwnd = 7;"
assert original.count(owner) == 1
try:
    fixture.write_text(original.replace(owner, "  DialogOwner.mainWindowHwnd = null;"), encoding="utf-8")
    result = subprocess.run(["flutter", "test", "--no-pub", "--reporter", "expanded",
        str(fixture), "--plain-name", "תיקייה קריאה: פירוט לפי רכיב ואישור פעיל"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, shell=os.name == "nt")
    output = result.stdout.decode("utf-8", errors="replace")
    Path("windows-owner-before.log").write_text(output, encoding="utf-8")
    print(output)
    assert result.returncode != 0, "Expected the missing owner to stop the fake picker"
    assert "Expected: <1>" in output and "Actual: <0>" in output, "Unexpected failure before the picker assertion"
    print("EXPECTED NEGATIVE CONTROL: the ownerless Windows fixture never invokes its fake picker.")
finally:
    fixture.write_text(original, encoding="utf-8")
