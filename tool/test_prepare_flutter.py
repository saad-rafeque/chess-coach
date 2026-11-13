from pathlib import Path
import tempfile
import unittest

from prepare_flutter import DETERMINISTIC, ORIGINAL, prepare


class PrepareFlutterTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.source = self.root / "packages/flutter_tools/lib/src/asset.dart"
        self.source.parent.mkdir(parents=True)
        self.stamp = self.root / "bin/cache/flutter_tools.stamp"
        self.stamp.parent.mkdir(parents=True)
        self.stamp.write_text("compiled-original")

    def test_patch_invalidates_compiled_tool_and_is_idempotent(self):
        self.source.write_text("before\n" + ORIGINAL + "\nafter")
        self.assertTrue(prepare(self.root))
        self.assertEqual(self.source.read_text(), "before\n" + DETERMINISTIC + "\nafter")
        self.assertFalse(self.stamp.exists())
        self.stamp.write_text("compiled-patched")
        self.assertFalse(prepare(self.root))
        self.assertEqual(self.stamp.read_text(), "compiled-patched")

    def test_unknown_or_ambiguous_sdk_is_not_modified(self):
        for content in ["changed upstream", ORIGINAL * 2, DETERMINISTIC + ORIGINAL]:
            with self.subTest(content=content):
                self.source.write_text(content)
                with self.assertRaisesRegex(ValueError, "Unsupported Flutter"):
                    prepare(self.root)
                self.assertEqual(self.source.read_text(), content)
                self.assertEqual(self.stamp.read_text(), "compiled-original")


if __name__ == "__main__":
    unittest.main()
