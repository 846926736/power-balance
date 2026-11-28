# 续航天平 PowerBalance v2.7.7 测试报告

## 版本

- 版本：v2.7.7
- versionCode：19
- 基线：v2.7.6 / versionCode 18

## 本次改动

- WALT `hispeed_freq` 改为只降不升：目标高于当前 hispeed 时保持原值，只有目标更低时才备份并写入。
- WALT 节点按 `policyN/walt/hispeed_freq` 探测，缺失时跳过。
- governor 写入后读回校验，失败记录 `gov not applied`。
- 新增 governor 漂移日志 `drift: gov:policyN=当前->期望`，只记录、不回写。
- WebUI 增加「夸克更新」入口；打赏入口移到「核心控制」上方；打赏卡片改为金色高亮样式，突出“制作不易、金额随意”；版本号保持 v2.7.7 / 19 不变。

## 回归结果

- 模块回归：**38 / 38 通过**
  - T27a：WALT hispeed 低于目标时不被抬高。
  - T27b：WALT hispeed 高于目标时被压低。
  - T28：governor 漂移只记录、不回写。
- WebUI 回归：**138 / 138 通过**
- `dash -n`：service / action / customize / uninstall 全部通过
- `node --check`：通过
- 成品包 `unzip -t`：通过

## 实机验证

设备：OnePlus Ace 3 Pro（PJX110），Android 17 / SDK 37 / arm64-v8a，Magisk 31.1。

- v2.7.7 覆盖安装后重启，模块版本 v2.7.7 / 19，服务 PID 2702 自启。
- 4 个 CPU policy：policy0 / policy2 / policy5 / policy7；WALT 节点为 `policyN/walt/hispeed_freq`。
- 原厂 hispeed：1344000 / 1612800 / 1612800 / 1593600。
- 临时 `gov_switch=0` + 手动 `walt`，切到 `level=balanced`：
  - max 目标：1459200 / 2035200 / 1920000 / 2380800，均高于原厂 hispeed。
  - 4 个 hispeed 仍为 1344000 / 1612800 / 1612800 / 1593600，没有被抬高。
- 切到 `level=light`：max 目标升高，WALT 按设计未写入，hispeed 保持不变。
- 观察到 governor 漂移日志：
  - `drift: gov:policy0=walt->conservative; ... (ROM override?)`
  - 只记录一次，没有每轮刷屏；实际 governor 保持 `walt`，模块没有回写。
- 测试后恢复用户配置：`mode=always`、`level=balanced`、`gov_switch=1`；state 为 `APPLY balanced|1|0|1|`，GPU 目标 629000000。
- 电池 96%、38.4℃，未触发 45℃ 高温保护。
- `/data/local/tmp` 下临时脚本、配置备份、旧版 service 备份和候选包已清理。

## 成品

- 文件：`power-balance-magisk-v2.7.7.zip`
- 大小：244,738 bytes
- SHA256：`340c09502d990f460b14452937789095f40a01355bf02eca47c21a2c24d2824f`

## 未做 / 风险

- 只在 OnePlus Ace 3 Pro / Android 17 / Magisk 31.1 上做了实机验证；MediaTek、三星及其他 OEM 的节点差异仍需更多真机覆盖。
- WALT 处理只对存在 `policyN/walt/hispeed_freq` 的平台生效；没有该节点的平台自动跳过。
- governor 漂移日志是诊断信息，不会强行把 governor 改回模块期望值。
- GitHub 上传按用户确认实机可用后再执行。
