# 续航天平 PowerBalance v2.7.3

**小改版：v2.7.2 → v2.7.3 · versionCode 14 → 15**

本日志只列与上一版 **v2.7.2** 的差异。

## 优化

- **排除名单为空时跳过前台查询**：未配置 `exclude` 时，不再每轮调用 `dumpsys activity activities`，省掉一次 binder 查询；有排除名单时行为不变。
- **降低待机开销**：省电模式下减少不必要的系统服务调用，轮询策略和降频结果不受影响。

## 验证

- 模块回归：**27/27** 通过（新增“空 exclude 跳过查询”和“非空 exclude 仍能拦截”两项）。
- UI 回归：**121/121** 通过。
- `dash -n`、`node --check`、DOM id 唯一性、成品包 `unzip -t` 均检查。
- 实际运行测试：模拟 20% 电量 + `exclude=` 空配置，确认空 `exclude` 不调用 `dumpsys activity`，非空 `exclude` 仍能识别前台并跳过省电。

## 升级

- 覆盖安装即可，版本为 **v2.7.3 / versionCode 15**。
- 旧配置保留；v2.7.2 的电池状态识别、卸载还原保护、日志导出等均保留。
