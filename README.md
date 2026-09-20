# AW1000 ImmortalWrt v10.5.1 Build Fix v8.2

用于 Arcadyan AW1000 的完整 GitHub Actions 构建仓库。以 `v10.5.1-LTS-Build-Fix-v8.1-FULL` 为基础，保留原有目录与硬件适配。本包已包含 QModem、Argon、AW1000 LED、OpenClash 的实际源码快照，并将 1,051 个 Vendor 文件封装成一个校验压缩包，使整个仓库低于 GitHub 网页单次上传的 100 文件限制。解压后可直接上传并运行 Build。GitHub Actions 运行 `35515202960` 已完成固件编译，但旧版在编译后的 revision 校验处停止，未收集产物；v8.1 已修复该问题，v8.2 进一步解决网页上传文件过多。AW1000 实机验证尚待执行。“LTS”是本项目维护策略名称，不是额外承诺官方支持周期。

## 本次修复

1. **版本配置真正进入构建**：先合并 `config/version.config`，启用 `CONFIG_IMAGEOPT=y` 和 `CONFIG_VERSIONOPT=y`，再执行 `make defconfig`。检查最终配置，编译后检查安装根目录中的 `/etc/openwrt_release` 和设备镜像包清单。
2. **运行构建时选择版本**：`immortalwrt_version` 填 `25.12.2` 等已发布正式版；填 `auto` 自动选择支持 AW1000 的最新 **25.12.X** 正式版。明确版本不可用时停止，不自动改选其他版本。
3. **来源可追溯**：主源码 checkout 到该 release 的 `version.buildinfo` 对应 commit；官方 feeds 使用 `feeds.buildinfo` 中的精确 commit。版本号和 revision 都来自同一正式发布，不把移动分支改名伪装成正式版。
4. **替换 v7 的 LED 占位代码**：实际写入 `red:5g`、`green:5g`、`blue:5g` 的 sysfs 节点；补丁让上游 `ledstatus` 停止改写这些通道的颜色和 heartbeat trigger。其余 LED 继续由原插件控制。
5. **消除半份状态和重复计数**：failover 完成探测后原子发布状态；LED 每个新探测样本最多计数一次，连续 3 个失败样本才亮红，连续 2 个成功样本后恢复。默认故障红色常亮，不主动周期闪红。
6. **第三方固定**：普通 Build 只使用已同步的 Vendor 快照；缺少快照时明确停止，避免回退到上游当天 HEAD。
7. **修复 detached HEAD 的 revision**：正式版 commit 仍精确固定，同时将 `version.buildinfo` 的官方 revision 写入源码树 `version` 文件；构建前立即用 `scripts/getver.sh` 核对，确保最终 `/etc/openwrt_release` 的 `DISTRIB_REVISION` 是官方值，而不是 `r0+...`。
8. **适配 GitHub 网页上传**：四个 Vendor 项目的 1,051 个文件保存在 `vendor/vendor-sources.tar.gz`，并用 `VENDOR_ARCHIVE.sha256` 防止损坏。构建自动验证、安全解包；第三方 commit 与源码内容没有删减。

详细验证范围见 `VALIDATION.md`，变更见 `CHANGELOG.md`。

## 在 GitHub 编译

将 ZIP 解压后的仓库内容放到仓库根目录，包括 `.github/`、`config/`、`scripts/`、`files-template/`、`patches/` 和 `vendor/`。

1. 仓库 `Settings → Secrets and variables → Actions` 中设置：
   - `ROOT_PASSWORD`：root / LuCI / SSH 密码。
   - `WIFI_PASSWORD`：2.4G / 5G 共用的 Wi-Fi 密码，至少 8 个字符。
2. 将 `vendor/vendor-sources.tar.gz` 和 `vendor/VENDOR_ARCHIVE.sha256` 一并上传。本包总文件数低于 100，适合网页直接上传；无需先运行 Vendor Sync。以后需要升级第三方时，才手动运行 `Sync Third-Party Vendor Sources`；该更新工作流需要仓库允许 Actions 写入内容。
3. `Actions → Build AW1000 ImmortalWrt → Run workflow` 填写：

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| immortalwrt_version | auto | 最新 25.12.X 正式版，或填写明确版本如 25.12.2 |
| hostname | AW1000 | 设备名称 |
| ssid_2g | AW1000-2G | 2.4G SSID |
| ssid_5g | AW1000-5G | 5G Wi-Fi SSID |

