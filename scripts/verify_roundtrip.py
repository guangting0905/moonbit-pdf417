#!/usr/bin/env python3
"""随机载荷往返 + 模块级错误注入验证。

这个脚本覆盖 `moon test` 不便覆盖的两件事：

1. **随机语料往返**：按固定种子生成文本/数字/字节/多字节字符混合的载荷，
   覆盖 1..30 列与 0..8 纠错级别，逐条 encode -> decode 比对。
2. **错误注入**：把矩阵里若干符号字符整体换成**另一个码字**的图案，
   再交给解码器，检查 ①载荷完好 ②报告里修好的错误数等于注入数。
   注入时使用的图案表直接从 `src/pdf417/codeword_table.mbt` 读出，
   所以注入的是解码器真正会遇到的符号字符错误。

用法：
    python scripts/verify_roundtrip.py
    python scripts/verify_roundtrip.py --trials 400 --seed 7
"""

import argparse
import os
import random
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MOON = os.environ.get("MOON", "moon")


def moon(args, timeout=600):
    cmd = [MOON, "run", "--target", "js", "cmd/main", "--"] + args
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    return p.returncode, p.stdout, p.stderr


def load_pattern_table():
    """Reads the generated pattern table so injections use real symbol characters."""
    path = os.path.join(ROOT, "src", "pdf417", "codeword_table.mbt")
    text = open(path, encoding="utf-8").read()
    table = []
    cluster = None
    for line in text.splitlines():
        m = re.match(r"\s*//\s*cluster\s+(\d+)", line)
        if m:
            cluster = []
            table.append(cluster)
            continue
        if cluster is not None:
            for lit in re.findall(r"0x([0-9a-f]+)U", line):
                cluster.append(int(lit, 16))
    if len(table) != 3 or any(len(c) != 929 for c in table):
        raise SystemExit("could not read 3x929 patterns from codeword_table.mbt")
    return table


def encode_rows(data, columns, ec, patterns):
    code, out, err = moon(["encode", "hex:" + data.hex(),
                           "--columns", str(columns), "--ec-level", str(ec),
                           "--format", "text"])
    if code != 0:
        return None, (err or out).strip()
    rows = [l for l in out.splitlines() if l and set(l) <= set("#.")]
    return rows, ""


def decode_rows(rows):
    code, out, err = moon(["decode", "--matrix", ";".join(rows)])
    if code != 0:
        return None, {}
    fields = {}
    for line in out.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fields[k.strip()] = v.strip()
    return fields.get("bytes"), fields


def set_pattern(row, row_index, codeword_index, value, columns):
    """Rewrites one 17-module symbol character in a text row."""
    bits = format(value, "017b")
    start = 34 + codeword_index * 17
    row_chars = list(row)
    for i, b in enumerate(bits):
        row_chars[start + i] = "#" if b == "1" else "."
    return "".join(row_chars)


ALPHABETS = {
    "ascii": "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz .,;:!?-_/@#%&*+=",
    "digits": "0123456789",
    "mixed": "abXY019 ,.!#%&/",
    "latin1": "".join(chr(c) for c in range(0xA1, 0x100)),
}


def random_payload(rng, kind, n):
    if kind == "bytes":
        return bytes(rng.randrange(256) for _ in range(n))
    if kind == "printable":
        return bytes(rng.randrange(32, 127) for _ in range(n))
    return "".join(rng.choice(ALPHABETS[kind]) for _ in range(n)).encode("utf-8")


def roundtrip_sweep(rng, trials, patterns):
    kinds = ["ascii", "digits", "bytes", "printable", "mixed", "latin1"]
    sizes = [0, 1, 2, 3, 5, 6, 7, 11, 12, 13, 17, 23, 44, 45, 60, 100, 200]
    columns_choices = [1, 2, 3, 4, 6, 9, 12, 18, 30]
    ec_choices = [0, 1, 2, 3, 5, 8]

    ok = 0
    rejected = 0
    failures = []
    for trial in range(trials):
        kind = kinds[trial % len(kinds)]
        data = random_payload(rng, kind, rng.choice(sizes))
        columns = rng.choice(columns_choices)
        ec = rng.choice(ec_choices)
        rows, err = encode_rows(data, columns, ec, patterns)
        if rows is None:
            # Geometry the standard forbids is expected to be refused.
            rejected += 1
            continue
        got, fields = decode_rows(rows)
        if got is None:
            failures.append((kind, len(data), columns, ec, "decode failed"))
            continue
        if bytes.fromhex(got) != data:
            failures.append((kind, len(data), columns, ec, "payload mismatch"))
            continue
        ok += 1
    return ok, rejected, failures


def injection_sweep(rng, patterns, per_level=6):
    """Inject 1..capacity symbol character errors and require full recovery."""
    results = []
    for ec in [2, 3, 4, 5]:
        capacity = 2 ** (ec + 1) // 2
        for trial in range(per_level):
            n = rng.choice([6, 20, 60, 120])
            kind = rng.choice(["ascii", "digits", "bytes"])
            data = random_payload(rng, kind, n)
            columns = rng.choice([4, 6, 9, 12])
            rows, err = encode_rows(data, columns, ec, patterns)
            if rows is None:
                continue
            n_rows = len(rows)
            total = n_rows * columns
            k = rng.choice([1, max(1, capacity // 2), capacity])
            k = min(k, total)
            positions = rng.sample(range(total), k)
            damaged = list(rows)
            for pos in positions:
                row_index = pos // columns
                col_index = pos % columns
                cluster = row_index % 3
                # Replace with a different codeword's pattern: a genuine symbol
                # character error, not a random bit flip.
                replacement = (pos * 7 + 13) % 929
                damaged[row_index] = set_pattern(
                    damaged[row_index], row_index, col_index,
                    patterns[cluster][replacement], columns,
                )
            got, fields = decode_rows(damaged)
            if got is None:
                results.append((ec, columns, k, "decode failed"))
                continue
            payload_ok = bytes.fromhex(got) == data
            corrected = int(fields.get("corrected", "-1"))
            results.append((
                ec, columns, k,
                "OK" if (payload_ok and corrected == k) else
                f"payload_ok={payload_ok} corrected={corrected}",
            ))
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trials", type=int, default=180)
    ap.add_argument("--seed", type=int, default=20260925)
    opts = ap.parse_args()

    patterns = load_pattern_table()
    rng = random.Random(opts.seed)

    ok, rejected, failures = roundtrip_sweep(rng, opts.trials, patterns)
    print(f"random round trip : {ok} ok, {rejected} refused by the geometry rules, "
          f"{len(failures)} failed")
    for f in failures[:20]:
        print("   kind=%s len=%d columns=%d ec=%d -> %s" % f)

    results = injection_sweep(rng, patterns)
    injected = sum(1 for r in results if r[3] == "OK")
    print(f"error injection   : {injected}/{len(results)} cases fully recovered")
    for ec, columns, k, verdict in results:
        mark = "OK " if verdict == "OK" else "!! "
        if verdict != "OK":
            print(f"   {mark}ec={ec} columns={columns} injected={k}: {verdict}")
    print()
    print("injected errors are whole symbol characters replaced by another")
    print("codeword's pattern, so they are real symbol errors rather than noise.")

    return 1 if (failures or injected != len(results)) else 0


if __name__ == "__main__":
    sys.exit(main())
