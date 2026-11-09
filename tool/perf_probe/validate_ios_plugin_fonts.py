#!/usr/bin/env python3
"""Validate native iOS compatibility evidence; an incomplete run is never a no-go."""
import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import zlib

ROUTES = ('file-production-policy', 'file-lab-policy', 'scheme-page-lab-policy')
SCENARIOS = ('normal', 'font-src-data', 'style-src-none')
SPECS = {
    'bundled-regular': ('FrankRuhlCLM', '400'),
    'bundled-bold': ('FrankRuhlCLM', '700'),
    'variable-light': ('Rubik', '300'),
    'variable-bold': ('Rubik', '700'),
}
ORIGIN = 'otzaria-plugin://ios.font.probe'
LAB_FILTER = r'^otzaria-plugin://ios\.font\.probe/'

FLUTTER_REVISION = 'abaf9c523780a608bd46686fd5e53740a07077f8'
ENGINE_REVISION = 'deb287481e3ce9468f3434937ced4240a70539ca'
WEBVIEW_PACKAGES = ('flutter_inappwebview', 'flutter_inappwebview_android', 'flutter_inappwebview_ios',
                    'flutter_inappwebview_linux', 'flutter_inappwebview_macos',
                    'flutter_inappwebview_platform_interface', 'flutter_inappwebview_web', 'flutter_inappwebview_windows')
NATIVE_PACKAGES = ('otzaria_search_engine', *WEBVIEW_PACKAGES)
THEME = {'typography': {'fontFamily': 'FrankRuhlCLM', 'commentatorsFontFamily': 'FrankRuhlCLM',
                        'uiFontFamily': 'Rubik', 'fontSize': 28}}


def blocker(pattern, allowed=False):
    return {'trigger': {'url-filter': pattern, 'url-filter-is-case-sensitive': allowed},
            'action': {'type': 'ignore-previous-rules' if allowed else 'block'}}


PRODUCTION_BLOCKERS = [blocker('.*')] + [blocker(p, True) for p in ('^about:', '^data:', '^blob:', '^file:')]
_SERVERS = (r'^http://127\.0\.0\.1:1/', '^http://localhost:1/')
PRODUCTION_BLOCKERS += [blocker(p) for p in _SERVERS]
PRODUCTION_BLOCKERS += [blocker(p + suffix, True) for p in _SERVERS
                        for suffix in (r'f/ios\.font\.probe/', 'w/', 'fonts/')]
_SOURCES = "'self' " + ORIGIN + ' file: data: blob: ' + ' '.join(
    f'http://{host}:1/{path}/' for host in ('127.0.0.1', 'localhost') for path in ('f/ios.font.probe', 'w', 'fonts'))
PRODUCTION_CSP = f"default-src {_SOURCES} 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval'; form-action {_SOURCES}; base-uri 'self'"


def positive_int(value):
    return type(value) is int and value > 0


def javascript_integer(value, *, minimum=0, maximum=2 ** 53 - 1):
    # WKWebView can bridge a JavaScript Number to a JSON float. Validate its
    # value, without coercing strings/bools or weakening Dart integer fields.
    return (type(value) in (int, float) and minimum <= value <= maximum and
            math.isfinite(value) and value == math.trunc(value))


def positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def validate_rendering_trace(view, identity):
    trace = view['rendering']['renderingProgress']
    require(trace['documentId'] == identity['documentId'] and trace['owner'] == identity['owner'], 'rendering trace belongs to another document')
    require(type(view['renderingRequestedAtEpochMilliseconds']) is int and
            javascript_integer(trace['startedAtEpochMilliseconds'], minimum=1) and
            trace['startedAtEpochMilliseconds'] >= view['renderingRequestedAtEpochMilliseconds'], 'native dispatch trace absent')
    expected = [('started', None)]
    for key in SPECS:
        expected += [(phase, key) for phase in ('font-load-started', 'font-load-completed', 'canvas-started', 'canvas-completed')]
    expected += [(phase, None) for phase in ('frames-requested', 'frame-1', 'frame-2', 'fallback-started', 'fallback-completed', 'completed')]
    events = trace['events']
    require(trace['phase'] == 'completed' and javascript_integer(trace['droppedEvents'], maximum=0) and
            [(e['phase'], e['fontKey']) for e in events] == expected, 'font/canvas/native frames incomplete')
    times = [e['elapsedMilliseconds'] for e in events]
    require(all(type(t) in (int, float) and math.isfinite(t) and t >= 0 for t in times) and
            times == sorted(times) and
            type(trace['elapsedMilliseconds']) in (int, float) and
            math.isfinite(trace['elapsedMilliseconds']) and trace['elapsedMilliseconds'] == times[-1] and
            all(e['visibilityState'] == 'visible' for e in events), 'hidden or invalid rendering trace')


