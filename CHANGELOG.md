# 续航天平 PowerBalance v2.7.7

**小改版：v2.7.6 → v2.7.7 · versionCode 18 → 19**

本日志只列与上一版 **v2.7.6** 的差异。

## 修复

- WALT `hispeed_freq` 改为只降不升：balanced / extreme 档先读当前值，仅当目标频率低于当前 hispeed 时才写入；原厂 hispeed 本来就低于模块目标时保持原值，不再把调度阈值抬高。
- WALT 节点改为按 `policyN/walt/hispeed_freq` 探测，节点不存在时自动跳过，不影响非 WALT 平台。

## 优化

- governor 写入后增加读回校验；写不进去时记录 `gov not applied`，便于区分“写入失败”和“被 ROM 改回”。
- 新增 governor 漂移日志：`gov_switch=1` 且处于省电状态时，若实际 governor 与期望不一致，记录 `gov:policyN=当前->期望`；只记录，不回写，避免和 ROM 温控/性能服务互相覆盖。

## 兼容性

- 没有新增机型判断，没有写死 OnePlus / 高通路径；CPU 继续按 `cpufreq/policy*` 自动发现，GPU 继续按 `devfreq/*` 自动发现。
- `kgsl-busmon` 等 `*bus*` 节点继续排除，不会被限频。

## 验证

- 模块回归 38/38，WebUI 回归 138/138。
- OnePlus Ace 3 Pro 实机：balanced 档下 4 个 WALT hispeed 保持原厂值；观察到 ROM 改回 governor 时只记录 drift，不回写。

## 同版本修订（versionCode 19 不变）

- WebUI 底部增加「夸克更新」入口，打开夸克网盘分享页。
- 打赏入口从页脚移到「核心控制」上方。
- 打赏卡片改为金色高亮样式，文案强调“制作不易，打赏多少无所谓，都是持续更新的动力”。
