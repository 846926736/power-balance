# 续航天平 PowerBalance v2.7.5 测试报告

## 版本

- 版本：v2.7.5
- versionCode：17
- 基线：v2.7.4 / versionCode 16

## 本次改动

- GPU 极端档遇到没有 `available_frequencies` 的 devfreq 设备时回退到 `min_freq`，不再写 0。
- CPU / GPU 都先备份 `max_freq` 再改 `min_freq` / 调度器，备份失败不留下半套改动。
- 卸载前先停止仍在轮询的 service，避免 uninstall 还原后被重新压频。
- 日志导出逐目录回退，并校验文件真实非空；失败不会再误报成功。
- WebUI 配置保存改为临时文件 + `mv` 原子替换。
- WebUI 增加 service 存活探测；state 残留但进程已退出时显示「状态残留 · 服务未运行」。

## 回归结果

- 模块回归：**30 / 30 通过**
  - T19：GPU 无频率表 extreme 回退 `min_freq`（200000000 / 200000000）。
  - T20：CPU `max_freq` 备份失败时 `min_freq` 保持不变。
  - T21：卸载前停止后台 service，并完成还原。
- WebUI 回归：**133 / 133 通过**
  - 新增服务存活探测、配置原子写入、导出落盘校验、残留状态四项检查。
- DOM ID：**50 个**，唯一，无重复或缺失
- `dash -n`：service / action / customize / uninstall 全部通过
- `node --check`：通过
- 安装器自检：显示 `v2.7.5 / versionCode 17`，模块 30 项 / UI 133 项通过
- 成品包 `unzip -t`：通过
- **直接用成品包内的脚本/HTML 重跑**：模块 30/30、WebUI 133/133，均通过
- 成品包逐文件与源码 `cmp` 一致，脚本权限 755 保留

## 成品

- 文件：`power-balance-magisk-v2.7.5.zip`
- 大小：242,995 bytes
- SHA256：`859af75c2d2a056962f12ed2288e19e864dc3a5399d7c78b3370693197e26a0f`

## 发布状态

- v2.7.5 发布到 GitHub Release，发布后为 Latest。
- 已发布的 v2.7.4 保留（SHA256 `909d...925d`）。
- 仓库：`https://github.com/846926736/power-balance`

## 未做 / 风险

- 未在真机 Magisk 环境刷入；具体 ROM 的 sysfs 差异、GitHub 按钮实际拉起浏览器仍需真机确认。
- 本次发布 v2.7.5 到 GitHub Release。
