# AGENTS.md — 与 AI 助手协作的约定

本仓库的代码与文档在 AI 助手（WorkBuddy）辅助下完成。这份文件记录协作方式、
硬性约束和踩过的坑，供后续（人类或 AI）接手时少走弯路。

## 项目边界（改代码前先读）

- **这是编解码器，不是扫描器。** 解码器的输入是「逻辑模块矩阵」，不是照片。
  不要为了「支持图片」把二值化、透视变换、行列检测塞进 `src/pdf417`——
  那会破坏项目对外承诺的边界。要支持图片，应当新建可选的集成层并说明清楚。
- **渲染只出文本格式**（PBM／SVG／终端）。不要加 PNG／JPEG 编码器。
- **库本体零第三方依赖。** 只用 `moonbitlang/core`。`cmd/` 下的可执行可以多依赖
  一点 core 包，但仍不引入第三方模块。
- **不要做能力上的陈述升级。** README 里的每个百分比都要有命令行出处；
  没有实测支持的说法（「比其他实现快」之类）一律不写。这条有实际教训：
  在开源赛事评审里，过度声明会直接被驳回。

## 硬性工程约束

1. **`moon check` 必须零警告。** MoonBit 的 `unused_mut` 等警告在检查阶段会当
   错误处理。反复出现的几条：
   - 变量没有真正被改写时不要写 `mut`（`Array` 的 `push` 不需要 `mut` 绑定）；
   - `StringBuilder()` 而不是 `StringBuilder::new()`；
   - `derive(Show)` 已废弃，用 `derive(Debug)`；
   - `starts_with` 已废弃，用 `has_prefix`；
   - `unsafe_char_at` 已废弃，用 `String::to_array()` 或 `get_char(i).unwrap()`；
   - `assert_true` 的第二参数是具名参数：`assert_true(cond, msg="...")`。
2. **`moon test` 必须全绿。** 目前 202 个用例。
3. **`moon build --target all` 必须通过。** 而 `native` 需要 C 编译器，
   本机不一定有，所以用到 `process.argv` 的 `cmd/main` 要声明
   `supported_targets = "js"`；纯 MoonBit 的库不受影响。
4. **不要用无循环变量的 `for`。** `for _ = 0; ...` 不是合法语法，
   用 `_k` 之类的具名变量。
5. **`try!` 不能出现在表达式中间。** 先赋值给变量再用：
   ```moonbit
   let ec = try! symbol.ec_codeword_count()
   assert_eq(total, a + b + ec + 1)
   ```
6. **字符串插值 `\{...}` 里不能换行**，多行拼接请分多次 `write_string`。
7. **`Int` 是 32 位。** 任何可能超过 2^31 的中间量要用 `Int64`：
   字节压缩的 5 个 base-900 码字累加（`900^5 ≈ 5.9e14`）是典型陷阱。
8. **`Array<T>` 用方括号**（`Array[Int]`），不是 `Array<Int>`——写错了报的是
   语法错误而不是类型错误，很难一眼看出。

## 数学上的约定（改纠错代码前务必对齐）

解码器里两种多项式求值方向**必须分清**，用错不会崩、只会静默算错：

| 函数 | 顺序 | 用在哪 |
| --- | --- | --- |
| `poly_eval` | 降幂（`c[0] * x^(n-1) + ...`） | 伴随式：码字块按最高次在前书写 |
| `poly_eval_asc` | 升幂（`p[0] + p[1]*x + ...`） | 错误定位多项式 `σ(x)`、错误求值多项式 `Ω(x)` |

其他关键约定（改动前先读对应测试）：

- 伴随式 `S_i = c(3^i)`，`i = 1..2t`；
- 错误定位子 `X_k = 3^(n-1-p_k)`，`σ(x) = ∏(1 − X_k x)`；
- `Ω(x) = S(x)σ(x) mod x^(2t)`，**截断必须恰好 2t 项**——多留一项会在
  错误定位点处正好抵消主系数，修出来的量级是 0；
- Forney：`X · Ω(X^-1) / σ'(X^-1)` 等于**负的**错误量级，所以修复是加法。

## 生成物与脚本

| 文件 | 生成脚本 | 是否入库 |
| --- | --- | --- |
| `src/pdf417/codeword_table.mbt` | `scripts/gen_codeword_table.py` | 是 |
| `src/pdf417/text_table.mbt` | 同上 | 是 |
| `src/pdf417/ec_coefficients_test.mbt` | 同上 | 是 |
| `src/pdf417/pdf417_vectors_test.mbt` | `scripts/gen_vectors.py` | 是 |
| `tests/vectors/*.json` | 两个脚本 | 是 |
| `docs/assets/*.svg` / `*.png` | `scripts/gen_samples.py` | 是 |

**改了生成物不要手改产物**，改脚本再重跑。生成脚本自带自检（结构、唯一性、
覆盖率），跑一遍就能发现问题。

## 验证命令（提交前至少跑前两条）

```sh
moon check                                  # 零警告
moon test                                   # 202 个用例
python scripts/build_web.py                 # 重新编译浏览器产物
node scripts/check_web.mjs                  # 冒烟测试该产物（需要 Node）
python scripts/verify_roundtrip.py          # 随机往返 + 错误注入（需 Python）
python scripts/verify_zxing.py              # 工业解码器验证（需 zxing-cpp）
python scripts/gen_samples.py               # 重新生成示例图并验证可扫
```

## 浏览器产物

`web/pdf417.js` 是 `moon build --target js --release` 的产物，**故意入库**：
页面要能在静态托管（GitHub Pages、内网 nginx）上直接打开，读者不必装 MoonBit
工具链。改了 `src/` 或 `cmd/web/` 之后必须重跑 `scripts/build_web.py`，
CI 的「生成物时效」作业会重新构建并检查 diff。

`cmd/web` 与 `cmd/main` 一样声明 `supported_targets = "js"`。
跨 FFI 边界只传字符串——`js_publish` 收一个
`(String, String, String, String) -> String` 并挂到 `globalThis.pdf417`。
这个 bundle 是普通脚本（不是 ES module），页面只需一个 `<script src>`。

## 关于「完成的定义」

一个变更算完成，需要同时满足：

1. `moon check` 零警告、`moon test` 全绿；
2. 新行为有具名测试，测试名写清它防的是什么（例如
   `decode/damaging the length descriptor does not truncate the payload`）；
3. README 里提到的数字如果变了，同步更新；
4. 若改了压缩/纠错/布局算法，`python scripts/verify_roundtrip.py` 与
   `python scripts/verify_zxing.py` 必须仍然全过。
