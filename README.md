# 续航天平 PowerBalance

一个面向 Android 的 Magisk 模块：电量低或息屏时自动给 CPU / GPU 降频省电，条件结束后按原值还原。

**当前版本：v2.7.3 / versionCode 15**

## 功能

- 电量低于阈值时自动限制 CPU 最大频率，回充后自动恢复。
- 息屏后按配置降频，亮屏后恢复。
- GPU 支持 kgsl / Mali / g3d / gpufreq 等主流平台，自动识别。
- 温度保护优先，高温时优先降频。
- 改动前备份原值，退出、卸载或关闭模块时还原。
- WebUI：设备信息、14 节状态、运行日志、日志导出。
- WebUI：作者主页入口、打赏码点按。

## 安装

1. 设备已安装 Magisk 20.4+。
2. 下载 Release 中的 `power-balance-magisk-v2.7.3.zip`。
3. 在 Magisk「模块 → 从本地安装」选择 zip，刷入后重启。
4. 打开模块 WebUI 调整阈值、轮询间隔和降频策略。

## 配置与日志

- 配置：`/data/adb/modules/power-balance/config`
- 运行日志：`/data/adb/modules/power-balance/service.log`
- WebUI「运行日志 → 导出」会写入 `Download/PowerBalance-log-时间.txt`。

## 验证

- v2.7.3 模块回归：27/27 通过。
- WebUI 回归：121/121 通过。
- DOM ID：49 个，唯一。
- 安装包已附带在 Release 中。

## 说明

- 模块会修改 sysfs 调频节点；请确认设备与内核支持后再使用。
- 作者：酷安 [@一颗初心](https://www.coolapk.com/u/1361950)。
- WebUI 内含作者支付宝 / 微信打赏码，仅用于自愿支持。
