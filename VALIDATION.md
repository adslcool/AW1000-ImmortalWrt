# Build Fix v8.2 验证记录

验证日期：2026-09-20。

## 已完成

- 12 项本地回归测试通过：Shell 语法、版本合并与重复执行、detached HEAD revision 覆盖、Vendor 压缩快照校验与解包、非法版本拒绝、实际镜像验证器的正反例、状态文件原子发布、LED 主备颜色、失败只按新样本计数、故障恢复防抖、状态过期/缺失与夜间模式、只读诊断。
- Vendor 压缩快照 SHA256 校验通过，安全解包后仍为 1,051 个文件；四个必需 Makefile 与 OpenClash 上游许可证存在。仓库交付文件总数低于 GitHub 网页单次上传的 100 文件限制。
- 两个 GitHub Actions 工作流 YAML 可以解析。
- 使用上游 `package/base-files/image-config.in` 与 Kconfiglib 验证版本开关：旧配置只写 VERSION_NUMBER 时该值被清除；启用 IMAGEOPT / VERSIONOPT 后，25.12.2 和官方 revision 均被保留。
- 使用真实 `luci-app-aw1k-led` 上游脚本（取样 commit `a8e3537366d74958fbc31046a762769918a4651f`）测试补丁：无 SINR 时原脚本会尝试写红灯；补丁在角色控制开启时阻止 5G 写入，同时保留其他 LED 的行为；关闭角色控制后上游恢复控制。补丁重复执行不重复插入。
- 在线解析明确版本 `25.12.2` 与 `auto` 均成功并解析到 25.12.2：主源码 revision `r38135-0c4cd0f9920a`，官方 LuCI commit `d6167ea0645cbd1327708d85f94824f42d0eb872`。此前日志出现这两个 commit 本身不能证明源码不属于正式版；必须同时看版本配置及最终 rootfs。
- GitHub Actions 运行 `35515202960` 的 `Build firmware` 步骤成功，说明完整交叉编译已完成；随后旧版校验发现 rootfs revision 不一致并停止，因此没有进入产物收集。复现确认：正确 commit 在单分支 detached HEAD 下由上游 `getver.sh` 生成 `r0+38135-0c4cd0f992`；写入官方 `version` 覆盖后输出精确恢复为 `r38135-0c4cd0f9920a`。

回归测试使用临时目录模拟 sysfs、UCI 和探测结果，没有改动测试主机的 `/sys/class/leds`。Kconfig 测试没有运行完整 OpenWrt 构建；与版本选项无关的生成 feeds 配置使用空测试文件。

## 尚未完成

- v8.2 的 GitHub Actions 全流程重跑及产物收集（旧版编译阶段已成功）。
- 在 AW1000 实机上验证 5G 红灯、SIM 拨号、夜间模式、有线/5G 切换与分区兼容性。
- 用户现有 Vendor 快照版本的实际编译。若该快照 LED 代码已改成不同结构，补丁会明确停止，要求核对实际源码。

本 ZIP 是完整构建仓库源码，不是已编译固件；测试通过不等同于实机验证完成。

## 实机回传信息

刷入成功后可提供以下只读输出：

```sh
cat /etc/openwrt_release
/usr/sbin/aw1000-led-status
```

如 LED 仍异常，状态中包含角色、实际各通道 brightness/trigger、最新健康样本、连续失败数和服务状态，可继续定位。
