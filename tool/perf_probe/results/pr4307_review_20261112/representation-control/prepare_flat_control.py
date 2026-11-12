#!/usr/bin/env python3
"""Build a representation control while preserving the candidate's common logic."""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


CANDIDATE = "6aa411d774f453331d6821dbb5a68f1c3b78bd78"
FLAT_SOURCE = "8d24d26f6b7eef04ad9eda1f30eb9ea0e53cf546"
PATH = "lib/text_book/bloc/text_book_bloc.dart"
SIGNATURES = {
    "_releaseContentOutsideWindow": "  void _releaseContentOutsideWindow(",
    "_applyContentRanges": "  void _applyContentRanges(",
    "_loadInitialItemRange": (
        "  Future<({List<String> content, List<bool> loadedLineFlags})?>\n"
        "  _loadInitialItemRange("
    ),
    "_contentWithAppliedRange": "  List<String> _contentWithAppliedRange(",
    "_loadedContentFlagsWithAppliedRange": (
        "  List<bool> _loadedContentFlagsWithAppliedRange("
    ),
    "_setLoadedContentFlags": "  void _setLoadedContentFlags(",
}


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])


def sha256(value):
    if isinstance(value, str):
        value = value.encode("utf-8")
    return hashlib.sha256(value).hexdigest()


def method(source, name, flat=False):
    signature = SIGNATURES[name]
    if flat and name == "_loadInitialItemRange":
        signature = "  Future<void> _loadInitialItemRange("
    assert source.count(signature) == 1, (name, "signature")
    start = source.index(signature)
    end = source.index("\n  }\n", start) + len("\n  }\n")
    return source[start:end]


def replace_once(source, old, new):
    assert source.count(old) == 1, ("replacement count", old[:100])
    return source.replace(old, new, 1)


