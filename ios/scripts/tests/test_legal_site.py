import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('export_legal_site', SCRIPTS / 'export_legal_site.py')
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)

class LegalWebsiteChecks(unittest.TestCase):
    def test_export_contains_all_documents_and_preserves_unverified_state(self):
        pages, blockers = exporter.pages()
        self.assertTrue(blockers)
        self.assertEqual(set(pages), {'index.html', 'privacy.html', 'terms.html', 'community.html', 'manifest.json'})
        for name in ('privacy.html', 'terms.html', 'community.html'):
            self.assertNotIn('开发测试', pages[name])
            self.assertNotIn('尚未完成核验', pages[name])
            self.assertNotIn('{{', pages[name])
            self.assertIn('Content-Security-Policy', pages[name])
            self.assertNotIn('<script', pages[name])
        self.assertFalse(json.loads(pages['manifest.json'])['releaseReady'])
        self.assertIn('具体存储地点', pages['privacy.html'])

    def test_operator_text_is_escaped_and_community_changes_revision(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for path in exporter.check_compliance.RESOURCES.iterdir():
                if path.is_file(): shutil.copy(path, root / path.name)
            config_path = root / 'Compliance.json'
            config = json.loads(config_path.read_text())
            config['operatorName'] = '<script>alert(1)</script>'
            config_path.write_text(json.dumps(config))
            before, _ = exporter.pages(root)
            self.assertNotIn('<script>', before['privacy.html'])
            self.assertIn('&lt;script&gt;', before['privacy.html'])
            community = root / 'community.txt'
            community.write_text(community.read_text() + '\n\n补充规则\n')
            after, _ = exporter.pages(root)
            self.assertNotEqual(json.loads(before['manifest.json'])['revision'], json.loads(after['manifest.json'])['revision'])
