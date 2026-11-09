#!/usr/bin/env python3
"""Decide whether a pull request needs the macOS-runner Apple font probes."""
import argparse
import re
import subprocess
import sys

DEPENDENCY_FILES = ('pubspec.yaml', 'pubspec.lock')
DEPENDENCY_SECTIONS = ('dependencies', 'dev_dependencies', 'dependency_overrides')
EXTRA_PACKAGES = {'ios': (), 'macos': ('window_manager',)}


def relevant_package(name, probe):
    return (name.startswith(('flutter_inappwebview', 'path_provider')) or 'webview' in name
            or name in EXTRA_PACKAGES[probe])


def glob_regex(pattern):
    """GitHub path filters: `*` stays inside one directory, `**` crosses them."""
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith('**/', i):
            out.append('(?:.*/)?')
            i += 3
        elif pattern.startswith('**', i):
            out.append('.*')
            i += 2
        elif pattern[i] == '*':
            out.append('[^/]*')
            i += 1
        elif pattern[i] == '?':
            out.append('[^/]')
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile(''.join(out) + r'\Z')


def workflow_paths(text):
    """The pull_request `paths` list of a workflow, read without a YAML parser."""
    match = re.search(r'^  pull_request:\n(?:    .*\n)*?    paths:\n((?:      [-#].*\n)+)', text, re.M)
    if match is None:
        raise ValueError('The workflow has no pull_request paths filter')
    return [re.fullmatch(r"\s+- '?([^']+?)'?", line)[1] for line in match[1].splitlines()
            if not line.lstrip().startswith('#')]


def blocks(text, indent):
    """Map each key at `indent` spaces to its full block, including nested lines."""
    text = re.sub(r'^[ \t]*#.*\n', '', text, flags=re.M)
    pattern = re.compile(r'^' + ' ' * indent + r'([A-Za-z0-9_-]+):.*\n((?:(?:' + ' ' * (indent + 1) +
                         r'.*|[ \t]*)\n)*)', re.M)
    return {m[1]: m[0] for m in pattern.finditer(text if text.endswith('\n') else text + '\n')}


def lock_changes(old, new, probe):
    before, after = (blocks(blocks(text, 0).get('packages', ''), 2) for text in (old, new))
    return sorted(name for name in set(before) | set(after)
                  if relevant_package(name, probe) and before.get(name) != after.get(name))


def pubspec_changes(old, new, probe):
    before, after = blocks(old, 0), blocks(new, 0)
    changed = []
    for section in DEPENDENCY_SECTIONS:
        old_deps, new_deps = (blocks(text.get(section, ''), 2) for text in (before, after))
        changed += [f'{section}.{name}' for name in sorted(set(old_deps) | set(new_deps))
                    if relevant_package(name, probe) and old_deps.get(name) != new_deps.get(name)]
    old_fonts, new_fonts = (blocks(text.get('flutter', ''), 2).get('fonts') for text in (before, after))
    if old_fonts != new_fonts:
        changed.append('flutter.fonts')
    return changed


def decide(changed_files, paths, read_base, read_head, probe):
    probe_paths = [glob_regex(p) for p in paths if p not in DEPENDENCY_FILES]
    probe_files = sorted(f for f in changed_files if any(p.match(f) for p in probe_paths))
    if probe_files:
        return True, {'probeFiles': probe_files}
    dependencies = []
    if 'pubspec.lock' in changed_files:
        dependencies += lock_changes(read_base('pubspec.lock'), read_head('pubspec.lock'), probe)
    if 'pubspec.yaml' in changed_files:
        dependencies += pubspec_changes(read_base('pubspec.yaml'), read_head('pubspec.yaml'), probe)
    return bool(dependencies), {'dependencies': dependencies}


def git(*args):
    return subprocess.run(['git', *args], check=True, capture_output=True, text=True).stdout


def git_file(revision, path):
    result = subprocess.run(['git', 'show', f'{revision}:{path}'], capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else ''


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--probe', choices=sorted(EXTRA_PACKAGES), required=True)
    parser.add_argument('--workflow', required=True)
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', default='HEAD')
    args = parser.parse_args(argv)
    with open(args.workflow, encoding='utf-8') as stream:
        paths = workflow_paths(stream.read())
    changed = set(git('diff', '--name-only', args.base, args.head).splitlines())
    run, reasons = decide(changed, paths, lambda path: git_file(args.base, path),
                          lambda path: git_file(args.head, path), args.probe)
    print(f'{args.probe} font probe {"required" if run else "skipped"}: {reasons}', file=sys.stderr)
    print(f'run={"true" if run else "false"}')


if __name__ == '__main__':
    main()
