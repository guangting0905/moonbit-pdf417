# moonbit-pdf417

MoonBit 从零实现的 **PDF417（ISO/IEC 15438）二维条码编解码器**：纯 MoonBit、
零第三方依赖、跨 wasm／js／native 一致。

```moonbit
let symbol = try! @pdf417.encode("hello", @pdf417.EncodeOptions::new(6, 2))
println(@pdf417.to_svg(symbol.matrix(), @pdf417.RenderOptions::default()))

let decoded = try! @pdf417.decode_matrix(symbol.matrix())
println(decoded.payload())                    // "hello"
println(decoded.report().corrected_errors())  // Reed-Solomon 修正了几个码字
```

- 编码：三种压缩模式（文本／字节／数字）、GF(929) Reed-Solomon 纠错、
  行指示符与布局、PBM／SVG／终端文本三种输出。
- 解码：符号字符图案匹配、行指示符多数表决恢复几何、Berlekamp-Massey + Forney
  纠错、逆压缩还原字节。
- 证据：127 条与独立参考实现的一致性向量、202 个单元测试、
  错误注入恢复、以及用 zxing-cpp 读回生成位图。

完整说明、验收命令与已知边界见仓库根目录的 [README.md](https://github.com/guangting0905/moonbit-pdf417)。
