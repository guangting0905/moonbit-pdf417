#!/usr/bin/env python3
"""重新生成文档里展示的示例条码，并验证它们真的能被扫出来。

`docs/assets/` 下的图不是截图，而是本项目的输出：脚本调用 CLI 生成 SVG 与
PBM，把 PBM 交给 Pillow 转成 PNG，再用 zxing-cpp 解码回原字符串。任何一步
对不上就报错退出——README 里贴的图必须是能扫的。

用法：
    python scripts/gen_samples.py
"""

import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MOON = os.environ.get("MOON", "moon")
ASSETS = os.path.join(ROOT, "docs", "assets")

SAMPLES = [
    (
        "sample",
        "https://github.com/ouoankang/moonbit-pdf417",
        6,
        4,
        3,
        "README headline sample",
    ),
    (
        "sample-dense",
        # 44 digits: one full numeric compaction group.
        "86753090123456789012345678901234567890123456",
        8,
        3,
        3,
        "numeric compaction sample",
    ),
    (
        "sample-bytes",
        None,  # filled in below as raw bytes
        6,
        5,
        3,
        "byte compaction sample",
    ),
]


def moon(args, timeout=300):
    p = subprocess.run([MOON, "run", "--target", "js", "cmd/main", "--"] + args,
                       cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    if p.returncode != 0:
        raise SystemExit("moon failed: %s" % ((p.stdout or "") + (p.stderr or "")))
    return p.stdout


def parse_pbm(text):
    lines = [l for l in text.splitlines() if l.strip() and not l.startswith("#")]
    assert lines[0].strip() == "P1", "expected P1 PBM"
    w, h = (int(v) for v in lines[1].split()[:2])
    bits = " ".join(lines[2:]).split()
    assert len(bits) == w * h, "PBM sample count mismatch"
    arr = np.array([0 if b == "1" else 255 for b in bits], dtype=np.uint8).reshape(h, w)
    return Image.fromarray(arr, mode="L")


def main():
    try:
        import zxingcpp
    except ImportError:
        print("zxing-cpp is not installed; run: pip install zxing-cpp pillow numpy")
        return 2

    os.makedirs(ASSETS, exist_ok=True)
    failures = []
    for name, text, columns, ec, scale, note in SAMPLES:
        if text is None:
            raw = bytes(range(0x30, 0x36)) + bytes(range(0xC0, 0xC6))
            payload_arg = "hex:" + raw.hex()
            expected = raw
        else:
            raw = text.encode("utf-8")
            payload_arg = "hex:" + raw.hex()
            expected = raw

        common = ["--columns", str(columns), "--ec-level", str(ec),
                  "--scale", str(scale), "--row-height", "3", "--quiet-zone", "4"]

        svg = moon(["encode", payload_arg] + common + ["--format", "svg"])
        svg_path = os.path.join(ASSETS, name + ".svg")
        with open(svg_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(svg)

        pbm = moon(["encode", payload_arg] + common + ["--format", "pbm"])
        img = parse_pbm(pbm)
        # 2x nearest-neighbour so the preview is not a postage stamp.
        img = img.resize((img.width * 2, img.height * 2), Image.NEAREST)
        png_path = os.path.join(ASSETS, name + ".png")
        img.save(png_path)

        results = zxingcpp.read_barcodes(np.array(img))
        ok = bool(results) and results[0].bytes == expected
        if not ok:
            failures.append(name)
        print(
            f"{name:<14} {len(raw):>4} bytes  {img.width}x{img.height}px  "
            f"svg {len(svg):>6}B  png {os.path.getsize(png_path):>6}B  "
            f"{'decoded by zxing-cpp' if ok else 'NOT DECODABLE'}   ({note})"
        )

    print()
    if failures:
        print("these samples did not decode:", failures)
        return 1
    print(f"all {len(SAMPLES)} samples written to docs/assets/ and verified decodable")
    return 0


if __name__ == "__main__":
    sys.exit(main())