def validate_png(png):
    require(png.startswith(b'\x89PNG\r\n\x1a\n'), 'native screenshot is not PNG')
    offset, chunks, image_bytes = 8, [], 0
    while offset < len(png):
        require(offset + 12 <= len(png), 'truncated PNG chunk')
        size = int.from_bytes(png[offset:offset + 4], 'big')
        end = offset + 12 + size
        require(end <= len(png), 'truncated PNG payload')
        kind, data = png[offset + 4:offset + 8], png[offset + 8:end - 4]
        require(zlib.crc32(kind + data) == int.from_bytes(png[end - 4:end], 'big'), 'PNG checksum differs')
        if not chunks:
            require(kind == b'IHDR' and size == 13, 'PNG header missing')
            width, height = struct.unpack('>II', data[:8])
            require(0 < width <= 16384 and 0 < height <= 16384, 'empty/oversized native screenshot')
        if kind == b'IDAT':
            image_bytes += size
        chunks.append(kind)
        offset = end
        if kind == b'IEND':
            require(size == 0 and offset == len(png), 'PNG trailing bytes')
            break
    require(chunks and chunks[-1] == b'IEND' and image_bytes > 0, 'PNG has no image data')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(envelope):
    require(type(envelope['schemaVersion']) is int and envelope['schemaVersion'] == 1, 'unknown envelope')
    framework = envelope['framework']
    require(framework['allTestsPassed'] is True and framework['failures'] == [],
            'framework failed or did not finish')
    report = envelope['data']['iosFontProbe']
    require(type(report['schemaVersion']) is int and report['schemaVersion'] == 1 and report['status'] == 'completed', 'probe incomplete')
    require(report['platform'] == 'ios' and report['osVersion'] and report['dartVersion'], 'not native iOS')
    require(report['buildMode'] in ('debug', 'profile', 'release'), 'unknown build mode')
    require(report['deviceKind'] in ('simulator', 'physical'), 'unknown device kind')
    require(report['deviceKind'] != 'simulator' or report['buildMode'] == 'debug', 'simulator must use debug')
    for mode in ('profile', 'release'):
        expected = 'this-run' if report['buildMode'] == mode else 'notRun'
        require(report['physical' + mode.capitalize()] == expected, 'physical coverage claim differs')
    require(re.fullmatch(r'[0-9a-f]{40}', report['sourceCommit']), 'missing source commit')
    require(re.fullmatch(r'[0-9a-f]{64}', report['lockSha256']), 'missing lock identity')
    require(report['framePolicy'] == 'fullyLive' and report['frameDriver'] == 'fullyLive-value-notifier', 'native frame driver differs')
    require(report['hostKind'] == 'visible-flutter-platform-view', 'headless is not rendering evidence')
    require(report['decision'] == 'keep-default-off' and report['productionIosExperimentEnabled'] is False, 'production must stay disabled')
    for key in ('engineMemory', 'engineCpu'):
        require(report[key] == {'availability': 'unsupported'}, 'host metrics cannot stand in for WebContent')
    require(report['crossViewCacheSharing'] == {'availability': 'not-measured'}, 'cache sharing was not measured')
    count = report['instances']
    require(type(count) is int and count in (1, 5, 10), 'invalid view count')
    expected_ids = {f'{r}-{t}-{s}' for r in ROUTES for t in ('data', 'scheme') for s in SCENARIOS}
    cases = {c['id']: c for c in report['cases']}
    require(len(cases) == len(report['cases']) and set(cases) == expected_ids, 'missing/duplicate compatibility case')
    require(report['theme'] == THEME, 'selected typography changed')
    identities, documents = set(), set()
    summary = {'decision': 'keep-default-off', 'instances': count, 'deviceKind': report['deviceKind'],
               'buildMode': report['buildMode'], 'routes': {}}
    for route in ROUTES:
        summary['routes'][route] = {}
        base_rules = PRODUCTION_BLOCKERS
        base_csp = PRODUCTION_CSP
        for scenario in SCENARIOS:
            for requested in ('data', 'scheme'):
                case = cases[f'{route}-{requested}-{scenario}']
                require(case['status'] == 'completed' and case['scenario'] == scenario and
                        case['requestedTransport'] == requested and case['cleanupStatus'] == 'completed' and
                        'cleanupError' not in case and 'error' not in case, 'case or cleanup did not complete as requested')
                policy = case['policy']
                lab = route != ROUTES[0]
                file_page = route != ROUTES[2]
                registered = requested == 'scheme' or not file_page
                require(policy['route'] == route, 'production and lab routes were conflated')
                require(policy['documentScheme'] == ('file' if file_page else 'otzaria-plugin'), 'document origin changed')
                require(policy['contentBlockers'] == ('lab-exact-origin-added' if lab else 'production'), 'blocker policy mislabeled')
                require(policy['labAllowFilter'] == (LAB_FILTER if lab else None), 'lab exception differs')
                rules = policy['contentBlockerRules']
                if lab:
                    require(rules[:-1] == base_rules, 'lab changed the production blocker rules')
                    last = rules[-1]
                    require(last == blocker(LAB_FILTER, True), 'lab allow rule is not exact')
                else:
                    require(rules == base_rules and len(rules) > 4, 'production blockers differ')
                require(policy['resourceCustomSchemes'] == (['otzaria-plugin'] if registered else []), 'scheme registration missing or broadened')
                require(policy['schemeRegistration'] == ('experiment-added' if registered else 'production'), 'registration override hidden')
                require(policy['handler'] == ('production-servePluginAsset' if registered else 'not-registered'), 'handler differs')
                require(policy['allowFileAccessFromFileURLs'] is False and
                        policy['allowUniversalAccessFromFileURLs'] is False and
                        policy['allowingReadAccessTo'] is None and policy['incognito'] is True and
                        policy['responseAddsAccessControlAllowOrigin'] is False, 'security/storage control widened')
                suffix = {'normal': '', 'font-src-data': '; font-src data:', 'style-src-none': "; style-src 'none'"}[scenario]
                require(policy['csp'] == base_csp + suffix and ORIGIN in base_csp, 'CSP controls differ')
                views = case['views']
                require(len(views) == count and all(type(v['index']) is int for v in views) and {v['index'] for v in views} == set(range(count)), 'missing/duplicate view')
                transports = []
                for view in views:
                    require(view['status'] == 'completed' and view['disposed'] is True, 'view incomplete or not disposed')
                    operations = view['operations']
                    names = [o['name'] for o in operations]
                    needed = {'font-preparation', 'boot', 'rendering', 'policy-diagnostics'}
                    if scenario != 'style-src-none':
                        needed.add('screenshot')
                    if view['index'] == count - 1:
                        needed.add('navigation-ownership')
                        if count > 1 and scenario == 'normal':
                            needed.add('fresh-survivor-font-load')
                    require(needed == set(names) and len(names) == len(set(names)) and
                            all(o['status'] == 'completed' and not o.get('lateResponse') and not o.get('lateError') for o in operations), 'native operation failed, late or missing')
                    require('failure' not in view and 'failureSnapshot' not in view, 'late native failure')
                    for operation in operations:
                        require(operation['timeoutMilliseconds'] == 10000 and
                                type(operation['startedMicroseconds']) is int and type(operation['responseMicroseconds']) is int and
                                0 <= operation['startedMicroseconds'] <= operation['responseMicroseconds'] and
                                operation['responseMicroseconds'] - operation['startedMicroseconds'] <= 10000000, 'operation deadline changed or exceeded')
                    identity, diagnostics = view['documentIdentity'], view['policyDiagnostics']
                    owner = identity['owner']
                    require(isinstance(owner, str) and owner and owner == identity['leaseId'] and owner not in identities, 'lease ownership reused')
                    identities.add(owner)
                    require(isinstance(identity['documentId'], str) and identity['documentId'] and identity['documentId'] not in documents, 'document identity reused')
                    documents.add(identity['documentId'])
                    require(diagnostics['owner'] == owner and diagnostics['documentId'] == identity['documentId'] and identity['documentId'], 'document not bound to owner')
                    require(diagnostics['href'].startswith('file:///' if file_page else ORIGIN + '/') and
                            diagnostics['href'].endswith('/' + case['id'] + '.html'), 'observed document route differs')
                    allowed_urls = {diagnostics['href']}
                    if view['index'] == count - 1:
                        allowed_urls.add(diagnostics['href'][:-5] + '-navigation.html')
                    decisions = [e for e in view['events'] if e['event'] == 'navigation-decision']
                    require(decisions and {e['url'] for e in decisions} == allowed_urls and
                            all(e['isForMainFrame'] is True and e['policy'] == 'allow' for e in decisions), 'navigation gate missing or broadened')
                    require('origin' in diagnostics and isinstance(diagnostics['violations'], list) and
                            javascript_integer(diagnostics['droppedViolations']), 'origin/CSP observations absent')
                    for event in view['events']:
                        if event['event'] == 'scheme-response':
                            require(event['accessControlAllowOrigin'] is None, 'unexpected ACAO response')
                    prep, rendering = view['preparation'], view['rendering']
                    require(view['bootAcknowledged'] is True and javascript_integer(rendering['bootCount'], minimum=1, maximum=1) and
                            rendering['bootTheme'] == report['theme'] and rendering['visible'] is True, 'SDK boot/theme/visibility failed')
                    require(all(positive_int(n) for n in (view['bootJavascriptUtf8Bytes'], prep['javascriptUtf8Bytes'],
                            prep['argumentJsonUtf8Bytes'])), 'submitted payload evidence missing')
                    transports.append(prep['transport'])
                    if scenario == 'style-src-none':
                        require(prep['ready'] is False and prep['transport'] == 'unavailable' and
                                prep['outcome']['reason'] == 'style-blocked' and rendering['samples'] == [] and
                                view['fontReadyFromViewCreationMicroseconds'] is None, 'CSP style denial falsely passed')
                        continue
                    validate_rendering_trace(view, identity)
                    require(prep['ready'] is True and prep['outcome']['reason'] == 'loaded' and
                            positive_int(view['fontReadyFromViewCreationMicroseconds']), 'font readiness missing')
                    require(prep['transport'] in ('data', 'scheme'), 'unknown effective transport')
                    if requested == 'data' or scenario == 'font-src-data':
                        require(prep['transport'] == 'data', 'data control/CSP fallback missing')
                    if requested == 'scheme' and prep['transport'] == 'data':
                        require(prep.get('schemeFailure') == 'font-load-failed', 'timeout/incomplete run cannot be a negative compatibility result')
                    else:
                        require('schemeFailure' not in prep, 'successful control has an unexplained failure')
                    if prep['transport'] == 'scheme':
                        require(all(positive_int(view[k]) for k in ('schemeRequests', 'schemeResponses', 'schemeResponseBytes', 'schemeBytesAtBoot')) and
                                view['schemeResponseBytes'] >= view['schemeBytesAtBoot'] > 0, 'scheme success lacks served bytes')
                    required_families = {'FrankRuhlCLM', 'Rubik'}
                    owned = {f['family'].strip("\"'") for f in prep['outcome'].get('faces', []) if f['status'] == 'loaded'}
                    boot = {f['family'].strip("\"'") for f in rendering['readyFacesAtBoot']}
                    require(required_families <= owned and required_families <= boot, 'owned selected fonts not ready at boot')
                    samples = {s['key']: s for s in rendering['samples']}
                    require(len(rendering['samples']) == 4 and set(samples) == set(SPECS), 'typography coverage missing')
                    for key, sample in samples.items():
                        require((sample['family'], sample['weight']) == SPECS[key], 'selected family/weight changed')
                        require(positive(sample['width']) and javascript_integer(sample['inkPixels'], minimum=1, maximum=650 * 80) and
                                re.fullmatch(r'[0-9a-f]{1,8}', sample['pixelHash']) and
                                sample['loadedFaces'] and all(f['status'] == 'loaded' and f['family'].strip("\"'") == sample['family'] for f in sample['loadedFaces']), 'empty/fallback FontFace or rendering')
                    require(any(f['weight'] == '700' for f in samples['bundled-bold']['loadedFaces']), 'bold face missing')
                    require(any(f['weight'] == '100 900' for f in samples['variable-bold']['loadedFaces']), 'variable axis missing')
                    require(samples['bundled-regular']['pixelHash'] != samples['bundled-bold']['pixelHash'] and
                            samples['variable-light']['pixelHash'] != samples['variable-bold']['pixelHash'], 'weights rendered identically')
                    fallback = rendering['fallbackControl']
                    require(positive(fallback['width']) and javascript_integer(fallback['inkPixels'], minimum=1, maximum=650 * 80) and
                            re.fullmatch(r'[0-9a-f]{1,8}', fallback['pixelHash']), 'generic rendering control missing')
                    require(any(s['pixelHash'] != fallback['pixelHash'] for s in samples.values()), 'only generic font rendered')
                    require(all(positive(rendering['viewport'][key]) for key in ('width', 'height', 'dpr')) and rendering['userAgent'], 'viewport/WebKit identity missing')
                    require(view.get('screenshot'), 'screenshot missing')
                nav = case['navigation']
                last = next(v for v in views if v['index'] == count - 1)
                require('navigation-ownership' in [o['name'] for o in last['operations']], 'navigation operation missing')
                require(nav['oldOwner'] == last['documentIdentity']['owner'] and
                        nav['oldDocumentId'] == last['documentIdentity']['documentId'] and
                        nav['newDocument']['documentId'] and nav['newDocument']['documentId'] != nav['oldDocumentId'] and
                        nav['requestedUrl'] == nav['observedUrl'] == last['policyDiagnostics']['href'][:-5] + '-navigation.html' and nav['oldLeaseInactive'] is True and
                        javascript_integer(nav['newDocument']['bootCount'], maximum=0) and nav['newDocument']['staleEffect'] is False and
                        nav['rejectedBoot'] == {'booted': False, 'reason': 'stale-document'}, 'stale boot/navigation was not rejected')
                if count > 1 and scenario == 'normal':
                    peer, fresh = case['peerClose'], case['freshOwnedFontAfterClosingFirst']
                    first = next(v for v in views if v['index'] == 0)
                    require(peer['closedLeaseInactive'] is True and peer['survivorLeaseActive'] is True and
                            peer['closedOwner'] == first['documentIdentity']['owner'] and
                            peer['survivorOwner'] == last['documentIdentity']['owner'], 'peer disposal crossed owners')
                    require(fresh['availability'] == 'verified' and fresh['faceStatus'] == 'loaded' and
                            fresh['owner'] == last['documentIdentity']['owner'] and
                            fresh['documentId'] == last['documentIdentity']['documentId'] and
                            fresh['transport'] == last['preparation']['transport'], 'fresh survivor font not owned or not verified')
                    if last['preparation']['transport'] == 'scheme':
                        require(fresh['availability'] == 'verified' and fresh['faceStatus'] == 'loaded' and
                                all(positive_int(fresh[k]) for k in ('loaderReads', 'requestDelta', 'responseDelta', 'responseBytesDelta')), 'fresh font after peer close not verified')
                    else:
                        require(positive_int(fresh['sourceBytes']), 'fresh data font bytes missing')
                summary['routes'][route][f'{requested}-{scenario}'] = {
                    'effectiveTransports': transports,
                    'result': 'style-blocked' if scenario == 'style-src-none' else
                              ('scheme-loaded' if all(t == 'scheme' for t in transports) else
                               'mixed-scheme-and-data' if len(set(transports)) > 1 else
                               'verified-data-fallback' if requested == 'scheme' else 'data-control'),
                }
            if scenario != 'style-src-none':
                a = cases[f'{route}-data-{scenario}']['views']
                b = cases[f'{route}-scheme-{scenario}']['views']
                for left, right in zip(sorted(a, key=lambda v: v['index']), sorted(b, key=lambda v: v['index'])):
                    samples = {s['key']: s for s in left['rendering']['samples']}
                    for sample in right['rendering']['samples']:
                        require(abs(samples[sample['key']]['width'] - sample['width']) <= 0.001 and
                                samples[sample['key']]['pixelHash'] == sample['pixelHash'], 'transport changed typography')
    summary['productionPolicySchemeCompatible'] = summary['routes'][ROUTES[0]]['scheme-normal']['result'] == 'scheme-loaded'
    summary['limitations'] = [
        'Lab results never establish compatibility with production file URLs/policy.',
        'A font rejection alone does not identify CORS, file-origin restrictions or content blockers.',
        'CSP events, native request Origin, registration and console diagnostics remain separate raw observations.',
        'Debug Simulator results establish functional coverage only, without memory/CPU/cache savings claims.',
        'The data control uses the bounded experimental verifier; production boot is unchanged.',
    ]
    return summary


