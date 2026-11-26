# 续航天平 PowerBalance v2.7.3 测试报告

## 版本

- 版本：v2.7.3
- versionCode：15
- 基线：v2.7.2 / versionCode 14

## 本次改动

- `exclude` 排除名单为空时，跳过 `dumpsys activity activities` 前台查询，减少每轮一次 binder 调用。
- 排除名单非空时行为不变：仍识别前台应用，命中时跳过省电并记录日志。

## 回归结果

- 模块回归：**27 / 27 通过**
  - 新增 T17：空 `exclude` 不调用 `dumpsys activity`，仍正常省电。
  - 新增 T18：非空 `exclude` 仍能识别前台并跳过省电。
- WebUI 回归：**121 / 121 通过**
- `dash -n`：service / action / customize / uninstall 全部通过
- DOM ID：49 个，唯一，无重复或缺失
- 安装器自检：显示 `v2.7.3 / versionCode 15`，模块 27 项 / UI 121 项通过
- 成品包 `unzip -t`：通过，无压缩错误
- **直接用成品包内的脚本/HTML 重跑**：模块 27/27、WebUI 121/121，均通过（不是只测源码）

## 成品

- 文件：`power-balance-magisk-v2.7.3.zip`
- 大小：241,041 bytes
- SHA256：`e17646c90293fbed677a00e58477b4c47c87e2b8f9e84e2ade8835b163b0952a`

## 成品包复核

- 18 个条目，均为预期文件；没有 `config` / `stats` 等运行期文件被打进包。
- 包内 12 个文件与源码逐文件 `cmp` 一致：模块脚本、安装脚本、WebUI、配置模板、打赏资源和 META-INF。
- 脚本权限保留：`customize.sh`、`service.sh`、`action.sh`、`uninstall.sh` 为 755；`update-binary` 为 755。
- 安装入口为标准 Magisk `META-INF`；安装器从包内自检显示 v2.7.3 / versionCode 15。
- `unzip -t` 通过，未发现压缩错误或路径穿越条目。

## 未做 / 风险

- 未在真机 Magisk 环境刷入，具体 ROM 的 sysfs 差异和酷安/打赏深链仍需真机确认。
- 本次仅做本地升级和测试，GitHub 仓库当前仍为 v2.7.2。
