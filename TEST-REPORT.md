# 续航天平 PowerBalance v2.7.6 测试报告

## 版本

- 版本：v2.7.6
- versionCode：18
- 基线：v2.7.5 / versionCode 17

## 本次改动

- 运行中修改 `gov_switch`、`core_off`、`gpu_devices` 后，下一轮自动还原并按新配置重套用。
- CPU 某个集群 `scaling_max_freq` 写入失败时，整套回滚本轮 CPU 改动，避免留下半套 min/调度器状态。
- `state` 文件增加生效配置签名（`APPLY` 行），配置变化时精确触发重套用。

## 回归结果

- 模块回归：**35 / 35 通过**
  - T22：运行中改 `gov_switch`，governor 正确切到 conservative。
  - T23：运行中改 `core_off`，cpu7 先下线，再恢复在线。
  - T24：CPU max 写入失败，整套 CPU 回滚，min/governor 保持原值。
  - T25：运行中改 `gpu_devices`，旧 GPU 还原、新 GPU 限频。
  - T26：旧版 state 无 APPLY 签名时升级后自动重套用。
- WebUI 回归：**133 / 133 通过**
- DOM ID：**50 个**，唯一，无重复或缺失
- `dash -n`：service / action / customize / uninstall 全部通过
- `node --check`：通过
- 成品包 `unzip -t`：通过
- **直接用成品包内脚本重跑模块回归**：35/35 通过
- **直接用成品包内 HTML 重跑 WebUI 回归**：133/133 通过
- 成品包逐文件与源码 `cmp` 一致，脚本权限 755 保留

## 成品

- 文件：`power-balance-magisk-v2.7.6.zip`
- 大小：243,326 bytes
- SHA256：`15ca994bde3557bc227702d098af33778535c581fba8edd692f9b0982e658e78`

## 未做 / 风险

- 未在真机 Magisk 环境刷入；具体 ROM 的 sysfs 差异仍需真机确认。
- GitHub 上传按用户确认可用后再执行。