def read_json(path):
    def invalid(value):
        raise ValueError(f'Non-JSON number: {value}')
    return json.loads(path.read_text(), parse_constant=invalid)


def lock_pin(text, name):
    match = re.search(r'^  ' + re.escape(name) + r':\n((?:    .*\n)+)', text, re.M)
    require(match is not None, f'Missing locked native dependency: {name}')
    pin = re.search(r'^      resolved-ref: "?([0-9a-f]{40})"?$', match[1], re.M)
    require(pin is not None and '    source: git\n' in match[1], f'Native dependency is not pinned Git: {name}')
    return pin[1]


def validate_environment(environment, probe):
    require(environment['schemaVersion'] == 1 and environment['captureStatus'] == 'complete', 'provenance capture incomplete')
    require(environment['runStatus'] == 'completed' and environment['drive']['returncode'] == 0 and
            environment['drive']['timedOut'] is False and environment['drive']['groupDrained'] is True, 'native runner failed or timed out')
    flutter = environment['flutter']
    require(flutter['frameworkVersion'] == '3.47.7' and flutter['frameworkRevision'] == FLUTTER_REVISION and
            flutter['engineRevision'] == ENGINE_REVISION and flutter['dartSdkVersion'].split()[0] == '3.13.5', 'unexpected Flutter SDK')
    require(environment['flutterSourceCommit'] == environment['flutterSourceCommitAfter'] == FLUTTER_REVISION and
            environment['flutterSourceStatus'] == environment['flutterSourceStatusAfter'] == '', 'Flutter SDK was modified')
    require(environment['sourceStatus'] == environment['sourceStatusAfter'] == '' and
            environment['sourceCommit'] == environment['sourceCommitAfter'] == probe['sourceCommit'] and
            environment['sourceTree'] == environment['sourceTreeAfter'] and
            environment['instances'] == probe['instances'] and
            environment['lockSha256'] == environment['lockSha256After'] == environment['committedLockSha256'] == probe['lockSha256'] and
            environment['lockSourceCommit'] == environment['sourceCommit'] and
            re.fullmatch(r'[0-9a-f]{40}', environment['sourceTree']), 'app source/lock changed during native run')
    require(all(isinstance(environment[k], str) and re.fullmatch(r'[0-9a-f]{40}', environment[k])
                for k in ('enginePin', 'webviewPin')), 'native source pin missing')
    native = environment['nativeSources']
    require(set(native) == set(NATIVE_PACKAGES), 'native source provenance missing')
    for name, source in native.items():
        expected = environment['enginePin'] if name == 'otzaria_search_engine' else environment['webviewPin']
        require(source['head'] == source['headAfter'] == source['lockPin'] == expected and source['status'] == source['statusAfter'] == '', 'native dependency modified')
    runtime = environment['runtime']
    require(runtime['deviceKind'] == probe['deviceKind'] == 'simulator' and environment['mode'] == probe['buildMode'] == 'debug', 'native runtime kind/mode differs')
    require(runtime['device']['udid'] and runtime['device']['isAvailable'] is True and
            runtime['device']['name'].startswith('iPhone') and '.iOS-' in runtime['identifier'] and
            runtime['version'] and runtime['buildversion'] and runtime['booted'] is True, 'actual iOS Simulator provenance missing')
    require(all(isinstance(environment[k], str) and environment[k].strip() for k in ('xcode', 'sdkVersion', 'sdkBuild', 'hostOS', 'hostArchitecture', 'rustc', 'cargo', 'rustToolchain', 'rustTargets')), 'Xcode/OS/Rust provenance missing')
    expected_target = 'aarch64-apple-ios-sim' if environment['hostArchitecture'] == 'arm64' else 'x86_64-apple-ios'
    require(environment['hostArchitecture'] in ('arm64', 'x86_64') and expected_target in environment['rustTargets'].splitlines(), 'Rust Simulator target differs from runner architecture')
    require(environment['podfileLockSha256'] and re.fullmatch(r'[0-9a-f]{64}', environment['podfileLockSha256']), 'native CocoaPods lock missing')


