"""The Apple font workflows' macOS-runner gate and time budgets."""
from pathlib import Path
import re
import unittest

import apple_font_probe_changes as changes

WORKFLOWS = Path(__file__).resolve().parents[2] / '.github/workflows'

LOCK = '''packages:
  flutter_inappwebview_ios:
    dependency: "direct overridden"
    description:
      resolved-ref: "{webview}"
      url: "https://github.com/Otzaria/flutter_inappwebview"
    source: git
    version: "1.2.0-beta.3"
  path_provider_foundation:
    dependency: transitive
    version: "2.4.1"
  window_manager:
    dependency: "direct main"
    version: "0.5.0"
  sqlite3:
    dependency: transitive
    version: "{sqlite}"
sdks:
  dart: ">=3.12.0 <4.0.0"
'''

PUBSPEC = '''name: otzaria
dependencies:
  flutter:
    sdk: flutter
  flutter_inappwebview:
    git:
      url: https://github.com/Otzaria/flutter_inappwebview
      ref: {webview}
  # comment
  path_provider: ^2.1.6
  sqlite3: {sqlite}

flutter:
  uses-material-design: true
  assets:
    - assets/{asset}
  fonts:
    - family: FrankRuhlCLM
      fonts:
        - asset: fonts/{font}
'''


def lock(webview='a', sqlite='3.8.0'):
    return LOCK.format(webview=webview, sqlite=sqlite)


def pubspec(webview='a', sqlite='^3.8.0', asset='logo.png', font='FrankRuehlCLM-Medium.ttf'):
    return PUBSPEC.format(webview=webview, sqlite=sqlite, asset=asset, font=font)


def decide(files, base, head, probe='ios', paths=('lib/plugins/view/plugin_tab_page.dart', 'fonts/**',
                                                       'tool/perf_probe/*ios_plugin_fonts*', 'pubspec.lock')):
    return changes.decide(set(files), list(paths), lambda path: base.get(path, ''),
                          lambda path: head.get(path, ''), probe)


