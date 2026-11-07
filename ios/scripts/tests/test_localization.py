import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'check_localization.py'
spec = importlib.util.spec_from_file_location('localization', SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class LocalizationValidationTests(unittest.TestCase):
    def test_shipped_resources(self):
        self.assertEqual(checker.inspect(), [])

    def test_missing_argument_and_locale_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            resources = Path(temporary)
            for path in checker.RESOURCES.rglob('*'):
                if path.is_file() and (path.suffix in {'.xcstrings', '.txt', '.plist'} or path.name == 'EmojiNames.json'):
                    target = resources / path.relative_to(checker.RESOURCES)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(path, target)
            path = resources / 'Localizable.xcstrings'
            catalog = json.loads(path.read_text())
            catalog['strings']['屏蔽 @%@？']['localizations']['en']['stringUnit']['value'] = 'Block this user?'
            catalog['strings']['屏蔽此帖']['localizations'].pop('zh-Hant')
            path.write_text(json.dumps(catalog))
            errors = checker.inspect(resources)
            self.assertTrue(any('mismatched format' in e for e in errors))
            self.assertTrue(any('incomplete locales' in e for e in errors))

    def test_reordered_typed_arguments_are_valid(self):
        self.assertEqual(checker.arguments('%@ %lld'), checker.arguments('%2$lld %1$@'))
        self.assertNotEqual(checker.arguments('%@ %lld'), checker.arguments('%1$lld %2$@'))
        self.assertEqual(checker.arguments('25%%'), {})

    def test_incomplete_russian_plurals_and_missing_japanese_policy_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            resources = Path(temporary) / 'Resources'
            shutil.copytree(checker.RESOURCES, resources,
                            ignore=shutil.ignore_patterns('NotoEmoji*', 'Assets.xcassets'))
            path = resources / 'Localizable.xcstrings'
            catalog = json.loads(path.read_text())
            catalog['strings']['%lld 条新消息']['localizations']['ru']['variations']['plural'].pop('few')
            path.write_text(json.dumps(catalog))
            (resources / 'ja.lproj/privacy.txt').unlink()
            errors = checker.inspect(resources)
            self.assertTrue(any('ru: incomplete plural forms' in error for error in errors))
            self.assertIn('privacy/ja: missing legal translation', errors)
