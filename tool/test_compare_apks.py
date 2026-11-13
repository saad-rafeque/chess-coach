import pathlib
import tempfile
import unittest
import warnings
import zipfile

from compare_apks import compare


class ApkComparisonTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)

    def archive(self, name, entries, year=2026):
        path = pathlib.Path(self.directory.name) / name
        with zipfile.ZipFile(path, "w") as archive:
            for entry, content in entries:
                info = zipfile.ZipInfo(entry, (year, 1, 1, 0, 0, 0))
                archive.writestr(info, content)
        return path

    def test_equal_payload_ignores_timestamps_and_order(self):
        first = self.archive("a.apk", [("a", b"123"), ("b", b"456")])
        second = self.archive("b.apk", [("b", b"456"), ("a", b"123")], 2025)
        self.assertEqual(compare(first, second), 2)

    def test_changed_missing_and_extra_entries_are_rejected(self):
        first = self.archive("a.apk", [("a", b"123"), ("b", b"456")])
        for entries in [
            [("a", b"321"), ("b", b"456")],
            [("a", b"123")],
            [("a", b"123"), ("b", b"456"), ("c", b"789")],
        ]:
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                compare(first, self.archive("b.apk", entries))

    def test_duplicate_names_are_rejected(self):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            duplicate = self.archive("a.apk", [("a", b"1"), ("a", b"2")])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            compare(duplicate, duplicate)


if __name__ == "__main__":
    unittest.main()
