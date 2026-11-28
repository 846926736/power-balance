# 续航天平 PowerBalance

一个面向 Android 的 Magisk 模块：电量低或息屏时自动给 CPU / GPU 降频省电，条件结束后按原值还原。

**当前版本：v2.7.7 / versionCode 19**

## 功能

- 电量低于阈值时自动限制 CPU 最大频率，回充后自动恢复。
- 息屏后按配置降频，亮屏后恢复。
- CPU 按 `cpufreq/policy*` 自动发现，不绑定核心数或集群布局。
- GPU 支持 kgsl / Mali / g3d / gpufreq 等主流平台，自动识别；`*bus*` 节点自动排除。
- WALT 机型只在 `walt/hispeed_freq` 存在时处理，且只降不升，不会把原厂较低的 hispeed 抬高。
- 温度保护优先，高温时优先降频。
- 改动前备份原值，退出、卸载或关闭模块时还原。
- 运行中修改 `gov_switch`、`core_off`、`gpu_devices` 后，下一轮自动重套用，不需要重启服务。
- governor 被 ROM 改回时记录 `drift:` 日志，只诊断、不回写，避免和系统性能/温控服务互相覆盖。
- WebUI：设备信息、15 节状态、运行日志、日志导出。
- WebUI：GitHub / 夸克更新入口，直达最新 Release 或夸克网盘。
- WebUI：service 存活探测，state 残留时提示“服务未运行”。
- WebUI：作者主页入口、打赏码点按；支持作者卡片为金色高亮样式，位于核心控制上方。

## 安装

1. 设备已安装 Magisk 20.4+。
2. 下载 Release 中的 `power-balance-magisk-v2.7.7.zip`。
3. 在 Magisk「模块 → 从本地安装」选择 zip，刷入后重启。
4. 打开模块 WebUI 调整阈值、轮询间隔和降频策略。

## 配置与日志

- 配置：`/data/adb/modules/power-balance/config`
- 运行日志：`/data/adb/modules/power-balance/service.log`
- WebUI「运行日志 → 导出」会写入 `Download/PowerBalance-log-时间.txt`。

## 下载

- GitHub Release：https://github.com/846926736/power-balance/releases/tag/v2.7.7
- 夸克网盘：https://pan.quark.cn/s/d0f39f0fba86

## 验证

- v2.7.7 模块回归：38/38 通过。
- WebUI 回归：138/138 通过。
- 实机：OnePlus Ace 3 Pro / Android 17 / Magisk 31.1，覆盖安装后重启，服务自启；balanced 档下 4 个 WALT hispeed 均保持原厂值，没有被抬高。
- 实机观察到 governor 被 ROM 从 `conservative` 改回 `walt`，模块只记录 `drift:`，没有回写。

## 说明

模块只写入 CPU 频率、调度器、部分大核在线状态和标准 devfreq GPU 频率节点；所有写入都经过白名单校验并可还原。不同 ROM 的节点命名可能有差异，识别不到时会跳过对应设备。通用性来自节点探测和缺失即跳过，不代表所有机型都已逐一实测。
