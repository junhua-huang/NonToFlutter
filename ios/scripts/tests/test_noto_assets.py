"""Check the entire offline resource archive, without image libraries or network."""
import hashlib
import io
import json
from pathlib import Path
import struct
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2] / "Nonto/Resources"


class NotoAssetsTests(unittest.TestCase):
    def test_catalog_animations_and_previews_are_complete(self):
        parts = sorted(ROOT.glob("NotoEmoji.zip.[0-9][0-9][0-9]"))
        self.assertTrue(parts)
        archive = zipfile.ZipFile(io.BytesIO(b"".join(p.read_bytes() for p in parts)))
        self.addCleanup(archive.close)
        catalog = json.loads(archive.read("catalog.json"))
        self.assertEqual(catalog["license"], "CC-BY-4.0")
        self.assertEqual(len(catalog["items"]), 881)
        identifiers = set()
        for item in catalog["items"]:
            with self.subTest(emoji=item["id"]):
                self.assertNotIn(item["id"], identifiers)
                identifiers.add(item["id"])
                self.assertEqual(item["emoji"], "".join(chr(int(x, 16)) for x in item["id"].split("_")))
                raw = archive.read(item["id"] + ".json")
                self.assertEqual(hashlib.sha256(raw).hexdigest(), item["sha256"])
                self.assertEqual(item["sha256"], item["sourceSHA256"])
                animation = json.loads(raw)
                self.assertGreater(animation["op"], animation["ip"])
                self.assertGreater(animation["fr"], 0)
                self.assertFalse(any(a.get("p") and not a.get("e") for a in animation.get("assets", [])))
                png = archive.read(item["id"] + ".png")
                self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
                self.assertEqual(struct.unpack(">II", png[16:24]), (96, 96))
        for name in ["CC-BY-4.0.txt", "UNICODE-LICENSE.txt", "Lottie-LICENSE.txt", "NOTICE.txt"]:
            self.assertGreater(len(archive.read(name)), 100)


if __name__ == "__main__":
    unittest.main()
