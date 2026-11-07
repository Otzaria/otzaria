"""Synthetic validator controls, never native iOS compatibility evidence."""
import base64
import copy
import json
import hashlib
import os
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

from validate_ios_plugin_fonts import (ENGINE_REVISION, FLUTTER_REVISION, LAB_FILTER, NATIVE_PACKAGES,
    ORIGIN, PRODUCTION_BLOCKERS, PRODUCTION_CSP, ROUTES, SCENARIOS, SPECS, THEME,
    blocker, read_json, validate, validate_artifacts, validate_environment)

ENGINE_PIN = '2da23091237ed0f0a612de3b2d18cfc99d8b7d2a'
WEBVIEW_PIN = 'c709de98711cf34350c48df4c75e24d0879d5876'
LOCK_TEXT = 'packages:\n' + ''.join(
    f'  {name}:\n    description:\n      resolved-ref: "{pin}"\n    source: git\n'
    for name, pin in [(name, ENGINE_PIN if name == 'otzaria_search_engine' else WEBVIEW_PIN) for name in NATIVE_PACKAGES])
LOCK_SHA = hashlib.sha256(LOCK_TEXT.encode()).hexdigest()
LOCK_BLOB = hashlib.sha1(b'blob ' + str(len(LOCK_TEXT.encode())).encode() + b'\0' + LOCK_TEXT.encode()).hexdigest()
PODS_TEXT = 'SYNTHETIC CocoaPods fixture\n'
PODS_SHA = hashlib.sha256(PODS_TEXT.encode()).hexdigest()


