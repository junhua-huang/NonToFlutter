from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


class WindowsSigningSetupChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        wrapper = (Path(__file__).parents[1] / 'setup_signing.ps1').read_text()
        cls.source = re.search(r"\$NontoPythonSetup = @'\n(.*?)\n'@", wrapper, re.S).group(1)
        key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        cls.legacy = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption())

    def run_helper(self, path, repair='keep'):
        result = subprocess.run([sys.executable, '-c', self.source, str(path), '-', repair], capture_output=True, text=True)
        self.assertNotIn('PRIVATE KEY', result.stdout + result.stderr)
        return result

    def test_new_key_is_compatible_and_repeated_execution_keeps_same_key(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'NonToDistribution.key'
            self.assertEqual(self.run_helper(path).returncode, 0)
            contents = path.read_bytes()
            self.assertEqual(serialization.load_pem_private_key(contents, None).key_size, 2048)
            self.assertEqual(self.run_helper(path, 'repair').returncode, 0)
            self.assertEqual(path.read_bytes(), contents)

    def test_unsupported_key_is_preserved_without_explicit_repair_then_backed_up_once(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'NonToDistribution.key'; path.write_bytes(self.legacy)
            self.assertNotEqual(self.run_helper(path).returncode, 0)
            self.assertEqual(path.read_bytes(), self.legacy)
            self.assertEqual(self.run_helper(path, 'repair').returncode, 0)
            self.assertEqual(path.with_name(path.name + '.rsa3072.backup').read_bytes(), self.legacy)
            contents = path.read_bytes()
            self.assertEqual(serialization.load_pem_private_key(contents, None).key_size, 2048)
            self.assertEqual(self.run_helper(path, 'repair').returncode, 0)
            self.assertEqual(path.read_bytes(), contents)

    def test_existing_backup_or_invalid_key_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'NonToDistribution.key'; path.write_bytes(self.legacy)
            backup = path.with_name(path.name + '.rsa3072.backup'); backup.write_bytes(b'previous backup')
            self.assertNotEqual(self.run_helper(path, 'repair').returncode, 0)
            self.assertEqual(path.read_bytes(), self.legacy)
            self.assertEqual(backup.read_bytes(), b'previous backup')
            path.write_bytes(b'invalid key')
            self.assertNotEqual(self.run_helper(path, 'repair').returncode, 0)
            self.assertEqual(path.read_bytes(), b'invalid key')