class ChangesGateTests(unittest.TestCase):
    def test_probe_files_always_need_the_simulator(self):
        run, reasons = decide(['fonts/a/Rubik.ttf', 'README.md'], {}, {})
        self.assertTrue(run)
        self.assertEqual(reasons, {'probeFiles': ['fonts/a/Rubik.ttf']})
        self.assertTrue(decide(['tool/perf_probe/run_ios_plugin_fonts.py'], {}, {})[0])
        self.assertFalse(decide(['tool/perf_probe/sub/run_ios_plugin_fonts.py'], {}, {})[0])

    def test_unrelated_dependency_bumps_skip_the_macos_runner(self):
        base = {'pubspec.lock': lock(), 'pubspec.yaml': pubspec()}
        head = {'pubspec.lock': lock(sqlite='3.9.0'), 'pubspec.yaml': pubspec(sqlite='^3.9.0', asset='icon.png')}
        self.assertEqual(decide(['pubspec.lock', 'pubspec.yaml'], base, head), (False, {'dependencies': []}))

    def test_webview_and_font_changes_need_the_simulator(self):
        base = {'pubspec.lock': lock(), 'pubspec.yaml': pubspec()}
        for files, head, expected in [
            (['pubspec.lock'], {'pubspec.lock': lock(webview='b')}, ['flutter_inappwebview_ios']),
            (['pubspec.yaml'], {'pubspec.yaml': pubspec(webview='b')}, ['dependencies.flutter_inappwebview']),
            (['pubspec.yaml'], {'pubspec.yaml': pubspec(font='Other.ttf')}, ['flutter.fonts']),
        ]:
            with self.subTest(expected=expected):
                self.assertEqual(decide(files, base, {**base, **head}), (True, {'dependencies': expected}))

    def test_window_manager_matters_only_to_the_macos_probe(self):
        base = {'pubspec.lock': lock()}
        head = {'pubspec.lock': lock().replace('"0.5.0"', '"0.6.0"')}
        self.assertFalse(decide(['pubspec.lock'], base, head, 'ios')[0])
        self.assertTrue(decide(['pubspec.lock'], base, head, 'macos')[0])

    def test_comments_cannot_split_a_section_into_false_changes(self):
        base = {'pubspec.yaml': pubspec().replace('  # comment\n', '# column-zero comment\n')}
        head = {'pubspec.yaml': pubspec().replace('  # comment\n', '  # reworded\n')}
        self.assertEqual(decide(['pubspec.yaml'], base, head), (False, {'dependencies': []}))

    def test_added_or_removed_relevant_packages_are_changes(self):
        base = {'pubspec.lock': lock()}
        head = {'pubspec.lock': lock().replace('  path_provider_foundation:\n    dependency: transitive\n'
                                               '    version: "2.4.1"\n', '')}
        self.assertEqual(decide(['pubspec.lock'], base, head)[1], {'dependencies': ['path_provider_foundation']})
        self.assertTrue(decide(['pubspec.lock'], {}, base)[0])

    def test_each_workflow_paths_filter_is_read_and_globs_match_like_github(self):
        for name in ('ios_plugin_font_probe.yml', 'macos_plugin_font_probe.yml'):
            paths = changes.workflow_paths((WORKFLOWS / name).read_text())
            with self.subTest(name=name):
                self.assertIn('.github/workflows/' + name, paths)
                self.assertIn('pubspec.lock', paths)
                self.assertNotIn('ios/**', paths)
                self.assertIn('tool/perf_probe/apple_font_probe_changes.py', paths)
        self.assertTrue(changes.glob_regex('fonts/**').match('fonts/a/b.ttf'))
        self.assertFalse(changes.glob_regex('lib/*.dart').match('lib/a/b.dart'))
        self.assertTrue(changes.glob_regex('test/**/x_test.dart').match('test/x_test.dart'))


def job(text, name):
    match = re.search(r'^  ' + name + r':\n((?:    .*\n|\n)+)', text, re.M)
    return match[1]


class WorkflowBudgetTests(unittest.TestCase):
    def test_the_simulator_needs_the_gate_and_the_contracts(self):
        for name, mac_job in (('ios_plugin_font_probe.yml', 'simulator'), ('macos_plugin_font_probe.yml', 'wkwebview')):
            text = (WORKFLOWS / name).read_text()
            with self.subTest(name=name):
                self.assertIn('needs: [changes, contracts]', job(text, mac_job))
                self.assertIn("if: needs.changes.outputs.run == 'true'", job(text, mac_job))
                self.assertIn('needs: changes', job(text, 'contracts'))
                self.assertIn('schedule:', text)
                self.assertNotIn('cache: false', text)
                self.assertIn('.dart_tool/hooks_runner/shared', job(text, mac_job))

    def test_three_counts_fit_inside_the_step_and_job_timeouts(self):
        simulator = job((WORKFLOWS / 'ios_plugin_font_probe.yml').read_text(), 'simulator')
        job_minutes = int(re.search(r'^    timeout-minutes: (\d+)$', simulator, re.M)[1])
        step = re.search(r'timeout-minutes: (\d+)\n        run: \|\n(?:          .*\n)*?'
                         r'          budget_minutes=(\d+)\n', simulator)
        step_minutes, budget_minutes = int(step[1]), int(step[2])
        others = sum(int(m) for m in re.findall(r'timeout-minutes: (\d+)', simulator)[1:]) - step_minutes
        self.assertLessEqual(budget_minutes + 5, step_minutes)
        self.assertLessEqual(step_minutes + others, job_minutes)
        self.assertIn('--deadline-epoch "$deadline"', simulator)
        self.assertNotIn('x86_64-apple-ios', simulator)


if __name__ == '__main__':
    unittest.main()
