import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1] / 'repo4307'
BASE = '8d24d26f6b7eef04ad9eda1f30eb9ea0e53cf546'
CANDIDATE = '75276fe11dcf679f4ffe81eae17f842ba53c6349'
PROVENANCE = []


def source(ref, path):
    return subprocess.check_output(['git', '-C', str(REPO), 'show', f'{ref}:{path}']).decode()


def extract(text, name, indent):
    start = re.search(r'^' + ' ' * indent + r'[A-Za-z_][^\n]*\b' + re.escape(name) + r'\(', text, re.M)
    if not start:
        raise ValueError(name)
    end = re.search(r'^' + ' ' * indent + r'}\n', text[start.start():], re.M)
    if not end:
        raise ValueError('No end for ' + name)
    result = text[start.start():start.start() + end.end()]
    return result, text[:start.start()].count('\n') + 1


def record(ref, path, name, value, line):
    PROVENANCE.append({'ref': ref, 'path': path, 'symbol': name, 'line': line,
                       'sha256': hashlib.sha256(value.encode()).hexdigest()})


parts = ["part of 'benchmark.dart';\n"]
for name, ref in [('BaselineEngine', BASE), ('CandidateEngine', CANDIDATE)]:
    path = 'lib/text_book/bloc/text_book_bloc.dart'
    text = source(ref, path)
    parts.append(f'class {name} extends Engine {{\n  {name}(super.snapshot);\n')
    for method in ['_applyContentRanges', '_releaseContentOutsideWindow', '_setLoadedContentFlags', '_onApplyFullBookContent',
                   '_contentWithAppliedRange', '_loadedContentFlagsWithAppliedRange']:
        value, line = extract(text, method, 2)
        record(ref, path, method, value, line)
        if name == 'CandidateEngine' and method == '_applyContentRanges':
            # Isolate representation: retain current-dev eager note input on both sides.
            old = 'scanOnly: applicable.expand((range) => range.lines),'
            assert old in value
            value = value.replace(old, 'scanOnly: [for (final range in applicable) ...range.lines],')
        parts.append(value)
    parts.append('}\n')
(ROOT / 'engine_sources.dart').write_text('\n'.join(parts))

path = 'lib/text_book/models/chunked_list.dart'
value = source(CANDIDATE, path)
record(CANDIDATE, path, 'entire file', value, 1)
(ROOT / 'chunked_list.dart').write_text(value)

parts = ["part of 'benchmark.dart';\n"]
path = 'lib/text_book/utils/reading_extent_estimates.dart'
text = source(BASE, path)
for name in ['_rawCharactersExceed', '_countChunks', 'visibleReadingCharCount']:
    value, line = extract(text, name, 0)
    record(BASE, path, name, value, line)
    parts.append(value)
(ROOT / 'consumer_sources.dart').write_text('\n'.join(parts))

path = 'lib/text_book/models/content_line_changes.dart'
value = source(BASE, path)
record(BASE, path, 'entire file before import/annotation removal', value, 1)
value = value.replace("import 'package:flutter/foundation.dart';", '').replace('@immutable\n', '')
(ROOT / 'content_line_changes.dart').write_text(value)

(ROOT / 'source_provenance.json').write_text(json.dumps({
    'baseline': BASE, 'candidate': CANDIDATE,
    'extraction': 'Engine methods and consumer bodies copied verbatim, except candidate _applyContentRanges normalizes lazy scanOnly expand to current-dev eager list comprehension to isolate representation. The state, emitter, range tracking and note detection are common benchmark substitutes. ContentLineChanges only loses Flutter import and @immutable annotation.',
    'scope': 'Current production list work. Excludes Flutter rendering, Bloc scheduling, I/O, HTML/footnotes and worker transfer. Consumer functions see identical plain ASCII fixtures; sanitizer rejects unsupported input.',
    'functions': PROVENANCE,
}, ensure_ascii=False, indent=2))
print(json.dumps({'files': [str(p) for p in ROOT.iterdir()], 'functions': len(PROVENANCE)}))
