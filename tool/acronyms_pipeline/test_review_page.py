"""Run with python3 tool/acronyms_pipeline/test_review_page.py."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import make_review_page
import merge
from test_merge import BASE, row, SOURCES


class ReviewPage(unittest.TestCase):
    def test_merge_cli_ignores_agent_rows_and_removal_suggestions(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / 'data').mkdir()
            for name in ('merge.py', 'filters.py'):
                shutil.copy(Path(merge.HERE) / name, root / name)
            sources = json.loads(Path(merge.SOURCES).read_text(encoding='utf-8'))
            for src in sources['sources'].values():
                src.pop('merge_agent_checked', None)
            (root / 'data/sources.json').write_text(json.dumps(sources), encoding='utf-8')
            merge.write_ledger([row('ב"ה', 'בית הלל', status='agent_approved', reviewer='agent:claude')],
                               root / 'data/decisions.csv')
            (root / 'data/baseline_removals.csv').write_text('key,expansion,reason\nט"ו,חמישה עשר,gematria_number\n')
            baseline = merge.dump({'ט"ו': ['חמישה עשר']})
            (root / 'baseline.json').write_bytes(baseline)
            subprocess.run([sys.executable, str(root / 'merge.py'), '--baseline', str(root / 'baseline.json'),
                            '--out', str(root / 'out.json')], check=True, capture_output=True)
            self.assertEqual((root / 'out.json').read_bytes(), baseline)

    def test_unverified_ledger_rows_are_reviewable_without_auto_approval(self):
        rows = [row('ב"ה', 'בית הלל', status=s) for s in
                ('pending', 'agent_approved', 'needs_review', 'approved', 'rejected')]
        candidates = make_review_page.ledger_candidates(rows, BASE)
        self.assertEqual(len(candidates), 3)
        self.assertEqual({r['id'] for r in candidates}, {candidates[0]['id']})
        self.assertTrue(all('status' not in c for c in candidates))
        self.assertEqual(candidates[0]['reference'], rows[0]['reference'])

    def test_agent_reference_requires_independent_human_evidence(self):
        candidate = make_review_page.ledger_candidates(
            [row('א"א', 'אי אפשר', source='agent-verified-reference', status='agent_approved')], BASE)[0]
        self.assertEqual(candidate['sources'], ['human-verified-reference'])
        self.assertEqual(candidate['reference'], '')
        self.assertEqual(candidate['existing'], BASE['א"א'])

    def test_human_export_overrides_the_agent_proposal_and_enters_dictionary(self):
        proposal = row('ב"ה', 'בית הלל', status='agent_approved', reviewer='agent:claude')
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'export.csv')
            merge.write_ledger([row('ב"ה', 'בית הלל')], path)
            imported = merge.import_exports([proposal], [path])
        self.assertEqual(merge.validate(imported, SOURCES), [])
        self.assertEqual([r['status'] for r in imported], ['approved'])
        merged, _ = merge.apply(BASE, imported)
        self.assertEqual(merged['ב"ה'], ['בית הלל'])

    def test_next_batch_after_import_starts_at_first_unreviewed_pair(self):
        ledger = [row('ב"ה', 'בית הלל', status='agent_approved'),
                  row('ג"ח', 'גמילות חסדים', status='agent_approved'),
                  row('ד"ה', 'דיבור המתחיל', status='needs_review')]
        first = make_review_page.ledger_candidates(ledger, BASE)[:1]
        self.assertEqual(first[0]['key'], 'ב"ה')
        with tempfile.TemporaryDirectory() as d:
            export = Path(d) / 'export.csv'
            merge.write_ledger([row('ב"ה', 'בית הלל')], export)
            updated = merge.import_exports(ledger, [export])
        second = make_review_page.ledger_candidates(updated, BASE)[:1]
        self.assertEqual(second[0]['key'], 'ג"ח')
        self.assertNotEqual(first[0]['id'], second[0]['id'])

    def test_ledger_cli_batches_and_separates_browser_progress(self):
        with tempfile.TemporaryDirectory() as d:
            ledger, baseline, out = [Path(d) / name for name in ('ledger.csv', 'baseline.json', 'review.html')]
            proposal = row('ב"ה', 'בית הלל', status='agent_approved')
            proposal['notes'] = '</script><!-- בדיקת שימור נתונים'
            merge.write_ledger([proposal,
                                row('ג"ח', 'גמילות חסדים', status='needs_review')], ledger)
            baseline.write_text(json.dumps(BASE), encoding='utf-8')
            cmd = [sys.executable, make_review_page.__file__, '--ledger', str(ledger), '--baseline', str(baseline),
                   '--limit', '1', '--out', str(out)]
            subprocess.run(cmd, check=True, capture_output=True)
            first = out.read_text()
            subprocess.run(cmd + ['--offset', '1'], check=True, capture_output=True)
            second = out.read_text()
        def data(html):
            return json.loads(html.split('const DATA = ', 1)[1].split(';\nconst SRC', 1)[0])
        self.assertEqual(len(data(first)), 1)
        self.assertIn('</script><!--', data(first)[0]['evidence'][0])
        self.assertNotIn('</script><!--', first)
        self.assertEqual(len(data(second)), 1)
        self.assertNotEqual(data(first)[0]['id'], data(second)[0]['id'])
        self.assertNotEqual(first.split('const LS = ', 1)[1].split(';', 1)[0],
                            second.split('const LS = ', 1)[1].split(';', 1)[0])


if __name__ == '__main__':
    unittest.main()