def fixture(count=1, *, javascript_floats=False):
    js_integer = float if javascript_floats else int
    cases = []
    for route in ROUTES:
        for requested in ('data', 'scheme'):
            for scenario in SCENARIOS:
                identifier = f'{route}-{requested}-{scenario}'
                lab, file = route != ROUTES[0], route != ROUTES[2]
                registered = requested == 'scheme' or not file
                blocked = scenario == 'style-src-none'
                transport = 'unavailable' if blocked else requested if scenario == 'normal' else 'data'
                policy = {'route': route, 'documentScheme': 'file' if file else 'otzaria-plugin',
                    'contentBlockers': 'lab-exact-origin-added' if lab else 'production',
                    'labAllowFilter': LAB_FILTER if lab else None,
                    'contentBlockerRules': copy.deepcopy(PRODUCTION_BLOCKERS + ([blocker(LAB_FILTER, True)] if lab else [])),
                    'resourceCustomSchemes': ['otzaria-plugin'] if registered else [],
                    'schemeRegistration': 'experiment-added' if registered else 'production',
                    'handler': 'production-servePluginAsset' if registered else 'not-registered',
                    'allowFileAccessFromFileURLs': False, 'allowUniversalAccessFromFileURLs': False,
                    'allowingReadAccessTo': None, 'incognito': True, 'responseAddsAccessControlAllowOrigin': False,
                    'csp': PRODUCTION_CSP + {'normal': '', 'font-src-data': '; font-src data:', 'style-src-none': "; style-src 'none'"}[scenario]}
                url = ('file:///SYNTHETIC-FIXTURE' if file else ORIGIN) + '/' + identifier + '.html'
                case = {'id': identifier, 'scenario': scenario, 'requestedTransport': requested,
                        'policy': policy, 'status': 'completed', 'cleanupStatus': 'completed', 'views': []}
                for index in range(count):
                    owner, document = f'owner-{identifier}-{index}', f'doc-{identifier}-{index}'
                    faces = [{'family': f, 'status': 'loaded'} for f in ('FrankRuhlCLM', 'Rubik')]
                    prep = {'ready': not blocked, 'transport': transport, 'javascriptUtf8Bytes': 100,
                            'argumentJsonUtf8Bytes': 100, 'outcome': {'reason': 'style-blocked' if blocked else 'loaded', 'faces': faces}}
                    if requested == 'scheme' and transport == 'data':
                        prep['schemeFailure'] = 'font-load-failed'
                    phases = [('started', None)]
                    for key in SPECS:
                        phases.extend((phase, key) for phase in ('font-load-started', 'font-load-completed', 'canvas-started', 'canvas-completed'))
                    phases.extend((phase, None) for phase in ('frames-requested', 'frame-1', 'frame-2', 'fallback-started', 'fallback-completed', 'completed'))
                    operations = ['font-preparation', 'boot', 'rendering', 'policy-diagnostics']
                    if not blocked:
                        operations.append('screenshot')
                    if index == count - 1:
                        operations.append('navigation-ownership')
                        if count > 1 and scenario == 'normal':
                            operations.append('fresh-survivor-font-load')
                    rendering = {'bootCount': js_integer(1), 'bootTheme': copy.deepcopy(THEME), 'visible': True,
                        'readyFacesAtBoot': faces, 'viewport': {'width': js_integer(100), 'height': js_integer(100), 'dpr': js_integer(2)}, 'userAgent': 'SYNTHETIC WebKit fixture',
                        'fallbackControl': {'pixelHash': 'ffff', 'width': 120.5, 'inkPixels': js_integer(40)}, 'samples': [] if blocked else [
                            {'key': key, 'family': family, 'weight': weight, 'width': 120.5, 'inkPixels': js_integer(45), 'pixelHash': format(i + 1, 'x'),
                             'loadedFaces': [{'family': family, 'weight': '100 900' if family == 'Rubik' else weight, 'status': 'loaded'}]}
                            for i, (key, (family, weight)) in enumerate(SPECS.items())],
                        'renderingProgress': {'documentId': document, 'owner': owner, 'phase': 'completed', 'droppedEvents': js_integer(0),
                            'startedAtEpochMilliseconds': js_integer(1001), 'elapsedMilliseconds': js_integer(len(phases) - 1),
                            'events': [{'phase': phase, 'fontKey': key, 'elapsedMilliseconds': js_integer(i),
                                        'visibilityState': 'visible'} for i, (phase, key) in enumerate(phases)]}}
                    if javascript_floats:
                        rendering['bootTheme']['typography']['fontSize'] = 28.0
                    decisions = [{'event': 'navigation-decision', 'url': url, 'policy': 'allow', 'isForMainFrame': True}]
                    if index == count - 1:
                        decisions.append(dict(decisions[0], url=url[:-5] + '-navigation.html'))
                    case['views'].append({'index': index, 'status': 'completed', 'disposed': True, 'events': decisions,
                        'operations': [{'name': name, 'status': 'completed', 'timeoutMilliseconds': 10000,
                                        'startedMicroseconds': i * 1000, 'responseMicroseconds': i * 1000 + 20}
                                       for i, name in enumerate(operations)],
                        'documentIdentity': {'owner': owner, 'leaseId': owner, 'documentId': document},
                        'policyDiagnostics': {'owner': owner, 'documentId': document, 'href': url,
                                              'origin': 'null' if file else ORIGIN, 'violations': [], 'droppedViolations': js_integer(0)},
                        'bootAcknowledged': True, 'bootJavascriptUtf8Bytes': 10, 'preparation': prep,
                        'fontReadyFromViewCreationMicroseconds': None if blocked else 200,
                        'schemeRequests': 1 if transport == 'scheme' else 0,
                        'schemeResponses': 1 if transport == 'scheme' else 0,
                        'schemeResponseBytes': 100 if transport == 'scheme' else 0,
                        'schemeBytesAtBoot': 100 if transport == 'scheme' else 0,
                        'renderingRequestedAtEpochMilliseconds': 1000, 'rendering': rendering,
                        'screenshot': None if blocked else f'{identifier}-{index}.png'})
                last, first = case['views'][-1], case['views'][0]
                identity = last['documentIdentity']
                case['navigation'] = {'oldOwner': identity['owner'], 'oldDocumentId': identity['documentId'],
                    'newDocument': {'documentId': 'replacement-' + identity['documentId'], 'bootCount': js_integer(0), 'staleEffect': False},
                    'requestedUrl': url[:-5] + '-navigation.html', 'observedUrl': url[:-5] + '-navigation.html',
                    'oldLeaseInactive': True, 'rejectedBoot': {'booted': False, 'reason': 'stale-document'}}
                if count > 1 and scenario == 'normal':
                    case['peerClose'] = {'closedLeaseInactive': True, 'survivorLeaseActive': True,
                                        'closedOwner': first['documentIdentity']['owner'], 'survivorOwner': identity['owner']}
                    case['freshOwnedFontAfterClosingFirst'] = {'availability': 'verified', 'faceStatus': 'loaded',
                        'transport': transport, 'owner': identity['owner'], 'documentId': identity['documentId'],
                        **({'loaderReads': 1, 'requestDelta': 1, 'responseDelta': 1, 'responseBytesDelta': 100}
                           if transport == 'scheme' else {'sourceBytes': 100})}
                cases.append(case)
    report = {'schemaVersion': 1, 'status': 'completed', 'platform': 'ios', 'osVersion': 'SYNTHETIC-TEST',
        'dartVersion': 'SYNTHETIC-TEST', 'buildMode': 'debug', 'deviceKind': 'simulator',
        'physicalProfile': 'notRun', 'physicalRelease': 'notRun', 'sourceCommit': '1' * 40, 'lockSha256': LOCK_SHA,
        'framePolicy': 'fullyLive', 'frameDriver': 'fullyLive-value-notifier', 'hostKind': 'visible-flutter-platform-view',
        'decision': 'keep-default-off', 'productionIosExperimentEnabled': False,
        'engineMemory': {'availability': 'unsupported'}, 'engineCpu': {'availability': 'unsupported'},
        'crossViewCacheSharing': {'availability': 'not-measured'}, 'instances': count, 'theme': copy.deepcopy(THEME), 'cases': cases}
    return {'schemaVersion': 1, 'framework': {'allTestsPassed': True, 'failures': []}, 'data': {'iosFontProbe': report}}


