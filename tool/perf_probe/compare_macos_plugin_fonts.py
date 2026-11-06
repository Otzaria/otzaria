#!/usr/bin/env python3
"""Validate one fresh-process data/scheme pair; never enable the experiment."""
import argparse
import json
import math
import pathlib
import statistics

SAMPLE_KEYS = {
    'system-regular', 'system-bold', 'bundled-regular', 'bundled-bold',
    'variable-light', 'variable-bold',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_pair(data, scheme):
    reports = {'data': data, 'scheme': scheme}
    require(data['pid'] != scheme['pid'], 'data and scheme must use fresh app processes')
    require(data['instances'] == scheme['instances'], 'instance count differs')
    require(data['systemFont']['family'] == scheme['systemFont']['family'], 'system font differs')
    count = data['instances']
    require(count in (1, 5, 10), 'unexpected instance count')
    summary = {'instances': count, 'decision': 'keep-default-off', 'modes': {}}
    cases = {}
    for mode, report in reports.items():
        require(report['schemaVersion'] == 1, 'unknown schema')
        require(report.get('status') == 'passed', 'probe run did not complete')
        require(report.get('framePolicy') == 'fullyLive', 'native frames were not enabled')
        require(report['platform'] == 'macos', 'requires actual macOS')
        require(report['requestedTransport'] == mode, 'requested transport differs')
        require(report['hostKind'] == 'visible-flutter-platform-view', 'headless is not visible-host evidence')
        require(report['window']['ready'] is True, 'host window was not verified')
        require(report['decision'] == 'keep-default-off', 'probe cannot enable production')
        require(report['ios'] == 'disabled-unvalidated', 'iOS must stay separate')
        for metric in ('engineMemory', 'engineCpu'):
            require(report[metric]['availability'] == 'unsupported', f'{metric} needs explicit missing coverage')
            require('value' not in report[metric], f'{metric} must not invent a numeric result')
        cases[mode] = {case['scenario']: case for case in report['cases']}
        require(set(cases[mode]) == {'normal', 'font-src-data', 'style-src-none'}, 'CSP cases missing')
        for name, case in cases[mode].items():
            require(case.get('status') == 'passed', 'CSP case did not complete')
            require(len(case['views']) == count, 'view count differs')
            require({v['index'] for v in case['views']} == set(range(count)), 'duplicate/missing view')
            for view in case['views']:
                require(view.get('status') == 'completed', 'view observation did not complete')
                operations = view.get('operations', [])
                names = [operation.get('name') for operation in operations]
                required = {'font-preparation', 'boot', 'rendering'}
                if name != 'style-src-none':
                    required.add('screenshot')
                require(required <= set(names) and len(names) == len(set(names)),
                        'native operation evidence missing or duplicated')
                require(all(operation.get('status') == 'completed'
                            and not operation.get('lateResponse')
                            and not operation.get('lateError') for operation in operations),
                        'native operation is incomplete or late')
                prep, rendering = view['preparation'], view['rendering']
                require(view.get('bootAcknowledged') is True, 'missing guarded boot acknowledgement')
                require(rendering['bootCount'] == 1, 'plugin boot did not complete exactly once')
                require(rendering['visible'] is True, 'document was hidden')
                require(view['bootJavascriptUtf8Bytes'] > 0, 'missing actual boot payload')
                require(prep['javascriptUtf8Bytes'] > 0 and prep['argumentJsonUtf8Bytes'] > 0, 'missing submitted font payload')
                require(view['schemeResponseBytes'] >= view['schemeBytesAtBoot'] >= 0, 'invalid scheme response counter')
                if name == 'style-src-none':
                    require(prep['ready'] is False and prep['transport'] == 'unavailable', 'blocked style falsely succeeded')
                    require(prep['outcome']['reason'] == 'style-blocked', 'blocked style reason lost')
                    require(view['fontReadyFromViewCreationMicroseconds'] is None, 'blocked style has no ready timestamp')
                    continue
                require(prep['ready'] is True, 'font did not become ready')
                require(view['fontReadyFromViewCreationMicroseconds'] > 0, 'missing font ready timing')
                at_boot = rendering.get('readyFacesAtBoot', [])
                boot_families = {face['family'].strip("\"'") for face in at_boot}
                require({report['systemFont']['family'], 'FrankRuhlCLM', 'Rubik'} <= boot_families,
                        'selected fonts were not ready at plugin.ready')
                require(view.get('screenshot') or view.get('screenshotBase64'), 'missing WKWebView rendering image')
                if mode == 'data' or name == 'font-src-data':
                    require(prep['transport'] == 'data', 'data control/fallback was not used')
                if mode == 'scheme' and name == 'font-src-data':
                    require(prep.get('schemeFailure'), 'CSP fallback lacks a rejected scheme attempt')
                if prep['transport'] == 'scheme':
                    require(view['schemeBytesAtBoot'] > 0 and view['schemeResponses'] > 0, 'scheme success lacks served font bytes')
                samples = {sample['key']: sample for sample in rendering['samples']}
                require(set(samples) == SAMPLE_KEYS, 'typography sample missing')
                for sample in samples.values():
                    require(math.isfinite(sample['width']) and sample['width'] > 0, 'invalid text width')
                    require(sample['inkPixels'] > 0, 'blank rendering')
                    require(sample['loadedFaces'] and all(face['status'] == 'loaded' for face in sample['loadedFaces']), 'no actual loaded FontFace')
                require(any(f['weight'] == '700' for f in samples['bundled-bold']['loadedFaces']), 'separate bold face not loaded')
                require(any(f['weight'] == '100 900' for f in samples['variable-bold']['loadedFaces']), 'variable face range missing')
                require(samples['bundled-regular']['pixelHash'] != samples['bundled-bold']['pixelHash'], 'separate bold did not change rendering')
                require(samples['variable-light']['pixelHash'] != samples['variable-bold']['pixelHash'], 'variable axis did not change rendering')
            if name == 'normal' and count > 1:
                require(case.get('survivorAfterClosingFirst') and all(s == 'loaded' for s in case['survivorAfterClosingFirst']), 'closing one host broke another')
                fresh = case.get('freshSchemeAfterClosingFirst', {})
                survivor = next(v for v in case['views'] if v['index'] == count - 1)
                if mode == 'scheme' and survivor['preparation']['transport'] == 'scheme':
                    require(fresh.get('availability') == 'verified', 'missing fresh survivor scheme request')
                    require(fresh.get('faceStatus') == 'loaded', 'survivor FontFace did not load')
                    for key in ('loaderReads', 'requestDelta', 'responseDelta', 'responseBytesDelta'):
                        require(fresh.get(key, 0) > 0, f'fresh survivor lacks {key}')
                else:
                    require(fresh.get('availability') == 'not-run', 'unmeasured survivor request must stay explicit')
                    reason = 'data-control' if mode == 'data' else 'normal-scheme-unavailable'
                    require(fresh.get('reason') == reason, 'survivor request limitation missing')
        normal = cases[mode]['normal']['views']
        summary['modes'][mode] = {
            'effectiveTransports': [v['preparation']['transport'] for v in normal],
            'bootJavascriptUtf8Bytes': sum(v['bootJavascriptUtf8Bytes'] for v in normal),
            'fontJavascriptUtf8Bytes': sum(v['preparation']['javascriptUtf8Bytes'] for v in normal),
            'fontArgumentJsonUtf8Bytes': sum(v['preparation']['argumentJsonUtf8Bytes'] for v in normal),
            'schemeBytesAtBoot': sum(v['schemeBytesAtBoot'] for v in normal),
            'schemeResponseBytesIncludingRenderingChecks': sum(v['schemeResponseBytes'] for v in normal),
            'medianFontReadyFromViewCreationMicroseconds': statistics.median(v['fontReadyFromViewCreationMicroseconds'] for v in normal),
            'freshSchemeAfterClosingFirst': cases[mode]['normal'].get(
                'freshSchemeAfterClosingFirst',
                {'availability': 'not-run', 'reason': 'single-instance'}),
        }
    for name in ('normal', 'font-src-data'):
        left = sorted(cases['data'][name]['views'], key=lambda v: v['index'])
        right = sorted(cases['scheme'][name]['views'], key=lambda v: v['index'])
        for a, b in zip(left, right):
            a_samples = {s['key']: s for s in a['rendering']['samples']}
            b_samples = {s['key']: s for s in b['rendering']['samples']}
            for key in SAMPLE_KEYS:
                aa, bb = a_samples[key], b_samples[key]
                require(abs(aa['width'] - bb['width']) <= 0.001, f'text width differs for {name}/{key}')
                require(aa['pixelHash'] == bb['pixelHash'], f'canvas rendering differs for {name}/{key}')
    summary['normalSchemeVerified'] = all(v['preparation']['transport'] == 'scheme' for v in cases['scheme']['normal']['views'])
    summary['limits'] = [
        'One pair per count is not a performance distribution.',
        'Data control shares the experimental pre-boot verifier; default Apple boot remains unchanged.',
        'UTF-8 logical payload sizes exclude native protocol envelopes and memory copies.',
        'No WKWebView process CPU/memory, GPU/display, iOS or cross-WebView cache claim.',
    ]
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('reports', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    reports = {}
    for path in args.reports.rglob('report.json'):
        report = json.loads(path.read_text()).get('fontProbe')
        require(isinstance(report, dict), f'missing fontProbe: {path}')
        key = report['requestedTransport']
        require(key not in reports, f'duplicate report mode: {key}')
        reports[key] = report
    require(set(reports) == {'data', 'scheme'}, 'complete data/scheme pair required')
    summary = validate_pair(reports['data'], reports['scheme'])
    args.output.write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