def normalized_outside_methods(source):
    for name in SIGNATURES:
        source = replace_once(source, method(source, name), f"<METHOD:{name}>\n")
    return source


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--worktree", type=Path, required=True)
    parser.add_argument("--outdir", type=Path, required=True)
    args = parser.parse_args()
    assert git(args.worktree, "rev-parse", "HEAD").decode().strip() == CANDIDATE
    candidate = git(args.repo, "show", f"{CANDIDATE}:{PATH}").decode()
    flat = git(args.repo, "show", f"{FLAT_SOURCE}:{PATH}").decode()
    target = args.worktree / PATH
    assert target.read_bytes().decode("utf-8") == candidate, "Control worktree must start unmodified"
    changes = {}
    notes = {}

    # These helpers have no candidate-specific behavioral changes.
    for name in (
        "_contentWithAppliedRange",
        "_loadedContentFlagsWithAppliedRange",
        "_setLoadedContentFlags",
    ):
        changes[name] = method(flat, name, flat=True)
        notes[name] = "Exact current-dev method bytes."

    name = "_releaseContentOutsideWindow"
    release = method(flat, name, flat=True)
    release = replace_once(
        release,
        "    var hasLoadedOutsideWindow = false;",
        "    var hasLoadedOutsideWindow = flags.length != content.length;",
    )
    release = replace_once(
        release,
        "      if (content[i].isNotEmpty) {",
        "      if (content[i].isNotEmpty || (i < flags.length && flags[i])) {",
    )
    changes[name] = release
    notes[name] = (
        "Current-dev flat scan/copy method, with candidate-equivalent change "
        "detection for unequal flag length and loaded empty lines outside the "
        "retained window. Restoring the dev early return verbatim would change "
        "behavior beyond representation."
    )

    name = "_applyContentRanges"
    apply = method(candidate, name)
    flat_apply = method(flat, name, flat=True)
    apply = replace_once(
        apply,
        "    if ((currentState.content is! ChunkedList<String> ||\n"
        "            _loadedContentFlags is! ChunkedList<bool>) &&\n"
        "        _loadedContentFlags.length >= currentState.content.length &&",
        "    if (_loadedContentFlags.length >= currentState.content.length &&",
    )
    apply = replace_once(
        apply,
        "    final nextContent = ChunkedList<String>.from(\n"
        "      currentState.content,\n"
        "      defaultValue: '',\n"
        "    ).edit();",
        "    final nextContent = List<String>.of(currentState.content);",
    )
    apply = replace_once(
        apply,
        "    final nextLoadedFlags = ChunkedList<bool>.from(\n"
        "      _loadedContentFlags,\n"
        "      defaultValue: false,\n"
        "    ).edit();\n"
        "    if (nextLoadedFlags.length < nextContent.length) {\n"
        "      nextLoadedFlags.length = nextContent.length;\n"
        "    }",
        "    final nextLoadedFlags = List<bool>.of(_loadedContentFlags);\n"
        "    var hasContentChanged = false;\n"
        "    var hasLoadedFlagsChanged = false;\n"
        "    if (nextLoadedFlags.length < nextContent.length) {\n"
        "      hasLoadedFlagsChanged = true;\n"
        "      nextLoadedFlags.addAll(\n"
        "        List<bool>.filled(nextContent.length - nextLoadedFlags.length, false),\n"
        "      );\n"
        "    }",
    )
    begin = apply.index("    for (final range in applicable) {", apply.index("    final nextLoadedFlags"))
    end = apply.index("\n    if (!nextContent.changed", begin)
    flat_begin = flat_apply.index("    for (final range in applicable) {", flat_apply.index("    final nextLoadedFlags"))
    flat_end = flat_apply.index("\n    void markAllRanges()", flat_begin)
    apply = apply[:begin] + flat_apply[flat_begin:flat_end] + apply[end:]
    apply = replace_once(
        apply,
        "    if (!nextContent.changed && !nextLoadedFlags.changed) {",
        "    if (!hasContentChanged && !hasLoadedFlagsChanged) {",
    )
    apply = replace_once(
        apply,
        "    _setLoadedContentFlags(currentState.book, nextLoadedFlags.build());",
        "    _setLoadedContentFlags(currentState.book, nextLoadedFlags);",
    )
    apply = replace_once(apply, "          content: nextContent.build(),", "          content: nextContent,")
    changes[name] = apply
    notes[name] = (
        "Candidate common method, markAllRanges, no-op guard semantics, "
        "revision/contentChanges emission and lazy scanOnly retained. "
        "List copies and the changed-range loop come from current dev. "
        "Candidate flag-length normalization is retained with flat addAll. "
        "The representation type condition is removed because this control "
        "uses flat lists on all normal production paths."
    )

    name = "_loadInitialItemRange"
    initial = method(candidate, name)
    flat_initial = method(flat, name, flat=True)
    begin = initial.index("    final nextContent = ChunkedList<String>.from(")
    end = initial.index("    _markLoadedContentRange(", begin)
    flat_begin = flat_initial.index("    for (var offset = 0;")
    flat_end = flat_initial.index("    _markLoadedContentRange(", flat_begin)
    initial = initial[:begin] + flat_initial[flat_begin:flat_end] + initial[end:]
    initial = replace_once(
        initial,
        "    return (content: nextContent.build(), loadedLineFlags: flags);",
        "    return (content: content, loadedLineFlags: loadedLineFlags);",
    )
    changes[name] = initial
    notes[name] = (
        "Candidate record/null return contract, getRange readiness check, "
        "error handling and post-await isClosed guard retained. The initial "
        "flat assignment loop and setFlags call come verbatim from current "
        "dev. The sole caller only invokes this helper for newly prepared "
        "initial lists, excludes preserveState on a loaded state, and has "
        "not emitted those lists. No extra full-list copy is introduced."
    )

    control = candidate
    for name, replacement in changes.items():
        control = replace_once(control, method(candidate, name), replacement)
    assert normalized_outside_methods(control) == normalized_outside_methods(candidate)
    for name in SIGNATURES:
        assert method(control, name) == changes[name]
    target.write_bytes(control.encode("utf-8"))
    args.outdir.mkdir(parents=True, exist_ok=True)
    provenance = {
        "candidate_sha": CANDIDATE,
        "flat_algorithm_source_sha": FLAT_SOURCE,
        "path": PATH,
        "candidate_file_sha256": sha256(candidate),
        "flat_source_file_sha256": sha256(flat),
        "control_file_sha256": sha256(control),
        "outside_changed_methods_byte_identical": True,
        "methods": [
            {
                "name": name,
                "candidate_sha256": sha256(method(candidate, name)),
                "flat_source_sha256": sha256(method(flat, name, flat=True)),
                "control_sha256": sha256(method(control, name)),
                "description": notes[name],
            }
            for name in SIGNATURES
        ],
        "shared_unchanged": [
            "All code outside the six methods, including _onLoadTextBook preserve/close/metadata logic",
            "_withInlineNotesCommentator and initial inline-note dispatch",
            "lib/text_book/utils/inline_notes_utils.dart",
            "lib/text_book/view/page_shape/utils/page_shape_notes_column.dart",
            "All contentVersion/revision consumer optimizations",
            "_onApplyFullBookContent and all background loading/scheduling",
            "All measurement harness, fixtures, tests, workflows and dependency lockfiles",
        ],
        "validation": {
            "source_structure_checks": "passed",
            "flutter_analyze": "pending CI; flutter and dart absent from PATH",
            "flutter_behavioral_tests": "pending CI",
            "windows_profile_build": "pending CI for both fixed source SHAs",
        },
    }
    (args.outdir / "source_provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"changed_methods": list(changes), "control_sha256": sha256(control)}))


if __name__ == "__main__":
    main()
