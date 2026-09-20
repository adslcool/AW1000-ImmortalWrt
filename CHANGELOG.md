# v10.5.1 Build Fix v8.2 — 2026-09-20

- 将四个 Vendor 项目的 1,051 个实际文件封装为 `vendor/vendor-sources.tar.gz`，仓库交付文件数降至 GitHub 网页可一次上传的范围。
- 增加 SHA256 完整性检查和 tar 路径/链接安全检查；普通 Build 自动解包，不需要先同步 Vendor。
- Vendor Sync 改为生成确定性压缩快照，并在同步提交中删除旧版散装 `vendor/packages/` 树。
- 构建缓存键加入 Vendor 压缩包校验文件；新增压缩快照回归测试。

# v10.5.1 Build Fix v8.1 — 2026-09-20

基于用户回传的 GitHub Actions 运行 `35515202960` 修复最终 rootfs revision 校验失败。该运行的固件编译步骤已经成功，随后在 `Verify release rootfs and image manifest` 停止。

- 根因是单分支 clone 后切换 detached HEAD，使 ImmortalWrt `scripts/getver.sh` 无法找到跟踪分支，生成 `r0+38135-0c4cd0f992`；而 `/etc/openwrt_release` 的 `DISTRIB_REVISION` 使用该值，不使用 `CONFIG_VERSION_CODE`。
- 新增 `scripts/stamp-source-revision.sh`，把所选正式版 `version.buildinfo` 的 revision 写入源码树 `version` 文件，并在编译前验证 `getver.sh` 输出完全一致。
- 最终镜像校验失败时同时显示期望值和实际值，便于后续定位。
- Vendor Sync 强制记录被上游嵌套 `.gitignore` 忽略的资源，并从 sparse clone 直接导出 OpenClash 根许可证，后续同步不会再丢失这些文件。
- 新增回归测试覆盖 detached HEAD revision 覆盖和错误详情；其余 Vendor、硬件、网络、代理和 LED 配置保持不变。

# v10.5.1 Build Fix v8 — 2026-09-20

基于 v10.5.1 Build Fix v7 完整仓库继续修改。本次完整源码交付已补齐四个 Vendor 项目的实际源码和许可证，首次 Build 无需先同步。

- 修复 `config/version.config` 未被合并，VERSIONOPT 未启用导致正式版本号被 Kconfig 清除的问题；同时开启 IMAGEOPT。
- 构建表单支持明确正式版本号，或自动选择最新 25.12.X 正式版；保持主源码与官方 feeds 的 release commit 一致。
- 保留官方 revision，不再用项目名称替代源码 revision；项目版本单独记录。
- 用真实 sysfs 控制和主备状态判定替换 v7 只打印日志、固定返回成功的 LED 代码。
- 给原 LED 插件增加 5G 控制权判断；保留其他 LED 与夜间模式。
- 禁止只读到一半的主备状态，按新探测样本累计连续失败；3 次失败红色常亮，2 次成功恢复。
- 修复旧首启脚本关闭所有 LED trigger 的行为，只处理 5G 三色灯。
- 补全只读 LED 诊断，检查实际源码补丁与脚本执行权限。
- 编译后要求真实 rootfs、设备包清单与固件输出存在；旧的几个误报/空检查入口统一调用实际验证器。
- 普通构建不再在 Vendor 缺失时回退到上游 HEAD；需要先同步快照。
- 更新 README、manifest 与验证说明，使其反映 OpenClash / 无预装核心 / 无 Xray / 无 SSR Plus 的实际配置。

验证结果及未验证部分见 VALIDATION.md。
