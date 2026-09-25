#!/usr/bin/env python3
"""构建浏览器用的单文件 JS，并放到 web/ 下。

`moon build --target js` 的产物是普通脚本（不是 ES module），
末尾会自己调用 `js_publish` 把 API 挂到 `globalThis.pdf417` 上，
所以页面只需要一个 `<script src>`，不需要打包器。

用法：
    python scripts/build_web.py
"""

import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MOON = os.environ.get("MOON", "moon")

ARTIFACT = os.path.join(
    ROOT, "_build", "js", "release", "build", "cmd", "web", "web.js"
)
TARGET = os.path.join(ROOT, "web", "pdf417.js")


def main():
    p = subprocess.run([MOON, "build", "--target", "js", "--release"],
                       cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=900)
    if p.returncode != 0:
        print("moon build failed:\n" + (p.stdout or "") + (p.stderr or ""))
        return 1
    if not os.path.exists(ARTIFACT):
        print("expected build artifact not found:", ARTIFACT)
        return 1
    os.makedirs(os.path.dirname(TARGET), exist_ok=True)
    shutil.copyfile(ARTIFACT, TARGET)
    print(f"wrote {TARGET} ({os.path.getsize(TARGET)} bytes)")
    print("serve the directory and open web/index.html:")
    print("    python -m http.server 8080 --directory web")
    return 0


if __name__ == "__main__":
    sys.exit(main())
