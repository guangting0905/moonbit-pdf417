# web/ —— 浏览器里的在线试用

页面把 `src/pdf417` 的编码与解码都暴露出来，全部在浏览器里跑，
不发任何网络请求。

## 怎么跑

```sh
python scripts/build_web.py
python -m http.server 8080 --directory web
# 打开 http://localhost:8080/
```

`scripts/build_web.py` 会执行 `moon build --target js --release`，
并把产物 `_build/js/release/build/cmd/web/web.js` 复制成 `web/pdf417.js`。

## 为什么这么简单

`moon build --target js` 的产物是**普通脚本**，不是 ES module：它把
`cmd/web/main.mbt` 里的 `js_publish` 编译成一段自执行代码，在末尾把 API
挂到 `globalThis.pdf417` 上。所以页面只要一个 `<script src="./pdf417.js">`，
不需要打包器、不需要 npm、也没有构建配置。

跨语言边界只传字符串：

```moonbit
extern "js" fn js_publish(
  api : (String, String, String, String) -> String,
) -> Unit
```

一个「字符串进、字符串出」的函数。让结构化值穿过 FFI 边界是浏览器 demo
最容易长出「没人愿意维护的胶水层」的地方，所以这里刻意不这么做。

`web/pdf417.js` 是**构建产物**，随仓库版本化只是为了让页面能在静态托管上
直接打开（GitHub Pages、内网 nginx 都行），不需要读者装 MoonBit 工具链。
改动了 `src/` 或 `cmd/web/` 之后记得重跑 `scripts/build_web.py`，
CI 里有一项会重新构建并检查是否有 diff。

## 页面能做什么

- **编码**：输入文本或十六进制字节，选择列数（1–30）、纠错级别（0–8），
  输出 SVG 条码 / 终端网格 / 几何摘要 / 码字流。SVG 可以直接用手机扫。
- **解码**：把「终端网格」的输出原样粘进去，解回字节，
  并显示行指示符恢复出的几何、未精确匹配的字符数、实际修正的码字数。

两个数字是分开的，因为它们说明两件不同的事：

- `unmatched` —— 有多少个符号字符的 17 个模块没精确匹配上任何图案（物理损伤程度）；
- `corrected` —— Reed-Solomon 实际修正了多少个码字（纠错余量还剩多少）。

**整字符被替换**时图案仍然精确匹配，`unmatched` 是 0 而码字是错的；
**位级划伤**时图案不在表里，`unmatched` 加一，但最近邻匹配可能把码字
「吸」回正确值，此时 `corrected` 反而是 0。
