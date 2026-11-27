# 续航天平 PowerBalance v2.7.6

**小改版：v2.7.5 → v2.7.6 · versionCode 17 → 18**

本日志只列与上一版 **v2.7.5** 的差异。

## 新增

- 运行中修改 `gov_switch`、`core_off` 或 `gpu_devices` 后，服务下一轮自动还原并按新配置重套用，不需要等省电条件结束或重启模块。

## 修复

- CPU 某个集群 `scaling_max_freq` 写入失败时，立即回滚本轮 CPU 改动；不会再留下 `scaling_min_freq`、调度器已改、`max_freq` 没生效的半套状态。

## 优化

- `state` 文件新增生效配置签名（`APPLY` 行）；档位、`gov_switch`、`core_off`、`gpu_save`、`gpu_devices` 变化时精确触发重套用，避免旧配置残留到省电结束。
