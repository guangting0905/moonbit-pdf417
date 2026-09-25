# 随仓库版本化的第三方数据

本文件记录 `tests/` 下每一份第三方数据的来源、版本与复现方式。
目的很直接：评审或任何人拿到这个仓库，应当能在**不联网**的情况下
重现 README 里的每一个数字，并且知道这些数据的许可。

---

## 1. `tests/vectors/pdf417_vectors.json`

| 项目 | 内容 |
| --- | --- |
| 来源 | [pdf417gen](https://github.com/ihabunek/pdf417-py/) 0.8.1（PyPI `pdf417gen`），一个独立的 Python PDF417 实现 |
| 许可 | MIT 风格（"PDF417-Py License"），原文见同目录 `LICENSE.pdf417gen` |
| 抓取时间 | 2026-09-25 |
| 生成脚本 | `scripts/gen_vectors.py` |
| 用途 | 与本实现逐条比对高层码字流与模块网格摘要 |

**内容形态**：127 个用例，每个包含

- `data_hex`：输入字节；
- `columns` / `ec_level`：几何参数；
- `rows` / `width`：由几何规则决定的行数与模块宽度；
- `codewords`：高层码字流——长度描述符、数据、填充、纠错码字；
- `digest`：模块网格的摘要，按行优先扫描，
  `h = (h * 131 + module_bit) mod 1000000007`（与本项目 `BitMatrix::digest` 完全一致）。

**为什么既有码字又有摘要**：码字对得上说明压缩与纠错对了；摘要对得上说明
行指示符、簇号、起始／终止图案和模块摆放也对了。两样一起才算「整条链路一致」。

**复现**：

```sh
pip install pdf417gen
python scripts/gen_vectors.py     # 重新生成 json 与内嵌向量的 .mbt 测试
moon test                         # 跑 127 条 conformance/* 用例
```

**范围与取舍**：语料覆盖三种压缩模式、44 位数字分组边界、6／7／11／17 字节等
字节压缩边界、UTF-8 多字节字符、纯二进制（0x00、0xFF），以及 1／2／3／4／6／9／
12／18／30 列与 0～8 纠错级别。参考实现因几何非法（行数不在 3..90）而拒绝的
组合不产生向量，那些边界改由 `encode_test.mbt` 从 MoonBit 侧直接断言。

---

## 2. `tests/vectors/ec_coefficients.json`

| 项目 | 内容 |
| --- | --- |
| 来源 | 系数由本实现独立推导（`g(x) = ∏(x − 3^i) mod 929`），对照表转写自 pdf417gen 的 `ERROR_CORRECTION_FACTORS`，后者与 ISO/IEC 15438 公布的表一致 |
| 许可 | 同 `LICENSE.pdf417gen`（对照部分）；推导结果本身为本项目产出 |
| 生成脚本 | `scripts/gen_codeword_table.py` |
| 用途 | 证明「纠错系数不是抄来的」——9 个级别、共 1022 项系数逐项核对 |

**复现**：

```sh
python scripts/gen_codeword_table.py
moon test        # 跑 ec/level 0..8 coefficients match ISO/IEC 15438
```

---

## 3. `src/pdf417/codeword_table.mbt`

| 项目 | 内容 |
| --- | --- |
| 来源 | ISO/IEC 15438 的符号字符图案表（929 个码字 × 3 个簇）；整理过程对照 pdf417gen 的 `codes.py` |
| 许可 | 标准表格内容；本项目以 Apache-2.0 发布生成物与生成脚本 |
| 生成脚本 | `scripts/gen_codeword_table.py` |

**为什么不"算"出来**：标准把码字值到 17 模块图案的映射定义为**规范性数据表**，
没有公开的闭式生成规则，所以它只能是数据。为了不让数据变成不可审计的黑盒，
生成脚本对全表做结构自检（`check_pattern_table()`，`moon test` 里也会再跑一遍）：

- 每个图案恰好 17 模块、以条开始、以空结束；
- 恰好 4 条 4 空，每段宽度在 1..6；
- 簇号满足 `(b1 − b2 + b3 − b4) mod 9`；
- 同一簇内 929 个图案互不重复。

---

## 4. `src/pdf417/text_table.mbt`

| 项目 | 内容 |
| --- | --- |
| 来源 | ISO/IEC 15438 的文本压缩子模式表（Table 3/4）；整理过程对照 pdf417gen 的 `data.py` |
| 生成脚本 | `scripts/gen_codeword_table.py` |

覆盖 9（TAB）、10（LF）、13（CR）与 32..126 共 98 个字符，以及四个子模式之间的
切换码。测试里有一条不变量：`text_submode_mask` 与 `text_values` 必须互相自洽。

---

## 5. 不随仓库入库的东西

以下资源只在本地运行时使用，**不进入仓库、不进入构建**：

| 资源 | 用途 | 许可 |
| --- | --- | --- |
| [zxing-cpp](https://github.com/zxing-cpp/zxing-cpp)（PyPI `zxing-cpp`） | `scripts/verify_zxing.py` 用它解码本项目生成的位图，验证「真实解码器读得出」 | Apache-2.0 |
| [Pillow](https://python-pillow.org/)、[NumPy](https://numpy.org/) | 位图转换 | HPND / BSD-3-Clause |
