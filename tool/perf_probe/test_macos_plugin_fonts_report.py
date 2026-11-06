import copy
import unittest

from compare_macos_plugin_fonts import SAMPLE_KEYS, validate_pair


def report(mode, count=1):
    cases = []
    for scenario in ('normal', 'font-src-data', 'style-src-none'):
        blocked = scenario == 'style-src-none'
        transport = 'unavailable' if blocked else mode if scenario == 'normal' else 'data'
        samples = [
            {'key': key, 'width': 123.5, 'pixelHash': key, 'inkPixels': 90,
             'loadedFaces': [{'family': 'Fixture', 'weight': ('700' if key == 'bundled-bold' else '100 900' if key.startswith('variable') else '400'), 'status': 'loaded'}]}
            for key in SAMPLE_KEYS
        ]
        prep = {'ready': not blocked, 'transport': transport,
                'javascriptUtf8Bytes': 700, 'argumentJsonUtf8Bytes': 2000,
                'outcome': {'reason': 'style-blocked' if blocked else 'loaded'}}
        if mode == 'scheme' and scenario != 'normal':
            prep['schemeFailure'] = 'style-blocked' if blocked else 'font-load-failed'
        cases.append({'scenario': scenario, 'views': [{
            'index': 0, 'preparation': prep, 'bootJavascriptUtf8Bytes': 50000,
            'bootAcknowledged': True,
            'schemeBytesAtBoot': 1000 if transport == 'scheme' else 0,
            'schemeResponseBytes': 1000 if transport == 'scheme' else 0,
            'schemeResponses': 1 if transport == 'scheme' else 0,
            'fontReadyFromViewCreationMicroseconds': None if blocked else 90000,
            'screenshot': None if blocked else 'fixture.png',
            'rendering': {'bootCount': 1, 'visible': True, 'samples': [] if blocked else samples,
                          'readyFacesAtBoot': [{'family': f} for f in ('Fixture', 'FrankRuhlCLM', 'Rubik')]},
        }]})
        first = cases[-1]['views'][0]
        cases[-1]['views'] = [dict(copy.deepcopy(first), index=i) for i in range(count)]
        if scenario == 'normal' and count > 1:
            cases[-1]['survivorAfterClosingFirst'] = ['loaded']
            cases[-1]['freshSchemeAfterClosingFirst'] = (
                {'availability': 'verified', 'faceStatus': 'loaded', 'loaderReads': 1,
                 'requestDelta': 1, 'responseDelta': 1, 'responseBytesDelta': 1000}
                if mode == 'scheme' else {'availability': 'not-run', 'reason': 'data-control'})
    return {'schemaVersion': 1, 'requestedTransport': mode, 'instances': count,
            'pid': 100 if mode == 'data' else 101, 'platform': 'macos',
            'systemFont': {'family': 'Fixture'}, 'hostKind': 'visible-flutter-platform-view',
            'window': {'ready': True}, 'decision': 'keep-default-off',
            'ios': 'disabled-unvalidated', 'engineMemory': {'availability': 'unsupported'},
            'engineCpu': {'availability': 'unsupported'}, 'cases': cases}


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.data, self.scheme = report('data'), report('scheme')

    def test_complete_pair_stays_disabled(self):
        summary = validate_pair(self.data, self.scheme)
        self.assertEqual(summary['decision'], 'keep-default-off')
        self.assertTrue(summary['normalSchemeVerified'])

    def test_rejects_missing_actual_face(self):
        self.scheme['cases'][0]['views'][0]['rendering']['samples'][0]['loadedFaces'] = []
        with self.assertRaisesRegex(ValueError, 'FontFace'):
            validate_pair(self.data, self.scheme)

    def test_rejects_missing_guarded_boot_acknowledgement(self):
        self.scheme['cases'][0]['views'][0].pop('bootAcknowledged')
        with self.assertRaisesRegex(ValueError, 'acknowledgement'):
            validate_pair(self.data, self.scheme)

    def test_cached_survivor_is_not_a_fresh_scheme_request(self):
        data, scheme = report('data', 5), report('scheme', 5)
        self.assertEqual(validate_pair(data, scheme)['modes']['scheme']
                         ['freshSchemeAfterClosingFirst']['loaderReads'], 1)
        for field in ('loaderReads', 'requestDelta', 'responseDelta', 'responseBytesDelta'):
            broken = copy.deepcopy(scheme)
            broken['cases'][0]['freshSchemeAfterClosingFirst'][field] = 0
            with self.assertRaisesRegex(ValueError, 'fresh survivor'):
                validate_pair(data, broken)
        scheme['cases'][0].pop('freshSchemeAfterClosingFirst')
        with self.assertRaisesRegex(ValueError, 'fresh survivor'):
            validate_pair(data, scheme)

    def test_unmeasured_survivor_must_be_explicit(self):
        data, scheme = report('data', 5), report('scheme', 5)
        scheme['cases'][0]['views'][-1]['preparation']['transport'] = 'data'
        scheme['cases'][0]['freshSchemeAfterClosingFirst'] = {
            'availability': 'not-run', 'reason': 'normal-scheme-unavailable'}
        self.assertFalse(validate_pair(data, scheme)['normalSchemeVerified'])
        data['cases'][0].pop('freshSchemeAfterClosingFirst')
        with self.assertRaisesRegex(ValueError, 'explicit'):
            validate_pair(data, scheme)

    def test_rejects_fonts_that_only_loaded_after_boot(self):
        self.scheme['cases'][0]['views'][0]['rendering']['readyFacesAtBoot'] = []
        with self.assertRaisesRegex(ValueError, 'plugin.ready'):
            validate_pair(self.data, self.scheme)

    def test_rejects_pixel_change_with_equal_width(self):
        self.scheme['cases'][0]['views'][0]['rendering']['samples'][0]['pixelHash'] = 'wrong'
        with self.assertRaisesRegex(ValueError, 'rendering differs'):
            validate_pair(self.data, self.scheme)

    def test_rejects_csp_false_success(self):
        self.scheme['cases'][2]['views'][0]['preparation']['ready'] = True
        with self.assertRaisesRegex(ValueError, 'blocked style'):
            validate_pair(self.data, self.scheme)

    def test_rejects_invented_zero_cpu(self):
        self.scheme['engineCpu']['value'] = 0
        with self.assertRaisesRegex(ValueError, 'numeric result'):
            validate_pair(self.data, self.scheme)

    def test_rejects_same_process_and_fake_scheme_success(self):
        broken = copy.deepcopy(self.scheme)
        broken['pid'] = self.data['pid']
        with self.assertRaisesRegex(ValueError, 'fresh app processes'):
            validate_pair(self.data, broken)
        self.scheme['cases'][0]['views'][0]['schemeBytesAtBoot'] = 0
        with self.assertRaisesRegex(ValueError, 'served font bytes'):
            validate_pair(self.data, self.scheme)

    def test_valid_fallback_is_not_evidence_of_scheme_support(self):
        self.scheme['cases'][0]['views'][0]['preparation']['transport'] = 'data'
        summary = validate_pair(self.data, self.scheme)
        self.assertFalse(summary['normalSchemeVerified'])
        self.assertEqual(summary['decision'], 'keep-default-off')


if __name__ == '__main__':
    unittest.main()
