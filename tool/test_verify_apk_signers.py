import subprocess
import unittest
from unittest.mock import patch

from verify_apk_signers import certificates, compare, verified_certificates


def output(label="#1", digest="ab" * 32):
    return f"Signer {label} certificate SHA-256 digest: {digest}\n"


class ApkSignersTest(unittest.TestCase):
    def test_numbered_and_sdk_range_labels(self):
        self.assertEqual(certificates(output().replace("\n", "\r\n")), [("#1", "ab" * 32)])
        label = "(minSdkVersion=33, maxSdkVersion=2147483647)"
        self.assertEqual(certificates(output(label)), [(label, "ab" * 32)])

    def test_empty_malformed_source_stamp_and_duplicate_records_fail(self):
        for text in ["", output(digest="abcd"), "Source Stamp " + output(), output() * 2]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                certificates(text)

    @patch("verify_apk_signers.subprocess.run")
    def test_invalid_signature_is_rejected_even_with_certificate_text(self, run):
        run.return_value = subprocess.CompletedProcess([], 1, output() + "DOES NOT VERIFY")
        with self.assertRaisesRegex(ValueError, "Signature verification failed"):
            verified_certificates("apksigner", "bad.apk")

    @patch("verify_apk_signers.verified_certificates")
    def test_different_keys_or_sdk_ranges_fail(self, verify):
        for second in [[("#1", "cd" * 32)], [("(minSdkVersion=33)", "ab" * 32)]]:
            verify.side_effect = [[("#1", "ab" * 32)], second]
            with self.subTest(second=second), self.assertRaisesRegex(ValueError, "differ"):
                compare("apksigner", "original.apk", "rebuilt.apk")

    @patch("verify_apk_signers.subprocess.run")
    def test_equal_verified_signers_pass(self, run):
        run.return_value = subprocess.CompletedProcess([], 0, output())
        self.assertEqual(compare("apksigner", "a.apk", "b.apk"), [("#1", "ab" * 32)])
        self.assertEqual(run.call_count, 2)


if __name__ == "__main__":
    unittest.main()
