#!/usr/bin/env python3
"""用工业级解码器验证本项目的输出。

`moon test` 证明的是"本实现与参考实现一致"，这个脚本回答的是另一个问题：
**真实扫描器能不能读出这些符号**。它把 MoonBit 生成的 PBM 位图交给
zxing-cpp（Google ZXing 的 C++ 实现，被大量生产系统使用）解码，再比回原始
载荷。

依赖（仅本脚本需要，不进入仓库依赖）：
    pip install zxing-cpp pillow numpy

用法：
    python scripts/verify_zxing.py            # 跑内置语料
    python scripts/verify_zxing.py --limit 20 # 只跑前 20 条
"""

import argparse
import io
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MOON = os.environ.get("MOON", "moon")


def moon(args, target="js"):
    cmd = [MOON, "run", "--target", target, "cmd/main", "--"] + args
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=600)
    return p.returncode, p.stdout, p.stderr


def parse_pbm(text):
    """P1 (ASCII) PBM -> PIL image, 1 = black."""
    lines = [l for l in text.splitlines() if l.strip() and not l.startswith("#")]
    if not lines or lines[0].strip() != "P1":
        raise ValueError("expected a P1 PBM header, got: %r" % lines[:1])
    w, h = (int(v) for v in lines[1].split()[:2])
    bits = " ".join(lines[2:]).split()
    if len(bits) != w * h:
        raise ValueError("PBM has %d samples, header says %d" % (len(bits), w * h))
    arr = np.array([0 if b == "1" else 255 for b in bits], dtype=np.uint8).reshape(h, w)
    return Image.fromarray(arr, mode="L")


def corpus():
    """Payloads whose requested geometry is legal (3..90 rows)."""
    return [
        ("ascii-short", b"HELLO", 3, 2),
        ("ascii-mixed", b"Hello World, PDF417!", 6, 2),
        ("digits-20", b"12345678901234567890", 6, 2),
        ("digits-44", b"7" * 44, 6, 4),
        ("url", b"https://moonbitlang.com/docs", 6, 2),
        ("json", b'{"a":1,"b":[2,3],"c":"x"}', 6, 3),
        ("vcard", b"BEGIN:VCARD\r\nFN:Moon\r\nEND:VCARD", 4, 2),
        ("cjk", "你好，世界".encode("utf-8"), 6, 2),
        ("cjk-long", ("条形码" * 8).encode("utf-8"), 6, 3),
        ("emoji", "PDF417 🐉 ok".encode("utf-8"), 6, 2),
        ("bytes-6", bytes(range(0x80, 0x86)), 6, 2),
        ("bytes-7", bytes(range(0x80, 0x87)), 6, 2),
        ("bytes-11", bytes(range(0x80, 0x8B)), 6, 2),
        ("bytes-17", bytes(range(0x80, 0x91)), 6, 2),
        ("bytes-24", bytes(range(0x80, 0x98)), 6, 3),
        # Six zero bytes exercise the "value 0 -> five zero codewords" path.
        ("all-zero-bytes", bytes(6), 6, 2),
        ("text-and-digits", b"Order 100000000000 shipped", 6, 2),
        ("columns-1", b"AB", 1, 3),
        ("columns-18", b"x" * 200, 18, 4),
        ("columns-30", b"y" * 300, 30, 2),
        ("level-0", b"no redundancy", 3, 0),
        ("level-8", b"heavy redundancy", 6, 8),
        ("long-lorem", b"the quick brown fox " * 8, 12, 3),
    ]


def rejections():
    """Requests the standard forbids. Each must be refused, not silently built.

    Everything here is a real constraint of ISO/IEC 15438, not an implementation
    limit: a symbol has 3..90 rows and at most 928 codewords.
    """
    return [
        # Too little data for the row budget: 2 rows where 3 are required.
        ("too-few-rows", b"HELLO", 6, 2),
        ("too-few-rows-columns", b"y" * 60, 30, 2),
        # 0 columns / 31 columns are outside 1..30.
        ("zero-columns", b"HELLO", 0, 2),
        ("too-many-columns", b"HELLO", 31, 2),
        # Error correction level 9 does not exist.
        ("ec-level-9", b"HELLO", 6, 9),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--verbose", action="store_true")
    opts = ap.parse_args()

    try:
        import zxingcpp
    except ImportError:
        print("zxing-cpp is not installed; run: pip install zxing-cpp pillow numpy")
        return 2

    cases = corpus()
    if opts.limit:
        cases = cases[: opts.limit]

    failures = []
    print(f"{'case':<18}{'bytes':>6}  {'cols':>4} {'ec':>3}  result")
    print("-" * 60)
    for name, payload, columns, ec in cases:
        code, out, err = moon([
            "encode", "hex:" + payload.hex(),
            "--columns", str(columns), "--ec-level", str(ec),
            "--format", "pbm", "--scale", "3", "--row-height", "3",
            "--quiet-zone", "4",
        ])
        if code != 0:
            failures.append((name, "encode failed: " + (err or out).strip()[:80]))
            print(f"{name:<18}{len(payload):>6}  {columns:>4} {ec:>3}  ENCODE-FAILED")
            continue
        try:
            img = parse_pbm(out)
        except ValueError as e:
            failures.append((name, "pbm parse: %s" % e))
            print(f"{name:<18}{len(payload):>6}  {columns:>4} {ec:>3}  BAD-PBM")
            continue

        results = zxingcpp.read_barcodes(np.array(img))
        if not results:
            failures.append((name, "no barcode read"))
            print(f"{name:<18}{len(payload):>6}  {columns:>4} {ec:>3}  NO-READ")
            continue
        got = results[0].bytes
        ok = got == payload
        if not ok:
            failures.append((name, "payload mismatch: %r" % got[:40]))
        print(
            f"{name:<18}{len(payload):>6}  {columns:>4} {ec:>3}  "
            f"{'OK' if ok else 'MISMATCH'}  {results[0].format}"
        )
        if opts.verbose and not ok:
            print("   expected:", payload[:80])
            print("   got     :", got[:80])

    print()
    print(f"{len(cases) - len(failures)}/{len(cases)} symbols decoded by zxing-cpp")
    for name, why in failures:
        print(f"  FAIL {name}: {why}")

    # Requests the standard forbids must be refused.
    print()
    print("rejected requests (must not build a symbol):")
    bad = []
    for name, payload, columns, ec in rejections():
        code, out, err = moon([
            "encode", "hex:" + payload.hex(),
            "--columns", str(columns), "--ec-level", str(ec), "--format", "pbm",
        ])
        refused = code != 0
        if not refused:
            bad.append(name)
        detail = ""
        if refused:
            for stream in (out, err):
                for line in (stream or "").splitlines():
                    if line.strip().startswith("pdf417:"):
                        detail = line.strip()[:70]
                        break
                if detail:
                    break
        print(f"  {name:<24}{'refused' if refused else 'BUILT'}  {detail}")
    if bad:
        print(f"  {len(bad)} request(s) should have been refused: {bad}")
    return 1 if (failures or bad) else 0


if __name__ == "__main__":
    sys.exit(main())
