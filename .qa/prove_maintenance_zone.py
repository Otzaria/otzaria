from pathlib import Path
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
source = Path("lib/indexing/repository/indexing_repository.dart")
original = source.read_text(encoding="utf-8")
fixed = "  static Future<void>? _replacementTail;\n\n  /// מנקז ריצות ומונע התחלת ריצות חדשות עד להשלמת החלפת קובצי האינדקס.\n  /// הפעולות סדרתיות; אין לקרוא שוב ל-helper מתוך [action].\n  static Future<T> withIndexingSuspended<T>(Future<T> Function() action) {\n    _indexingSuspensions++;\n    final result = (_replacementTail ?? Future<void>.value()).then((_) async {\n      try {\n        for (final repository in _activeRuns.keys.toList()) {\n          repository.cancelIndexing();\n        }\n        await whenIdle();\n        return await action();\n      } finally {\n        _indexingSuspensions--;\n      }\n    });\n    final settled = result.then<void>((_) {}, onError: (Object _) {});\n    _replacementTail = settled;\n    unawaited(\n      settled.whenComplete(() {\n        if (identical(_replacementTail, settled)) _replacementTail = null;\n      }),\n    );\n    return result;\n  }\n"
baseline = "  static Future<void> _replacementTail = Future<void>.value();\n\n  /// מנקז ריצות ומונע התחלת ריצות חדשות עד להשלמת החלפת קובצי האינדקס.\n  /// הפעולות סדרתיות; אין לקרוא שוב ל-helper מתוך [action].\n  static Future<T> withIndexingSuspended<T>(Future<T> Function() action) {\n    _indexingSuspensions++;\n    final result = _replacementTail.then((_) async {\n      try {\n        for (final repository in _activeRuns.keys.toList()) {\n          repository.cancelIndexing();\n        }\n        await whenIdle();\n        return await action();\n      } finally {\n        _indexingSuspensions--;\n      }\n    });\n    _replacementTail = result.then<void>((_) {}, onError: (Object _) {});\n    return result;\n  }\n"
assert original.count(fixed) == 1
try:
    source.write_text(original.replace(fixed, baseline), encoding="utf-8")
    result = subprocess.run(["flutter", "test", "--no-pub", "--reporter", "expanded",
        "test/indexing/repository/indexing_lifecycle_test.dart", "--plain-name",
        "an idle replacement queue does not retain its previous zone"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = result.stdout.decode("utf-8", errors="replace")
    Path("maintenance-zone-before.log").write_text(output, encoding="utf-8")
    print(output)
    assert result.returncode != 0, "Expected the retained old-zone tail to fail"
    assert "Expected: <2>" in output and "Actual: <1>" in output, "Unexpected regression failure"
    print("EXPECTED NEGATIVE CONTROL: the completed queue retains the previous zone.")
finally:
    source.write_text(original, encoding="utf-8")
