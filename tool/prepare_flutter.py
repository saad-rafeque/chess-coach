"""Make Flutter's resolution-variant manifest order deterministic before builds.

Flutter 3.47.7 enumerates image variant directories in filesystem order. Its
manifest sorts asset keys, but not each asset's variants, so identical sources
can produce different AssetManifest.bin bytes. Sort the discovered variant
files while retaining Flutter's base-image-first behavior. Fail closed if an
SDK upgrade changes this code; never relax the APK comparison.
"""

import os
from pathlib import Path
import shutil
import sys


ORIGINAL = """          .expand((Directory dir) => dir.listSync())
          .whereType<File>()
          .toList();"""
DETERMINISTIC = """          .expand((Directory dir) => dir.listSync())
          .whereType<File>()
          .toList()
            ..sort((File left, File right) => left.path.compareTo(right.path));"""


def prepare(root):
    root = Path(root)
    source = root / "packages/flutter_tools/lib/src/asset.dart"
    content = source.read_text(encoding="utf-8")
    if content.count(DETERMINISTIC) == 1 and ORIGINAL not in content:
        return False
    if content.count(ORIGINAL) != 1 or DETERMINISTIC in content:
        raise ValueError("Unsupported Flutter asset code; review the deterministic variant patch")
    source.write_text(content.replace(ORIGINAL, DETERMINISTIC), encoding="utf-8")
    # Flutter keys its compiled tool by Git revision, not local source edits.
    # Invalidate the stamp so both Unix and Windows bootstrap the changed tool.
    (root / "bin/cache/flutter_tools.stamp").unlink(missing_ok=True)
    return True


if __name__ == "__main__":
    try:
        root = os.environ.get("FLUTTER_ROOT")
        if not root:
            executable = shutil.which("flutter")
            if not executable:
                raise ValueError("Flutter is not on PATH and FLUTTER_ROOT is unset")
            root = Path(executable).resolve().parent.parent
        changed = prepare(root)
        print("Flutter asset variant ordering: " + ("patched" if changed else "already deterministic"))
    except (OSError, ValueError) as error:
        sys.exit(str(error))