def validate_artifacts(path, environment, provenance_root=None):
    envelope = read_json(path)
    summary = validate(envelope)
    probe = envelope['data']['iosFontProbe']
    require(probe['sourceCommit'] == environment['sourceCommit'] and probe['lockSha256'] == environment['lockSha256'], 'build/source provenance differs')
    validate_environment(environment, probe)
    require(isinstance(environment.get('startupCheckpoint'), dict), 'authenticated native startup checkpoint missing')
    startup = environment['startupCheckpoint']
    require(positive_int(startup['hostPid']) and probe.get('pid') == startup['hostPid'] and
                startup['runId'] == environment['startupGeneration'] == probe.get('startupGeneration') and
                isinstance(environment.get('buildId'), str) and environment['buildId'] and
                startup.get('buildId') == environment['buildId'] == probe.get('buildId') and
                startup['nativeFork'] == environment['webviewPin'] and startup['appBootToken'] and
                startup['hostExecutable'] and startup.get('firstFrameRasterized') is True and
                probe.get('startupFirstFrameRasterized') is True, 'startup checkpoint differs from the measured native app')
    provenance_root = provenance_root or path.parent
    lock = provenance_root / 'pubspec.lock'
    require(hashlib.sha256(lock.read_bytes()).hexdigest() == probe['lockSha256'], 'retained source lock differs')
    blob = b'blob ' + str(lock.stat().st_size).encode() + b'\0' + lock.read_bytes()
    require(hashlib.sha1(blob).hexdigest() == environment['lockSourceBlob'], 'retained lock is not the committed Git blob')
    for name, source in environment['nativeSources'].items():
        require(lock_pin(lock.read_text(), name) == source['lockPin'], 'native source differs from committed lock artifact')
    require(hashlib.sha256((provenance_root / 'Podfile.lock').read_bytes()).hexdigest() ==
            environment['podfileLockSha256'], 'retained CocoaPods lock differs')
    raw = read_json(path.parent / 'framework-response.json')
    require(raw['result'] == 'true' and raw['failureDetails'] == [], 'raw framework result failed')
    original = raw['data']['iosFontProbe']
    for case in probe['cases']:
        raw_case = next(c for c in original['cases'] if c['id'] == case['id'])
        for view in case['views']:
            if case['scenario'] == 'style-src-none':
                continue
            name = view['screenshot']
            require(re.fullmatch(r'[a-z0-9-]+\.png', name), 'unsafe screenshot name')
            png = (path.parent / name).read_bytes()
            raw_view = next(v for v in raw_case['views'] if v['index'] == view['index'])
            validate_png(png)
            require(name == f"{case['id']}-{view['index']}.png" and
                    png == base64.b64decode(raw_view['screenshotBase64'], validate=True), 'missing/mismatched native screenshot')
            raw_view.pop('screenshotBase64')
            raw_view['screenshot'] = name
    require(raw['data'] == envelope['data'], 'normalized report differs from raw framework data')
    summary['sourceCommit'] = probe['sourceCommit']
    summary['reportSha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('reports', type=Path)
    parser.add_argument('--environment', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        paths = list(args.reports.glob('run-*/report.json'))
        require(len(paths) == 1, 'exactly one completed native report is required')
        summary = validate_artifacts(paths[0], read_json(args.environment), args.environment.parent)
        result = {'status': 'complete', 'compatibility': summary}
    except (ValueError, KeyError, TypeError, OSError, StopIteration, IndexError, AttributeError) as error:
        result = {'status': 'invalid-or-not-run', 'reason': str(error), 'decision': 'keep-default-off'}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        raise SystemExit(str(error))
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