`vendor/vendor-sources.tar.gz` 内含 1,051 个上游源码及资源文件，具体 commit 记录在 `vendor/VENDOR_COMMITS.txt`。Build 优先使用并校验该压缩快照，即使旧仓库中还残留散装的 `vendor/packages/` 也不会混用。需要清理旧文件时，上传本版后手动运行一次 `Sync Third-Party Vendor Sources`，工作流会提交删除旧树。本包是完整在线构建仓库：Actions 会自动取得所选版本的 ImmortalWrt 主源码、官方 feeds 及编译依赖；第三方组件直接使用包内固定快照。

## 固定配置

| 项目 | 当前设置 |
| --- | --- |
| Target / Device | qualcommax/ipq807x / arcadyan_aw1000 |
| LAN | 192.168.8.1/24；LAN1–LAN4 为 br-lan |
| DHCP | 192.168.8.10–192.168.8.99 |
| WAN | 第 5 个物理 2.5G 网口；默认 DHCP，可在 LuCI 改 PPPoE |
| 主备 | 有线公网健康时优先；故障切换 5G，恢复后切回 |
| RG500Q-EA | USB / qmi_wwan_q / wwan0 或 wwan0_1；热备拨号；启动延迟 25 秒 |
| Wi-Fi | 中国 CN；2.4G HE20 / 信道 1；5G HE80 / 信道 149 |
| Wi-Fi 加密 | WPA2/WPA3 Mixed；802.11k/v 开启，802.11r 关闭 |
| 时区 | Asia/Shanghai |
| 界面 | 中文 LuCI、Argon；不安装 argon-config |
| 代理管理 | OpenClash；固件不预装 Mihomo 核心，由 OpenClash 按需下载 |
| 保留 | QModem、短信兼容补丁与诊断、BBR、FileManager、ZeroTier、TTYD、UPnP、IPv6、USB 存储 |
| 默认禁用服务 | ZeroTier、TTYD、Watchcat |
| 不集成 | SSR Plus、Xray-core、PassWall、DDNS、NSS、TurboACC、SFE、mwan3、Docker |

固件不包含 RG500Q-EA 模组固件，不修改 MIBIB。保留原项目针对已完成 701 MiB 扩容设备的配置；此版本没有重新进行分区兼容性实机测试。

## 5G 角色灯

| 状态 | 默认颜色 |
| --- | --- |
| 有线主用，5G 探测健康、保持备用 | 蓝色常亮 |
| 5G 主用且探测健康 | 绿色常亮 |
| 有线失败或恢复的连续确认阶段 | 黄色常亮 |
| 5G 有默认路由，但连续 3 个完整公网探测样本失败 | 红色常亮 |
| 启动尚未获得状态、5G 无可用路由、状态超过 120 秒未更新 | 熄灭，诊断输出说明原因 |
| 夜间模式生效 | 熄灭 |

短暂探测失败保持之前的角色颜色。故障红灯恢复须连续 2 个成功样本。计数按 failover 完成的探测轮次，不是按 LED 的 2 秒刷新次数；每轮耗时包含 ping 等待。

角色颜色与阈值：`/etc/config/aw1000-5g-role-led`。保留旧配置升级时，未设置的新增项使用脚本默认值。控制器不发送 AT 命令，不反复写 UCI/Flash。上游夜间模式与本控制器使用同一状态标记和时间设置。

只读诊断：

```sh
/usr/sbin/aw1000-led-status
/usr/sbin/aw1000-failover status
/usr/sbin/aw1000-sms-diag
```

5G 角色灯不表示 SINR；移动信号灯 `*:signal` 仍由上游插件表示信号质量。上游插件的 5G/SINR 色阶配置在角色控制开启时不控制这一颗灯。

## 构建输出

成功后从 Actions Artifacts 下载：

- `*arcadyan_aw1000*-sysupgrade.bin`
- `*arcadyan_aw1000*-factory.ubi`
- `*arcadyan_aw1000*-initramfs-uImage.itb`
- 源码、官方 feeds、Vendor commit 记录，`final.diffconfig`、镜像 manifest、`sha256sums.txt`。

本仓库的测试使用 `python3 -m unittest discover -s tests -v`，不需要路由器。v8.2 的完整编译成功仍须以新 Actions 产物为准；LED、拨号及故障切换仍须在 AW1000 上验证。

## 上游

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [QModem](https://github.com/FUjr/QModem)
- [AW1000 LED](https://github.com/nooblk-98/luci-app-aw1k-led)
- [OpenClash](https://github.com/vernesong/OpenClash)
- [Argon](https://github.com/jerrykuku/luci-theme-argon)
