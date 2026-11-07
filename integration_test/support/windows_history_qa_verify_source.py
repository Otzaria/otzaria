import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def git(*args):
    return subprocess.check_output(['git', *args])


def verify(product):
    if not re.fullmatch(r'[0-9a-f]{40}', product):
        raise ValueError('A complete reviewed product commit is required.')
    head = git('rev-parse', 'HEAD').decode().strip()
    allowed = {
        '.github/workflows/report-winv-windows11-qa.yml',
        'integration_test/report_clipboard_history_windows_qa_test.dart',
        'integration_test/support/windows_history_qa_clipboard.ps1',
        'integration_test/support/windows_history_qa_controller.ps1',
        'integration_test/support/windows_history_qa_native.cs',
        'integration_test/support/windows_history_qa_run_bundle.ps1',
        'integration_test/support/windows_history_qa_server_prerequisite.ps1',
        'integration_test/support/windows_history_qa_server_prerequisite_test.ps1',
        'integration_test/support/windows_history_qa_verify_source.py',
        'integration_test/support/windows_history_qa_windows11.ps1',
        'windows/runner/flutter_window.cpp',
        'windows/runner/main.cpp',
        'windows/runner/report_history_qa_trace.h',
    }
    changed = {
        value.decode()
        for value in git('diff', '--name-only', '-z', product, head).split(b'\0')
        if value
    }
    if changed - allowed:
        raise ValueError(f'Unexpected product changes in the QA overlay: {sorted(changed - allowed)}')
    removals = {
        'windows/runner/flutter_window.cpp': [
            b'#include "report_history_qa_trace.h"\n',
            b'  InstallReportHistoryQaTrace(view);\n',
            b'  InstallReportHistoryQaTrace(flutter_controller_->view()->GetNativeWindow());\n',
        ],
        'windows/runner/main.cpp': [
            b'#include "report_history_qa_trace.h"\n',
            b'    ObserveReportHistoryQaRawQueue(msg);\n',
        ],
    }
    native = []
    for path, lines in removals.items():
        original = git('show', f'{product}:{path}')
        observed = git('show', f'{head}:{path}')
        stripped = observed
        for line in lines:
            if original.count(line) or stripped.count(line) != 1:
                raise ValueError(f'Unexpected native observation hook in {path}')
            stripped = stripped.replace(line, b'')
        if stripped != original:
            raise ValueError(f'The native runner differs beyond its reviewed observation hook: {path}')
        native.append({
            'path': path,
            'productSha256': hashlib.sha256(original).hexdigest(),
            'qaSha256': hashlib.sha256(observed).hexdigest(),
            'productRestoredAfterRemovingObservation': True,
        })
    subprocess.run(['git', 'diff', '--exit-code', '--quiet', 'HEAD'], check=True)
    crate = Path('packages/super_native_extensions/rust')
    files = sorted(path for path in (crate / 'src').rglob('*') if path.is_file() and not path.is_symlink())
    files += [crate / name for name in ('Cargo.toml', 'Cargo.lock', 'build.rs', 'cargokit.yaml') if (crate / name).is_file()]
    digest = hashlib.sha256()
    for path in files:
        # Match Cargokit's line-ending-independent hashing of every source file.
        digest.update(''.join(re.split(r'\r\n|\r|\n', path.read_text(encoding='utf-8'))).encode())
    crate_hash = digest.hexdigest()[:32]
    if crate_hash != os.environ['REPORT_QA_CRATE_HASH']:
        raise ValueError(f'The patched crate hash differs from the reviewed source: {crate_hash}')
    config = json.loads(Path('.dart_tool/package_config.json').read_text())
    package = [entry for entry in config['packages'] if entry['name'] == 'super_native_extensions']
    if len(package) != 1:
        raise ValueError('The clipboard package is not uniquely resolved.')
    from urllib.parse import urljoin, unquote, urlparse
    from urllib.request import url2pathname
    resolved = Path(url2pathname(unquote(urlparse(urljoin(Path('.dart_tool/package_config.json').absolute().as_uri(), package[0]['rootUri'])).path))).resolve()
    if resolved != crate.parent.resolve():
        raise ValueError(f'The native clipboard package is not the reviewed vendor: {resolved}')
    return {
        'sourceHead': product, 'qaHead': head,
        'changedPaths': sorted(changed), 'nativeObservation': native,
        'crateHash': crate_hash, 'crateFileCount': len(files),
        'resolvedClipboardPackage': str(resolved), 'productPreserved': True,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--product', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.product)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result))