def environment_fixture():
    return {'schemaVersion': 1, 'captureStatus': 'complete', 'runStatus': 'completed', 'instances': 1,
        'drive': {'returncode': 0, 'timedOut': False, 'groupDrained': True},
        'sourceCommit': '1' * 40, 'sourceCommitAfter': '1' * 40, 'sourceTree': '3' * 40, 'sourceTreeAfter': '3' * 40, 'sourceStatus': '', 'sourceStatusAfter': '',
        'lockSha256': LOCK_SHA, 'lockSha256After': LOCK_SHA, 'committedLockSha256': LOCK_SHA,
        'lockSourceCommit': '1' * 40, 'lockSourceBlob': LOCK_BLOB,
        'flutter': {'frameworkVersion': '3.47.7', 'frameworkRevision': FLUTTER_REVISION,
                    'engineRevision': ENGINE_REVISION, 'dartSdkVersion': '3.13.5'},
        'flutterSourceCommit': FLUTTER_REVISION, 'flutterSourceCommitAfter': FLUTTER_REVISION, 'flutterSourceStatus': '', 'flutterSourceStatusAfter': '',
        'enginePin': ENGINE_PIN, 'webviewPin': WEBVIEW_PIN, 'nativeSources': {
            name: {'head': pin, 'headAfter': pin, 'lockPin': pin, 'status': '', 'statusAfter': ''}
            for name, pin in [(name, ENGINE_PIN if name == 'otzaria_search_engine' else WEBVIEW_PIN) for name in NATIVE_PACKAGES]},
        'mode': 'debug', 'runtime': {'deviceKind': 'simulator', 'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-26-7',
            'device': {'udid': 'SYNTHETIC', 'isAvailable': True, 'name': 'iPhone synthetic'},
            'version': '26.7', 'buildversion': 'SYNTHETIC', 'booted': True},
        'xcode': 'SYNTHETIC', 'sdkVersion': '26.7', 'sdkBuild': 'SYNTHETIC', 'hostOS': 'SYNTHETIC',
        'hostArchitecture': 'arm64', 'rustc': 'SYNTHETIC', 'cargo': 'SYNTHETIC', 'rustToolchain': 'SYNTHETIC',
        'rustTargets': 'aarch64-apple-ios-sim\nx86_64-apple-ios', 'podfileLockSha256': PODS_SHA}


def png_bytes(width=1):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, 1, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(b'\x00' + b'\x00\x00\x00\xff' * width)) + chunk(b'IEND', b''))


