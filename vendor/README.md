# 已包含的第三方源码快照

为兼容 GitHub 网页一次最多上传 100 个文件的限制，1,051 个实际源码及资源文件统一保存在 `vendor-sources.tar.gz`。Build 会先校验 `VENDOR_ARCHIVE.sha256`，再自动安全解包，无需手工处理。

| 目录 | Commit | 文件数 |
| --- | --- | ---: |
| QModem | `c49654efc870f53712ee8e25bf181722eb1466d9` | 776 |
| luci-theme-argon | `182294b07f985088b40610f80ec867fe167e41db` | 57 |
| luci-app-aw1k-led | `a8e3537366d74958fbc31046a762769918a4651f` | 17 |
| luci-app-openclash | `c3a33c1d3407956fdf8f0e0b7c1a4c52e6ad9593` | 201 |

普通构建使用本地压缩快照，手动运行 `Sync Third-Party Vendor Sources` 才会更新。同步工作流会重新生成压缩包，并从仓库删除旧版散装的 `vendor/packages/` 文件树。

OpenClash 保存用于编译的 `luci-app-openclash/` 子目录及上游许可证；QModem、Argon、AW1000 LED 保存完整源码树。Mihomo 核心由 OpenClash 按需下载。

LED 补丁在解包后的构建副本上应用，不修改压缩快照。
