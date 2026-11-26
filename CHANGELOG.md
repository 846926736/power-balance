# 续航天平 PowerBalance v2.7.5

**小改版：v2.7.4 → v2.7.5 · versionCode 16 → 17**

本日志只列与上一版 **v2.7.4** 的差异。

## 修复

- GPU 极端档遇到没有 `available_frequencies` 的 devfreq 设备时，不再把 `min_freq` / `max_freq` 写成 0，改为回退当前最低频；读不到最低频则跳过该 GPU。
- CPU / GPU 都改为**先备份 `max_freq`，再改 `min_freq` / 调度器**。备份失败时不会留下“min 已压低、max 没有备份”的半套改动。
- 卸载前先停止仍在轮询的 service，避免 uninstall 还原完成后又被服务下一轮重新压频。
- 日志导出逐目录回退，并校验文件真实非空；不再出现“提示导出成功但文件没写进去”。
- WebUI 保存配置改为临时文件 + `mv` 原子替换，避免服务读到写了一半的 config。

## 优化

- WebUI 增加 service 存活探测：state 还在但进程已退出时显示「状态残留 · 服务未运行」，不再误显示「省电中」。
- 保留 v2.7.4 的 GitHub 更新入口、作者主页、打赏码点按和空 `exclude` 跳过 `dumpsys activity` 优化。

## 验证

- 模块回归：**30 / 30 通过**
- WebUI 回归：**133 / 133 通过**
- DOM ID：**50 个**，唯一，无重复或缺失
- `dash -n`、`node --check`、安装器自检、成品包校验全部通过。

## 发布状态

- v2.7.5 发布到 GitHub Release，发布后为 Latest。
- 已发布的 v2.7.4 保留。