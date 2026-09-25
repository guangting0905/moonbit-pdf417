# Git hooks

本仓库带一个轻量的 pre-commit 钩子：`moon check` + `moon test`。

默认不生效，需要一次性开启：

```sh
git config core.hooksPath .githooks
```

**为什么只跑这两条**：钩子必须快，否则会被绕过。随机往返与 zxing-cpp 验证较重，
留在 CI 里跑；提交前能拦住的是「类型不过」和「单测回归」这两类最常见的问题。

钩子在找不到 `moon` 时会直接放行并打印提示，避免在没有工具链的机器上把提交堵死。
