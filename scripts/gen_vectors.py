#!/usr/bin/env python3
"""生成 PDF417 参考向量，供 MoonBit 侧一致性测试使用。

向量由独立参考实现 pdf417gen 0.8.1 (MIT) 产出：它在 Python 里完成压缩、
纠错与布局，本项目再把同一份输入的**码字序列**和**模块网格摘要**与自己
的实现逐条比对。

产出两个文件（都由本脚本重新生成，别手工改）：

  tests/vectors/pdf417_vectors.json   人可读的向量，含来源与生成方式
  src/pdf417/pdf417_vectors_test.mbt  内嵌向量的 MoonBit 测试

摘要函数 `digest` 与本项目 `BitMatrix::digest` 完全一致：
按行优先顺序扫描模块，h = (h * 131 + bit) mod 1000000007。

用法：python scripts/gen_vectors.py
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

from pdf417gen import encode  # noqa: E402
from pdf417gen.encoding import encode_high  # noqa: E402

MOD = 1000000007
START_WIDTH = 17
STOP_WIDTH = 18


def modules(codes):
    """把 pdf417gen 的码字行展开成 0/1 模块网格。"""
    grid = []
    for row in codes:
        bits = []
        for i, value in enumerate(row):
            width = STOP_WIDTH if i == len(row) - 1 else START_WIDTH
            bits.extend(int(b) for b in format(value, "0{}b".format(width)))
        grid.append(bits)
    return grid


def digest(grid):
    h = 0
    for row in grid:
        for b in row:
            h = (h * 131 + b) % MOD
    return h


def build_case(name, data, columns, ec_level):
    # `encode_high` is the compaction + error correction layer: length
    # descriptor, data, padding, then error correction. This is what the
    # MoonBit side exposes as `Symbol::codewords`.
    high = [int(v) for v in encode_high(data, columns, ec_level)]
    # `encode` adds the row layout on top; we only need its module grid.
    codes = list(encode(data, columns=columns, security_level=ec_level))
    grid = modules(codes)
    width = len(grid[0])
    height = len(grid)
    assert all(len(r) == width for r in grid), "ragged grid"
    assert width == 17 * columns + 69, f"width {width} != {17 * columns + 69}"
    assert height >= 3
    assert height * columns == len(high), "row count does not match codeword count"
    return {
        "name": name,
        "data_hex": data.hex(),
        "columns": columns,
        "ec_level": ec_level,
        "rows": height,
        "width": width,
        "codewords": high,
        "digest": digest(grid),
    }


def payloads():
    """一组覆盖面明确的语料：三种压缩模式、边界长度、多字节字符。"""
    out = []
    out.append(("empty", b""))
    out.append(("a", b"A"))
    out.append(("ab", b"AB"))
    out.append(("hello", b"hello"))
    out.append(("hello-upper", b"HELLO"))
    out.append(("hello-lower", b"hello world"))
    out.append(("mixed-case", b"Hello World"))
    out.append(("text-punct", b"a,b;c:d!e?f(g)h[i]j{k}l@m#n%o^p&q*r+s-t.u/v"))
    out.append(("digits-1", b"7"))
    out.append(("digits-2", b"42"))
    out.append(("digits-11", b"12345678901"))
    out.append(("digits-12", b"123456789012"))
    out.append(("digits-13", b"1234567890123"))
    out.append(("digits-20", b"12345678901234567890"))
    out.append(("digits-44", b"1" * 44))
    out.append(("digits-45", b"2" * 45))
    out.append(("digits-88", b"3" * 88))
    out.append(("text-then-digits", b"order 100000000000 and more"))
    out.append(("digits-then-text", b"10000000000000000 items"))
    out.append(("short-digit-run", b"ab12cd"))
    out.append(("long-digit-run", b"ab12345678901234567890cd"))
    out.append(("bytes-1", bytes([0])))
    out.append(("bytes-nul", bytes([0, 0, 0, 0, 0, 0])))
    out.append(("bytes-255", bytes([255] * 6)))
    out.append(("bytes-1to6", bytes([1, 2, 3, 4, 5, 6])))
    out.append(("bytes-1to7", bytes([1, 2, 3, 4, 5, 6, 7])))
    out.append(("bytes-1to12", bytes(range(1, 13))))
    out.append(("bytes-escape", b"a\x1bb\x00c\x7fd"))
    out.append(("bytes-all0-63", bytes(range(64))))
    out.append(("bytes-all64-127", bytes(range(64, 128))))
    out.append(("bytes-128-191", bytes(range(128, 192))))
    out.append(("utf8-cn", "你好，世界".encode("utf-8")))
    out.append(("utf8-cn-long", ("条形码" * 12).encode("utf-8")))
    out.append(("utf8-emoji", "PDF417 🐉 条形码".encode("utf-8")))
    out.append(("utf8-accented", "café naïve ØÀ".encode("utf-8")))
    out.append(("latin1-highbytes", "café".encode("latin-1")))
    out.append(("json-ish", b'{"a":1,"b":[2,3],"c":"x"}'))
    out.append(("url", b"https://example.com/path?q=1&r=2#frag"))
    out.append(("base64-ish", b"SGVsbG8sIFdvcmxkIQ=="))
    out.append(("license-plate", b"GD-12345"))
    out.append(("vcard-ish", b"BEGIN:VCARD\r\nFN:Moon\r\nEND:VCARD"))
    out.append(("newlines", b"line1\nline2\r\nline3"))
    out.append(("tabs", b"col1\tcol2\tcol3"))
    for n in (60, 120, 240, 480):
        out.append((f"lorem-{n}", (b"the quick brown fox jumps over the lazy dog " * 20)[:n]))
    for n in (60, 120):
        out.append((f"digits-long-{n}", (b"9876543210" * 20)[:n]))
    for n in (30, 90):
        out.append((f"bytes-seq-{n}", bytes((i * 7) % 256 for i in range(n))))
    return out


ALL_GEOMETRY = [
    (6, 2),
    (6, 0),
    (6, 8),
    (3, 3),
    (1, 5),
    (2, 2),
    (4, 4),
    (9, 1),
    (12, 2),
    (18, 6),
    (30, 2),
]

# Payloads that get swept across every geometry above: one per compaction
# mode plus the structural edge cases.
SWEEP = {"empty", "hello", "text-punct", "digits-20", "bytes-1to12", "utf8-cn"}

# Everything else runs on two geometries: the common default and one that is
# far from it, so a bug that depends on column count still shows up.
PAIR = [(6, 2), (9, 4)]

# Big payloads stay on a single geometry; they exist to exercise multi-row
# layouts and the row-indicator formula at both ends of the row range.
BIG = {"lorem-480", "digits-long-120", "bytes-seq-90"}


def build_all():
    cases = []
    for name, data in payloads():
        if name in SWEEP:
            geometry = ALL_GEOMETRY
        elif name in BIG:
            geometry = [(9, 4)]
        else:
            geometry = PAIR
        for columns, ec_level in geometry:
            try:
                case = build_case(
                    f"{name}-c{columns}-e{ec_level}", data, columns, ec_level
                )
            except ValueError:
                # Geometry the standard forbids (fewer than 3 rows, more than
                # 90, or more codewords than fit). The same boundaries are
                # asserted from the MoonBit side in the hand-written tests.
                continue
            cases.append(case)
    return cases


def emit_json(cases, skipped_note):
    return {
        "generated_by": "scripts/gen_vectors.py",
        "reference_implementation": "pdf417gen 0.8.1 (MIT) — see tests/VENDORED.md",
        "digest": "row-major scan, h = (h * 131 + module_bit) mod 1000000007",
        "codewords": "flattened low-level symbol characters, start/stop included",
        "case_count": len(cases),
        "note": skipped_note,
        "cases": cases,
    }


def emit_mbt(cases):
    lines = []
    w = lines.append
    w("// Generated by scripts/gen_vectors.py — DO NOT EDIT BY HAND.")
    w("//")
    w("// Conformance vectors produced by an independent implementation")
    w("// (pdf417gen 0.8.1, MIT). Each case pins the high-level codeword stream")
    w("// (length descriptor, data, padding, error correction) and a digest of the")
    w("// module grid, so a regression in compaction, error correction or row")
    w("// layout shows up here.")
    w("//")
    w("// Regenerate: python scripts/gen_vectors.py")
    w("// Source data: tests/vectors/pdf417_vectors.json")
    w("")
    for case in cases:
        w(f'///|')
        w(f'test "conformance/{case["name"]}" {{')
        w(f'  let data = try! @pdf417.bytes_from_hex("{case["data_hex"]}")')
        w(
            "  let options = @pdf417.EncodeOptions::new("
            f"{case['columns']}, {case['ec_level']})"
        )
        w(f"  let symbol = try! @pdf417.encode_bytes(data, options)")
        w(f"  assert_eq(symbol.rows(), {case['rows']})")
        w(f"  let expected : Array[Int] = [")
        cws = case["codewords"]
        for i in range(0, len(cws), 16):
            w("    " + ", ".join(str(v) for v in cws[i:i + 16]) + ",")
        w(f"  ]")
        w(f"  assert_eq(symbol.codewords(), expected)")
        w(f"  assert_eq(symbol.matrix().digest(), {case['digest']}L)")
        w(f"}}")
        w("")
    return "\n".join(lines)


def main():
    cases = build_all()
    skipped_note = (
        "Some payload/geometry combinations have no vector: the reference "
        "implementation rejects them because the symbol would fall outside the "
        "3..90 row range or exceed 928 codewords. Those boundaries are asserted "
        "from the MoonBit side in encode_test.mbt instead."
    )

    os.makedirs(os.path.join(ROOT, "tests", "vectors"), exist_ok=True)
    json_path = os.path.join(ROOT, "tests", "vectors", "pdf417_vectors.json")
    with open(json_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(emit_json(cases, skipped_note), f, ensure_ascii=False, indent=1)
        f.write("\n")

    mbt_path = os.path.join(ROOT, "src", "pdf417", "pdf417_vectors_test.mbt")
    with open(mbt_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(emit_mbt(cases))

    print(f"{len(cases)} vectors")
    print("wrote", json_path, os.path.getsize(json_path), "bytes")
    print("wrote", mbt_path, os.path.getsize(mbt_path), "bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