def artifacts(root):
    (root / 'pubspec.lock').write_text(LOCK_TEXT)
    (root / 'Podfile.lock').write_text(PODS_TEXT)
    envelope = fixture()
    raw_data = copy.deepcopy(envelope['data'])
    for case in raw_data['iosFontProbe']['cases']:
        for view in case['views']:
            if view['screenshot']:
                (root / view.pop('screenshot')).write_bytes(png_bytes())
                view['screenshotBase64'] = base64.b64encode(png_bytes()).decode()
    # The writer leaves a null screenshotBase64 on blocked views.
    for report in (envelope['data'], raw_data):
        for case in report['iosFontProbe']['cases']:
            if case['scenario'] == 'style-src-none':
                for view in case['views']:
                    view.pop('screenshot')
                    view['screenshotBase64'] = None
    (root / 'report.json').write_text(json.dumps(envelope))
    (root / 'framework-response.json').write_text(json.dumps({'result': 'true', 'failureDetails': [], 'data': raw_data}))
    return root / 'report.json'


class ValidatorTests(unittest.TestCase):
    def test_complete_1_5_10_synthetic_controls_do_not_enable_production(self):
        for count in (1, 5, 10):
            result = validate(fixture(count))
            self.assertTrue(result['productionPolicySchemeCompatible'])
            self.assertEqual(result['decision'], 'keep-default-off')


    def test_integral_javascript_floats_pass_without_converting_dart_fields(self):
        for count in (1, 5, 10):
            with self.subTest(count=count):
                integer = validate(fixture(count))
                bridged = fixture(count, javascript_floats=True)
                before = copy.deepcopy(bridged)
                self.assertEqual(validate(bridged), integer)
                self.assertEqual(bridged, before)
                self.assertIs(type(bridged['data']['iosFontProbe']['instances']), int)

    def test_javascript_integer_fields_reject_nonintegral_or_untyped_values(self):
        fields = [
            lambda c, v, value: v['rendering'].update(bootCount=value),
            lambda c, v, value: c['navigation']['newDocument'].update(bootCount=value),
            lambda c, v, value: v['rendering']['samples'][0].update(inkPixels=value),
            lambda c, v, value: v['rendering']['fallbackControl'].update(inkPixels=value),
            lambda c, v, value: v['rendering']['renderingProgress'].update(startedAtEpochMilliseconds=value),
            lambda c, v, value: v['rendering']['renderingProgress'].update(droppedEvents=value),
            lambda c, v, value: v['policyDiagnostics'].update(droppedViolations=value),
        ]
        for index, field in enumerate(fields):
            for value in (True, False, '1', None, 1.5, float('nan'), float('inf'),
                          -float('inf'), -1, 2 ** 53, float(2 ** 53), 10 ** 1000):
                with self.subTest(field=index, value=repr(value)):
                    self.reject(lambda e, r, c, v: field(c, v, value))

    def test_javascript_integer_field_specific_bounds_remain_required(self):
        for value in (0, 2, 2.0):
            self.reject(lambda e, r, c, v: v['rendering'].update(bootCount=value))
        for value in (1, 1.0):
            self.reject(lambda e, r, c, v: c['navigation']['newDocument'].update(bootCount=value))
            self.reject(lambda e, r, c, v: v['rendering']['renderingProgress'].update(droppedEvents=value))
        for value in (0, 650 * 80 + 1, float(650 * 80 + 1)):
            self.reject(lambda e, r, c, v: v['rendering']['samples'][0].update(inkPixels=value))
            self.reject(lambda e, r, c, v: v['rendering']['fallbackControl'].update(inkPixels=value))
        self.reject(lambda e, r, c, v: v['rendering']['renderingProgress'].update(startedAtEpochMilliseconds=0))
        self.reject(lambda e, r, c, v: v['rendering']['renderingProgress'].update(startedAtEpochMilliseconds=999.0))

    def test_dart_integer_provenance_is_not_widened_for_the_javascript_bridge(self):
        mutations = [
            lambda e, r, c, v: e.update(schemaVersion=1.0),
            lambda e, r, c, v: r.update(schemaVersion=1.0),
            lambda e, r, c, v: r.update(instances=1.0),
            lambda e, r, c, v: v.update(index=0.0),
            lambda e, r, c, v: v.update(bootJavascriptUtf8Bytes=10.0),
            lambda e, r, c, v: v['preparation'].update(javascriptUtf8Bytes=100.0),
            lambda e, r, c, v: v['preparation'].update(argumentJsonUtf8Bytes=100.0),
            lambda e, r, c, v: v.update(fontReadyFromViewCreationMicroseconds=200.0),
            lambda e, r, c, v: v.update(renderingRequestedAtEpochMilliseconds=1000.0),
            lambda e, r, c, v: v['operations'][0].update(startedMicroseconds=0.0),
            lambda e, r, c, v: v['operations'][0].update(responseMicroseconds=20.0),
            lambda e, r, c, v: r['cases'][3]['views'][0].update(schemeResponseBytes=100.0),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(field=index):
                self.reject(mutate)

    def test_real_javascript_measurements_are_finite_and_complete(self):
        fields = [
            lambda v, value: v['rendering']['samples'][0].update(width=value),
            lambda v, value: v['rendering']['fallbackControl'].update(width=value),
            lambda v, value: v['rendering']['viewport'].update(dpr=value),
            lambda v, value: v['rendering']['renderingProgress'].update(elapsedMilliseconds=value),
            lambda v, value: v['rendering']['renderingProgress']['events'][0].update(elapsedMilliseconds=value),
        ]
        for index, field in enumerate(fields):
            for value in (True, '1', None, float('nan'), float('inf'), -float('inf'), -1):
                with self.subTest(field=index, value=repr(value)):
                    self.reject(lambda e, r, c, v: field(v, value))
        self.reject(lambda e, r, c, v: v['rendering']['renderingProgress'].update(elapsedMilliseconds=24))
        self.reject(lambda e, r, c, v: v['rendering']['fallbackControl'].update(pixelHash='invalid'))
        self.reject(lambda e, r, c, v: v['rendering']['viewport'].pop('dpr'))

    def reject(self, mutate, pattern=None, count=1):
        envelope = fixture(count)
        report = envelope['data']['iosFontProbe']
        mutate(envelope, report, report['cases'][0], report['cases'][0]['views'][0])
        with self.assertRaises((ValueError, KeyError, TypeError)) as failure:
            validate(envelope)
        if pattern:
            self.assertRegex(str(failure.exception), pattern)

    def test_framework_case_cleanup_and_count_mutants(self):
        mutations = [
            lambda e, r, c, v: e['framework'].update(allTestsPassed=False),
            lambda e, r, c, v: e['framework'].update(failures=['failure']),
            lambda e, r, c, v: r.update(status='running'),
            lambda e, r, c, v: r.update(instances=True),
            lambda e, r, c, v: v.update(index=False),
            lambda e, r, c, v: v['rendering'].update(bootCount=True),
            lambda e, r, c, v: v.update(bootJavascriptUtf8Bytes=True),
            lambda e, r, c, v: r['cases'].pop(),
            lambda e, r, c, v: r['cases'].append(copy.deepcopy(c)),
            lambda e, r, c, v: c.update(status='failed'),
            lambda e, r, c, v: c.update(cleanupStatus='failed'),
            lambda e, r, c, v: c.update(cleanupError='timeout'),
            lambda e, r, c, v: v.update(disposed=False),
            lambda e, r, c, v: v.update(failure={'error': 'late'}),
            lambda e, r, c, v: v.update(failureSnapshot={'status': 'captured', 'phase': 'completed'}),
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutations.index(mutate)):
                self.reject(mutate)

    def test_native_operation_and_navigation_mutants(self):
        for status in ('pending', 'timed-out', 'disposed', 'failed'):
            self.reject(lambda e, r, c, v: v['operations'][0].update(status=status))
        for flag in ('lateResponse', 'lateError'):
            self.reject(lambda e, r, c, v: v['operations'][0].update({flag: True}))
        self.reject(lambda e, r, c, v: v['operations'].pop())
        self.reject(lambda e, r, c, v: v['operations'][0].update(timeoutMilliseconds=30000))
        self.reject(lambda e, r, c, v: v['operations'][0].update(responseMicroseconds=10000001))
        self.reject(lambda e, r, c, v: v.update(events=[]))
        self.reject(lambda e, r, c, v: v['events'][0].update(policy='cancel'))
        self.reject(lambda e, r, c, v: v['events'][0].update(isForMainFrame=False))
        self.reject(lambda e, r, c, v: v['events'][0].update(url='file:///other.html'))
        for field, value in [('oldLeaseInactive', False), ('oldOwner', 'other'), ('rejectedBoot', {'booted': True})]:
            self.reject(lambda e, r, c, v: c['navigation'].update({field: value}))
        for field, value in [('bootCount', 1), ('staleEffect', True), ('documentId', 'doc-file-production-policy-data-normal-0')]:
            self.reject(lambda e, r, c, v: c['navigation']['newDocument'].update({field: value}))

    def test_production_and_lab_policy_mutants(self):
        for field, value in [('allowFileAccessFromFileURLs', True), ('allowUniversalAccessFromFileURLs', True),
                             ('allowingReadAccessTo', 'file:///'), ('responseAddsAccessControlAllowOrigin', True),
                             ('incognito', False), ('documentScheme', 'otzaria-plugin'), ('resourceCustomSchemes', ['http'])]:
            self.reject(lambda e, r, c, v: c['policy'].update({field: value}))
        # Changing every baseline together used to evade a relative-only policy check.
        self.reject(lambda e, r, c, v: [item['policy']['contentBlockerRules'][0]['action'].update(type='ignore-previous-rules') for item in r['cases']])
        self.reject(lambda e, r, c, v: [item['policy'].update(csp=item['policy']['csp'].replace("'self'", '*')) for item in r['cases']])
        self.reject(lambda e, r, c, v: r['cases'][6]['policy']['contentBlockerRules'][-1]['trigger'].update({'url-filter': '^otzaria-plugin:'}))

    def test_boot_faces_pixels_and_complete_native_frames_are_required(self):
        mutations = [
            lambda e, r, c, v: v.update(bootAcknowledged=False),
            lambda e, r, c, v: v['rendering'].update(bootCount=2),
            lambda e, r, c, v: v['rendering'].update(visible=False),
            lambda e, r, c, v: v['rendering'].update(bootTheme={}),
            lambda e, r, c, v: v['rendering'].update(readyFacesAtBoot=[]),
            lambda e, r, c, v: v['preparation']['outcome'].update(faces=[]),
            lambda e, r, c, v: v['rendering']['samples'][0].update(loadedFaces=[]),
            lambda e, r, c, v: v['rendering']['samples'][0].update(width=float('nan')),
            lambda e, r, c, v: v['rendering']['samples'][0].update(inkPixels=0),
            lambda e, r, c, v: v['rendering']['samples'][1].update(pixelHash='1'),
            lambda e, r, c, v: v['rendering']['samples'][3]['loadedFaces'][0].update(weight='700'),
            lambda e, r, c, v: v['rendering']['renderingProgress']['events'].pop(-4),
            lambda e, r, c, v: v['rendering']['renderingProgress'].update(owner='wrong'),
            lambda e, r, c, v: v['rendering']['renderingProgress']['events'][0].update(visibilityState='hidden'),
            lambda e, r, c, v: v['policyDiagnostics'].update(owner='wrong'),
            lambda e, r, c, v: v.pop('screenshot'),
            lambda e, r, c, v: r.update(productionIosExperimentEnabled=True),
            lambda e, r, c, v: r.update(engineCpu={'availability': 'measured', 'value': 0}),
            lambda e, r, c, v: r.update(crossViewCacheSharing={'availability': 'shared'}),
            lambda e, r, c, v: r.update(buildMode='profile', physicalProfile='this-run'),
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutations.index(mutate)):
                self.reject(mutate)

    def test_csp_denial_and_transport_pair_mutants(self):
        self.reject(lambda e, r, c, v: r['cases'][2]['views'][0]['preparation'].update(ready=True))
        self.reject(lambda e, r, c, v: r['cases'][3]['views'][0].update(schemeBytesAtBoot=0))
        self.reject(lambda e, r, c, v: r['cases'][4]['views'][0]['preparation'].update(schemeFailure='font-timeout'))
        self.reject(lambda e, r, c, v: r['cases'][3]['views'][0]['rendering']['samples'][0].update(pixelHash='a'))

    def test_fresh_scheme_and_data_survivors_require_same_document(self):
        for key in ('loaderReads', 'requestDelta', 'responseDelta', 'responseBytesDelta'):
            self.reject(lambda e, r, c, v: r['cases'][3]['freshOwnedFontAfterClosingFirst'].update({key: 0}), count=5)
        self.reject(lambda e, r, c, v: c['freshOwnedFontAfterClosingFirst'].update(sourceBytes=0), count=5)
        self.reject(lambda e, r, c, v: c['freshOwnedFontAfterClosingFirst'].update(owner='foreign'), count=5)
        self.reject(lambda e, r, c, v: c['peerClose'].update(survivorLeaseActive=False), count=5)
        self.reject(lambda e, r, c, v: c.pop('freshOwnedFontAfterClosingFirst'), count=5)

    def test_verified_fallback_and_mixed_results_are_distinct_from_incomplete(self):
        envelope = fixture(5)
        case = envelope['data']['iosFontProbe']['cases'][3]
        for view in case['views'][:1]:
            view['preparation'].update(transport='data', schemeFailure='font-load-failed')
        result = validate(envelope)
        self.assertEqual(result['routes'][ROUTES[0]]['scheme-normal']['result'], 'mixed-scheme-and-data')
        self.assertFalse(result['productionPolicySchemeCompatible'])
        for view in case['views']:
            view['preparation'].update(transport='data', schemeFailure='font-load-failed')
        case['freshOwnedFontAfterClosingFirst'].update(transport='data', sourceBytes=100)
        result = validate(envelope)
        self.assertEqual(result['routes'][ROUTES[0]]['scheme-normal']['result'], 'verified-data-fallback')
        self.assertFalse(result['productionPolicySchemeCompatible'])
        case['views'][0]['preparation']['schemeFailure'] = 'font-timeout'
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            validate(envelope)



class NativeReportReplayTests(unittest.TestCase):
    """Replay immutable first-run artifacts; their full acceptance must stay rejected."""

    def test_original_ios_bridge_reports_and_failed_source_gate(self):
        supplied = os.environ.get('IOS_FONT_NATIVE_REPLAY_ROOT')
        if not supplied:
            self.skipTest('Original native artifacts were not supplied; this is not native acceptance.')
        root = Path(supplied)
        expected = {
            1: '5549994f8e5d3f6379c2e15fa2574ca4d08e4c71ec9e1f495c6b829573b4fcbb',
            5: '26ac88605f3987a8026dbc4a51e852e9f4bda71f45e161e1fbf3cc72ab0f5dbe',
            10: 'c239f15926b36339cb949c0708cd416d2f56b74e69953b25ce9353e01ac2652f',
        }
        for count, digest in expected.items():
            with self.subTest(instances=count):
                reports = list((root / str(count)).rglob('report.json'))
                environments = list((root / str(count)).rglob('environment.json'))
                self.assertEqual(len(reports), 1)
                self.assertEqual(len(environments), 1)
                path, environment_path = reports[0], environments[0]
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest)
                retained = [p for p in (root / str(count)).rglob('*') if p.is_file()]
                before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in retained}
                envelope = read_json(path)
                environment = read_json(environment_path)
                report = envelope['data']['iosFontProbe']
                self.assertEqual(report['instances'], count)
                self.assertEqual(len(report['cases']), 18)
                self.assertIs(type(report['cases'][0]['views'][0]['rendering']['bootCount']), float)
                summary = validate(envelope)
                self.assertEqual(summary['decision'], 'keep-default-off')
                self.assertEqual(environment['sourceStatus'], '')
                self.assertEqual({line.strip() for line in environment['sourceStatusAfter'].splitlines()}, {
                    'M ios/Runner.xcodeproj/project.pbxproj',
                    'M ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
                })
                with self.assertRaises(ValueError):
                    validate_artifacts(path, environment, environment_path.parent)
                self.assertEqual({p: hashlib.sha256(p.read_bytes()).hexdigest() for p in retained}, before)
                print(json.dumps({'nativeReportReplayInstances': count, 'reportSha256': digest,
                                  'reportSemantics': 'passed', 'originalFullAcceptance': 'rejected',
                                  'decision': 'keep-default-off'}))


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.path = artifacts(self.root)
        self.environment = environment_fixture()

    def tearDown(self):
        self.temp.cleanup()

    def test_exact_raw_framework_and_pngs_validate(self):
        result = validate_artifacts(self.path, self.environment)
        self.assertEqual(result['sourceCommit'], '1' * 40)
        self.assertEqual(len(result['reportSha256']), 64)

    def test_edited_report_cannot_replace_framework_data(self):
        envelope = read_json(self.path)
        envelope['data']['iosFontProbe']['unreportedClaim'] = 'made-up'
        self.path.write_text(json.dumps(envelope))
        with self.assertRaisesRegex(ValueError, 'raw framework'):
            validate_artifacts(self.path, self.environment)

    def test_raw_framework_failure_is_never_reclassified(self):
        path = self.root / 'framework-response.json'
        raw = read_json(path)
        raw['result'] = 'false'
        path.write_text(json.dumps(raw))
        with self.assertRaisesRegex(ValueError, 'raw framework'):
            validate_artifacts(self.path, self.environment)

    def test_corrupt_and_replaced_pngs_fail(self):
        png = next(self.root.glob('*.png'))
        for contents in (b'\x89PNG\r\n\x1a\n' + b'0' * 30, png_bytes(2)):
            png.write_bytes(contents)
            with self.assertRaises(ValueError):
                validate_artifacts(self.path, self.environment)

    def test_missing_sdk_native_source_runtime_or_timeout_provenance_fails(self):
        probe = fixture()['data']['iosFontProbe']
        mutations = [
            lambda env: env['flutter'].update(frameworkRevision='0' * 40),
            lambda env: env['flutter'].update(engineRevision='0' * 40),
            lambda env: env.update(flutterSourceStatusAfter=' M file'),
            lambda env: env.update(lockSha256After='0' * 64),
            lambda env: env['nativeSources']['flutter_inappwebview_ios'].update(statusAfter=' M native'),
            lambda env: env.update(webviewPin='0' * 40),
            lambda env: env.update(sourceCommitAfter='0' * 40),
            lambda env: env.update(sourceStatusAfter=' M ios/Runner.xcodeproj/project.pbxproj'),
            lambda env: env.update(lockSourceCommit='0' * 40),
            lambda env: env.update(committedLockSha256='0' * 64),
            lambda env: env['nativeSources']['flutter_inappwebview_android'].update(head='0' * 40),
            lambda env: env['nativeSources']['flutter_inappwebview_ios'].update(headAfter='0' * 40),
            lambda env: env.update(xcode=''),
            lambda env: env.update(rustTargets='aarch64-apple-ios'),
            lambda env: env['runtime'].update(booted=False),
            lambda env: env.update(podfileLockSha256=None),
            lambda env: env['drive'].update(timedOut=True),
            lambda env: env['drive'].update(groupDrained=False),
            lambda env: env['drive'].update(returncode=1),
        ]
        for mutate in mutations:
            env = copy.deepcopy(self.environment)
            mutate(env)
            with self.assertRaises(ValueError):
                validate_environment(env, probe)

    def test_non_json_numbers_fail_before_validation(self):
        self.path.write_text('{"fake": NaN}')
        with self.assertRaisesRegex(ValueError, 'Non-JSON'):
            read_json(self.path)

    def test_changed_native_heads_cannot_rewrite_the_committed_lock_evidence(self):
        self.environment['webviewPin'] = '5' * 40
        for name, source in self.environment['nativeSources'].items():
            if name.startswith('flutter_inappwebview'):
                source.update(head='5' * 40, headAfter='5' * 40, lockPin='5' * 40)
        with self.assertRaisesRegex(ValueError, 'committed lock artifact'):
            validate_artifacts(self.path, self.environment)

    def test_retained_app_and_cocoapods_locks_are_both_required(self):
        for name in ('pubspec.lock', 'Podfile.lock'):
            path = self.root / name
            original = path.read_bytes()
            path.write_bytes(original + b'changed')
            with self.assertRaisesRegex(ValueError, 'lock differs'):
                validate_artifacts(self.path, self.environment)
            path.write_bytes(original)


if __name__ == '__main__':
    unittest.main()
